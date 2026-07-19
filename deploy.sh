#!/bin/bash
# Deploy CMEXAIII robot stack from GHCR.
#
# Robot images (cmexa_hardware, cmexa_nav) and webapp (cmeresearch_amr_webcontrol)
# share the same '<distro>-<semver>' tag scheme on GHCR. By default --version
# applies to both; pass --webapp-version to pin the webapp separately.
#
# Usage:
#   bash deploy.sh --version jazzy-0.1.0                          # pin both
#   bash deploy.sh --version jazzy-0.1.0 --webapp-version jazzy-0.1.0
#   bash deploy.sh --version jazzy-latest                         # rolling stable
#
# Accepted version formats: <distro>-<tag> where <tag> is
#   - latest                       (rolling, stable releases only)
#   - <major>                      e.g. jazzy-1
#   - <major>.<minor>              e.g. jazzy-1.4
#   - <major>.<minor>.<patch>      e.g. jazzy-1.4.0
#   - <major>.<minor>.<patch>-<id> e.g. jazzy-1.4.0-rc1
#   - <40-char-commit-sha>         e.g. jazzy-abcd1234...

set -euo pipefail

# Regex: <lowercase-distro>-<latest|semver|sha40>
VERSION_REGEX='^[a-z]+-(latest|[0-9]+(\.[0-9]+){0,2}(-[0-9A-Za-z.-]+)?|[0-9a-f]{40})$'

usage() {
  cat <<EOF
Usage: bash deploy.sh --version <distro>-<tag> [--webapp-version <distro>-<tag>]
                      [--robot <name>] [--instance <name>] [--nav]

By default this deploys mosquitto, webapp, brickd and hardware only.
Pass --nav to additionally start the navigation container.

Robot identity (defaults preserve the production mecanum robot):
  --robot     robot type; selects the ROS launch/description via the ROBOT env
              and the container names (<robot>-hardware / <robot>-nav).
              default: cmexaiii
  --instance  MQTT instance id; the cmeresearch/<instance>/... topic prefix and
              the mosquitto bridge routing. default: <robot>-001

Examples:
  bash deploy.sh --version jazzy-0.1.0                # cmexaiii hardware stack
  bash deploy.sh --version jazzy-0.1.0 --nav          # cmexaiii + nav
  bash deploy.sh --version jazzy-latest --nav
  bash deploy.sh --version jazzy-0.1.0 --webapp-version jazzy-0.2.0 --nav
  # diff-drive mini:
  bash deploy.sh --version jazzy-latest --robot cmexamini --instance cmexamini-001 --nav

Versions must match: ${VERSION_REGEX}
EOF
}

validate_version() {
  local label="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "ERROR: ${label} is empty." >&2
    usage >&2
    exit 1
  fi
  if [[ "$value" == "latest" ]]; then
    echo "ERROR: ${label}='latest' is not allowed — use '<distro>-latest' (e.g. jazzy-latest) so the ROS distro is unambiguous." >&2
    exit 1
  fi
  if ! [[ "$value" =~ $VERSION_REGEX ]]; then
    echo "ERROR: ${label}='${value}' does not match the expected '<distro>-<tag>' format." >&2
    usage >&2
    exit 1
  fi
}

ROBOT_VERSION=""
WEBAPP_VERSION=""
ROBOT_VERSION_SET=false
WEBAPP_VERSION_SET=false
USE_NAV=false
# Robot identity (type + instance). Default to the production mecanum cmexaiii /
# cmexaiii-001 so existing deploys are unaffected. A second robot type (e.g. the
# diff-drive mini) sets --robot cmexamini --instance cmexamini-001.
ROBOT=""
ROBOT_INSTANCE=""
ROBOT_SET=false
ROBOT_INSTANCE_SET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      ROBOT_VERSION="${2:-}"
      ROBOT_VERSION_SET=true
      shift 2
      ;;
    --webapp-version)
      WEBAPP_VERSION="${2:-}"
      WEBAPP_VERSION_SET=true
      shift 2
      ;;
    --robot)
      ROBOT="${2:-}"
      ROBOT_SET=true
      shift 2
      ;;
    --instance)
      ROBOT_INSTANCE="${2:-}"
      ROBOT_INSTANCE_SET=true
      shift 2
      ;;
    --nav)
      USE_NAV=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

# Generate .env if it doesn't exist yet (also sources values like INPUT_GID)
if [ ! -f .env ]; then
  echo "==> No .env found, running setup.sh first..."
  bash setup.sh
fi

# If a flag was not passed, fall back to whatever is pinned in .env.
read_env_value() {
  local key="$1"
  if grep -q "^${key}=" .env 2>/dev/null; then
    awk -F= -v k="$key" '$1==k {sub(/^[^=]+=/,""); print; exit}' .env
  fi
}

if ! $ROBOT_VERSION_SET; then
  ROBOT_VERSION="$(read_env_value ROBOT_VERSION)"
fi

# Webapp defaults to the same version as the robot when not explicitly pinned.
if ! $WEBAPP_VERSION_SET; then
  WEBAPP_VERSION="$(read_env_value WEBAPP_VERSION)"
  if [[ -z "$WEBAPP_VERSION" || "$WEBAPP_VERSION" == "latest" ]]; then
    WEBAPP_VERSION="$ROBOT_VERSION"
  fi
fi

