#!/bin/bash
# Deploy CMEXAIII robot stack from GHCR.
#
# Usage:
#   bash deploy.sh                          # latest stable on jazzy (rolls forward on each release)
#   bash deploy.sh --version jazzy-1.4.0    # pinned release

set -euo pipefail

ROBOT_VERSION="jazzy-latest"
WEBAPP_VERSION="latest"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      # Robot images are distro-prefixed (e.g. jazzy-1.4.0). Webapp uses its own
      # tag scheme and is not changed by --version; pass --webapp-version for it.
      ROBOT_VERSION="$2"
      shift 2
      ;;
    --webapp-version)
      WEBAPP_VERSION="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: bash deploy.sh [--version <distro>-<semver>] [--webapp-version <tag>]"
      exit 1
      ;;
  esac
done

COMPOSE_FILE="docker-compose.prod.yml"

echo "==> Deploying CMEXAIII stack (robot: ${ROBOT_VERSION}, webapp: ${WEBAPP_VERSION})"

# Generate .env if it doesn't exist yet
if [ ! -f .env ]; then
  echo "==> No .env found, running setup.sh first..."
  bash setup.sh
fi

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

echo "==> Pulling images..."
ROBOT_VERSION="${ROBOT_VERSION}" WEBAPP_VERSION="${WEBAPP_VERSION}" \
  docker compose -f "${COMPOSE_FILE}" pull

echo "==> Starting services..."
ROBOT_VERSION="${ROBOT_VERSION}" WEBAPP_VERSION="${WEBAPP_VERSION}" \
  docker compose -f "${COMPOSE_FILE}" up -d

echo ""
echo "==> Done. Running services:"
docker compose -f "${COMPOSE_FILE}" ps
