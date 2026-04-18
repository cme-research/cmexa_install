#!/bin/bash
# Deploy CMEXAIII robot stack from GHCR.
#
# Usage:
#   bash deploy.sh                    # deploy latest
#   bash deploy.sh --version 1.2.3   # deploy specific release

set -euo pipefail

ROBOT_VERSION="latest"
WEBAPP_VERSION="latest"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      ROBOT_VERSION="$2"
      WEBAPP_VERSION="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: bash deploy.sh [--version <semver>]"
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

# Login check — prompt if not already authenticated
if ! docker system info 2>/dev/null | grep -q "ghcr.io"; then
  if [ -z "${GHCR_TOKEN:-}" ]; then
    echo "==> Not logged in to ghcr.io."
    echo "    Set GHCR_TOKEN env var or enter a GitHub PAT with read:packages scope:"
    read -r -s -p "    PAT: " GHCR_TOKEN
    echo
  fi
  echo "${GHCR_TOKEN}" | docker login ghcr.io -u cme-research --password-stdin
fi

echo "==> Pulling images..."
ROBOT_VERSION="${ROBOT_VERSION}" WEBAPP_VERSION="${WEBAPP_VERSION}" \
  docker compose -f "${COMPOSE_FILE}" pull

echo "==> Starting services..."
ROBOT_VERSION="${ROBOT_VERSION}" WEBAPP_VERSION="${WEBAPP_VERSION}" \
  docker compose -f "${COMPOSE_FILE}" up -d

echo ""
echo "==> Done. Running services:"
docker compose -f "${COMPOSE_FILE}" ps