validate_version "ROBOT_VERSION"  "$ROBOT_VERSION"
validate_version "WEBAPP_VERSION" "$WEBAPP_VERSION"

# Resolve robot identity: CLI flag > .env > default (cmexaiii / <robot>-001).
if ! $ROBOT_SET; then
  ROBOT="$(read_env_value ROBOT)"
fi
ROBOT="${ROBOT:-cmexaiii}"

if ! $ROBOT_INSTANCE_SET; then
  ROBOT_INSTANCE="$(read_env_value ROBOT_INSTANCE)"
fi
ROBOT_INSTANCE="${ROBOT_INSTANCE:-${ROBOT}-001}"

# Nav launch file: .env override, else the robot's mapping launch by convention.
# Auto-correct a launch file that does not belong to this robot (e.g. a stale
# cmexaiii default written by setup.sh when deploying the mini). An explicit
# same-robot choice (mapping vs localization) is preserved.
LAUNCH_FILE="$(read_env_value LAUNCH_FILE)"
if [[ -z "$LAUNCH_FILE" || "$LAUNCH_FILE" != ${ROBOT}_* ]]; then
  LAUNCH_FILE="${ROBOT}_nav_mapping.launch.py"
fi

COMPOSE_FILE="docker-compose.prod.yml"

PROFILE_ARGS=()
if $USE_NAV; then
  PROFILE_ARGS+=("--profile" "nav")
  NAV_LABEL="enabled"
else
  NAV_LABEL="disabled"
fi

echo "==> Deploying ${ROBOT} stack (instance: ${ROBOT_INSTANCE}, robot: ${ROBOT_VERSION}, webapp: ${WEBAPP_VERSION}, nav: ${NAV_LABEL})"

# Write version + identity overrides into .env (replace or append)
update_env() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    echo "${key}=${value}" >> .env
  fi
}

update_env "ROBOT_VERSION" "${ROBOT_VERSION}"
update_env "WEBAPP_VERSION" "${WEBAPP_VERSION}"
update_env "ROBOT" "${ROBOT}"
update_env "ROBOT_INSTANCE" "${ROBOT_INSTANCE}"
update_env "LAUNCH_FILE" "${LAUNCH_FILE}"

# Render the mosquitto bridge config for this instance from the template. The
# topic routes and remote_clientid are instance-scoped; substituting here keeps
# a single source of truth (bridge.conf.template) across robot types. For
# cmexaiii/cmexaiii-001 this reproduces the committed bridge.conf byte-for-byte.
BRIDGE_TEMPLATE="docker/mosquitto/bridge.conf.template"
BRIDGE_CONF="docker/mosquitto/bridge.conf"
if [[ -f "$BRIDGE_TEMPLATE" ]]; then
  echo "==> Rendering ${BRIDGE_CONF} for ${ROBOT_INSTANCE}..."
  sed -e "s@__ROBOT_INSTANCE__@${ROBOT_INSTANCE}@g" \
      -e "s@__ROBOT__@${ROBOT}@g" \
      "$BRIDGE_TEMPLATE" > "$BRIDGE_CONF"
fi

# If --nav is NOT set, stop any previously running nav container so we don't
# leave a stale one behind from an earlier full deploy.
if ! $USE_NAV; then
  if docker ps -a --format '{{.Names}}' | grep -qx "${ROBOT}-nav"; then
    echo "==> --nav not set: stopping leftover nav container..."
    ROBOT="${ROBOT}" LAUNCH_FILE="${LAUNCH_FILE}" \
      docker compose -f "${COMPOSE_FILE}" --profile nav stop nav 2>/dev/null || true
    ROBOT="${ROBOT}" LAUNCH_FILE="${LAUNCH_FILE}" \
      docker compose -f "${COMPOSE_FILE}" --profile nav rm -f nav 2>/dev/null || true
  fi
fi

# Env exported to every compose call: image tags + robot identity + nav launch.
COMPOSE_ENV=(
  "ROBOT_VERSION=${ROBOT_VERSION}"
  "WEBAPP_VERSION=${WEBAPP_VERSION}"
  "ROBOT=${ROBOT}"
  "ROBOT_INSTANCE=${ROBOT_INSTANCE}"
  "LAUNCH_FILE=${LAUNCH_FILE}"
)

echo "==> Pulling images..."
env "${COMPOSE_ENV[@]}" \
  docker compose -f "${COMPOSE_FILE}" "${PROFILE_ARGS[@]}" pull

echo "==> Starting services..."
env "${COMPOSE_ENV[@]}" \
  docker compose -f "${COMPOSE_FILE}" "${PROFILE_ARGS[@]}" up -d

# Mosquitto's image tag is unpinned (eclipse-mosquitto:latest) and its config
# is bind-mounted from docker/mosquitto/bridge.conf. Neither bind-mount content
# changes nor unchanged image digests trigger `up -d` to recreate. Force a
# recreate so config edits actually reach the running container.
echo "==> Recreating mosquitto to pick up bind-mounted config changes..."
env "${COMPOSE_ENV[@]}" \
  docker compose -f "${COMPOSE_FILE}" "${PROFILE_ARGS[@]}" up -d --force-recreate --no-deps mosquitto

echo ""
echo "==> Done. Running services:"
env "${COMPOSE_ENV[@]}" \
  docker compose -f "${COMPOSE_FILE}" "${PROFILE_ARGS[@]}" ps
