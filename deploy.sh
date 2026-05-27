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
Usage: bash deploy.sh --version <distro>-<tag> [--webapp-version <distro>-<tag>] [--nav]

By default this deploys mosquitto, webapp, brickd and hardware only.
Pass --nav to additionally start the navigation container.

Examples:
  bash deploy.sh --version jazzy-0.1.0                # hardware stack only
  bash deploy.sh --version jazzy-0.1.0 --nav          # hardware + nav
  bash deploy.sh --version jazzy-latest --nav
  bash deploy.sh --version jazzy-0.1.0 --webapp-version jazzy-0.2.0 --nav

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

COMPOSE_FILE="docker-compose.prod.yml"

PROFILE_ARGS=()
if $USE_NAV; then
  PROFILE_ARGS+=("--profile" "nav")
  NAV_LABEL="enabled"
else
  NAV_LABEL="disabled"
fi

echo "==> Deploying CMEXAIII stack (robot: ${ROBOT_VERSION}, webapp: ${WEBAPP_VERSION}, nav: ${NAV_LABEL})"

# Write version overrides into .env (replace or append)
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

# If --nav is NOT set, stop any previously running nav container so we don't
# leave a stale one behind from an earlier full deploy.
if ! $USE_NAV; then
  if docker ps -a --format '{{.Names}}' | grep -qx cmexaiii-nav; then
    echo "==> --nav not set: stopping leftover nav container..."
    docker compose -f "${COMPOSE_FILE}" --profile nav stop nav 2>/dev/null || true
    docker compose -f "${COMPOSE_FILE}" --profile nav rm -f nav 2>/dev/null || true
  fi
fi

echo "==> Pulling images..."
ROBOT_VERSION="${ROBOT_VERSION}" WEBAPP_VERSION="${WEBAPP_VERSION}" \
  docker compose -f "${COMPOSE_FILE}" "${PROFILE_ARGS[@]}" pull

echo "==> Starting services..."
ROBOT_VERSION="${ROBOT_VERSION}" WEBAPP_VERSION="${WEBAPP_VERSION}" \
  docker compose -f "${COMPOSE_FILE}" "${PROFILE_ARGS[@]}" up -d

echo ""
echo "==> Done. Running services:"
docker compose -f "${COMPOSE_FILE}" "${PROFILE_ARGS[@]}" ps
