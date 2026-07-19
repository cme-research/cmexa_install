#!/bin/bash
# Deploy a robot stack from GHCR.
#
# robot.yaml is the single source of truth for this host (identity, DDS domain,
# image versions, nav mode). This script compiles it via scripts/render_config.py
# into the generated compose env-file (.compose.env) and the mosquitto bridge
# config, then brings the stack up. CLI flags below edit robot.yaml in place.
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

CONFIG_FILE="robot.yaml"
ENV_FILE=".compose.env"
RENDER="scripts/render_config.py"

# Regex: <lowercase-distro>-<latest|semver|sha40>
VERSION_REGEX='^[a-z]+-(latest|[0-9]+(\.[0-9]+){0,2}(-[0-9A-Za-z.-]+)?|[0-9a-f]{40})$'

usage() {
  cat <<EOF
Usage: bash deploy.sh [--version <distro>-<tag>] [--webapp-version <distro>-<tag>]
                      [--robot <name>] [--instance <name>] [--domain <id>] [--nav]

Config lives in robot.yaml (the single source of truth). The flags below edit it;
omitting a flag keeps whatever robot.yaml already has. On a fresh host robot.yaml
is seeded from robot.example.yaml (or migrated from a legacy .env).

By default this deploys mosquitto, webapp, brickd and hardware only.
Pass --nav to additionally start the navigation container.

Identity (defaults preserve the production mecanum robot):
  --robot      robot type; selects launch/description/config + container names
  --instance   MQTT instance id -> cmeresearch/<instance>/... + bridge routing
  --domain     ROS_DOMAIN_ID; give robots on one subnet distinct domains

Examples:
  bash deploy.sh --version jazzy-0.1.0                # cmexaiii hardware stack
  bash deploy.sh --version jazzy-0.1.0 --nav          # cmexaiii + nav
  bash deploy.sh --version jazzy-latest --robot cmexamini --instance cmexamini-001 --domain 13 --nav

Versions must match: ${VERSION_REGEX}
EOF
}

validate_version() {
  local label="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "ERROR: ${label} is empty — pass --version <distro>-<semver> (robot.yaml has no image version yet)." >&2
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

USE_NAV=false
# Overrides collected from flags and applied to robot.yaml via render_config.
SETS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)         SETS+=(--set "images.robot_version=${2:-}");   shift 2 ;;
    --webapp-version)  SETS+=(--set "images.webapp_version=${2:-}");  shift 2 ;;
    --robot)           SETS+=(--set "identity.robot=${2:-}");         shift 2 ;;
    --instance)        SETS+=(--set "identity.instance=${2:-}");      shift 2 ;;
    --domain)          SETS+=(--set "ros.domain_id=${2:-}");          shift 2 ;;
    --nav)             USE_NAV=true;                                  shift ;;
    -h|--help)         usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

command -v python3 >/dev/null 2>&1 || {
  echo "ERROR: python3 is required (deploy uses scripts/render_config.py)." >&2
  exit 1
}

# Ensure robot.yaml exists: migrate a legacy .env, else seed from setup.sh.
MIGRATE_ARGS=()
if [ ! -f "$CONFIG_FILE" ]; then
  if [ -f .env ]; then
    echo "==> No robot.yaml — migrating legacy .env into it..."
    MIGRATE_ARGS=(--migrate-env .env)
  else
    echo "==> No robot.yaml — seeding host config via setup.sh..."
    bash setup.sh
  fi
fi

# Compile robot.yaml -> env-file + bridge.conf (persisting flag edits/migration).
WRITE_ARGS=()
if [[ ${#SETS[@]} -gt 0 || ${#MIGRATE_ARGS[@]} -gt 0 ]]; then
  WRITE_ARGS=(--write)
fi
python3 "$RENDER" --config "$CONFIG_FILE" \
  "${MIGRATE_ARGS[@]}" "${SETS[@]}" "${WRITE_ARGS[@]}" \
  --emit-env "$ENV_FILE" --render-bridge

# Load the resolved values for this script's own logic (echo, nav cleanup).
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

validate_version "ROBOT_VERSION"  "${ROBOT_VERSION:-}"
validate_version "WEBAPP_VERSION" "${WEBAPP_VERSION:-}"

COMPOSE_FILE="docker-compose.prod.yml"

PROFILE_ARGS=()
if $USE_NAV; then
  PROFILE_ARGS+=("--profile" "nav")
  NAV_LABEL="enabled"
else
  NAV_LABEL="disabled"
fi

echo "==> Deploying ${ROBOT} stack (instance: ${ROBOT_INSTANCE}, domain: ${ROS_DOMAIN_ID}, robot: ${ROBOT_VERSION}, webapp: ${WEBAPP_VERSION}, nav: ${NAV_LABEL})"

# If --nav is NOT set, stop any previously running nav container so we don't
# leave a stale one behind from an earlier full deploy.
if ! $USE_NAV; then
  if docker ps -a --format '{{.Names}}' | grep -qx "${ROBOT}-nav"; then
    echo "==> --nav not set: stopping leftover nav container..."
    docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" --profile nav stop nav 2>/dev/null || true
    docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" --profile nav rm -f nav 2>/dev/null || true
  fi
fi

echo "==> Pulling images..."
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "${PROFILE_ARGS[@]}" pull

echo "==> Starting services..."
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "${PROFILE_ARGS[@]}" up -d

# Mosquitto's image tag is unpinned (eclipse-mosquitto:latest) and its config
# is bind-mounted from docker/mosquitto/bridge.conf. Neither bind-mount content
# changes nor unchanged image digests trigger `up -d` to recreate. Force a
# recreate so config edits actually reach the running container.
echo "==> Recreating mosquitto to pick up bind-mounted config changes..."
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "${PROFILE_ARGS[@]}" up -d --force-recreate --no-deps mosquitto

echo ""
echo "==> Done. Running services:"
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "${PROFILE_ARGS[@]}" ps
