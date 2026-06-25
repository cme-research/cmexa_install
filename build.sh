#!/bin/bash
# Build the CMEXAIII robot Docker images locally.
#
# Counterpart to deploy.sh: where deploy.sh PULLS released images from GHCR,
# this script BUILDS them from the Dockerfiles in ./docker. The images are
# tagged to match docker-compose.yml (the dev compose, "local images"), so a
# fresh build is immediately runnable with:
#
#   docker compose -f docker-compose.yml up -d
#
# Targets:
#   brickd    -> cmeresearch/brickd:1.0              (docker/Dockerfile.brickd)
#   hardware  -> cmeresearch/cmexaiii-hardware:test  (docker/Dockerfile.hardware)
#   nav       -> cmeresearch/cmexaiii-nav:test       (docker/Dockerfile.nav)
#
# Selection:
#   --all                         build all three
#   --brickd / --hardware / --nav build that one target
#   combinations of two           e.g. --hardware --nav
#   (selecting all three individually is rejected — use --all instead)
#
# Note: this is a NATIVE single-arch build for local dev/testing. Multi-arch
# release images (linux/amd64 + linux/arm64) are produced by CI on merge to
# the `jazzy` branch — see README "CI/CD Pipeline".
#
# Usage:
#   bash build.sh --all
#   bash build.sh --nav
#   bash build.sh --hardware --nav
#   bash build.sh --all --no-cache
#   bash build.sh --nav --platform linux/arm64

set -euo pipefail

# Run from the repo root regardless of the caller's cwd (build context is ./docker).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Build order. brickd, hardware and nav are independent images (no shared
# FROM), so the order is cosmetic — brickd is quickest, so it goes first.
ORDER=(brickd hardware nav)

# target -> image:tag (kept in sync with docker-compose.yml)
declare -A IMAGE=(
  [brickd]="cmeresearch/brickd:1.0"
  [hardware]="cmeresearch/cmexaiii-hardware:test"
  [nav]="cmeresearch/cmexaiii-nav:test"
)

usage() {
  cat <<EOF
Usage: bash build.sh (--all | <target>...) [--no-cache] [--platform <p>]

Build the CMEXAIII robot Docker images locally from ./docker.

Targets:
  --all         build all three images (brickd, hardware, nav)
  --brickd      build the TinkerForge brick daemon image
  --hardware    build the ros2_control / stepper / LiDAR / MQTT-bridge image
  --nav         build the Nav2 + SLAM Toolbox image

Individual targets may be combined to build two of them, e.g.
  bash build.sh --hardware --nav
To build all three, use --all (selecting all three individually is rejected).

Options:
  --no-cache        pass --no-cache to docker build
  --platform <p>    build for a specific platform, e.g. linux/arm64
  -h, --help        show this help

Images produced (match docker-compose.yml):
  brickd    -> ${IMAGE[brickd]}
  hardware  -> ${IMAGE[hardware]}
  nav       -> ${IMAGE[nav]}
EOF
}

BUILD_ALL=false
declare -A SELECTED=()
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      BUILD_ALL=true
      shift
      ;;
    --brickd)
      SELECTED[brickd]=1
      shift
      ;;
    --hardware)
      SELECTED[hardware]=1
      shift
      ;;
    --nav)
      SELECTED[nav]=1
      shift
      ;;
    --no-cache)
      EXTRA_ARGS+=(--no-cache)
      shift
      ;;
    --platform)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --platform requires a value (e.g. linux/arm64)." >&2
        exit 1
      fi
      EXTRA_ARGS+=(--platform "$2")
      shift 2
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

n_selected=${#SELECTED[@]}

if $BUILD_ALL && (( n_selected > 0 )); then
  echo "ERROR: --all cannot be combined with individual target flags." >&2
  usage >&2
  exit 1
fi

if ! $BUILD_ALL && (( n_selected == 0 )); then
  echo "ERROR: nothing selected. Pass --all, or one or more of --brickd --hardware --nav." >&2
  usage >&2
  exit 1
fi

# Combinations may build two targets; building all three must go through --all.
if (( n_selected == ${#ORDER[@]} )); then
  echo "ERROR: all three targets selected individually. Use --all to build everything." >&2
  usage >&2
  exit 1
fi

# Resolve the final target list, preserving ORDER.
TARGETS=()
for t in "${ORDER[@]}"; do
  if $BUILD_ALL || [[ -n "${SELECTED[$t]:-}" ]]; then
    TARGETS+=("$t")
  fi
done

echo "==> Building image(s): ${TARGETS[*]}"

for t in "${TARGETS[@]}"; do
  img="${IMAGE[$t]}"
  echo ""
  echo "==> [${t}] docker build -f docker/Dockerfile.${t} -t ${img} ./docker"
  docker build "${EXTRA_ARGS[@]}" \
    -f "docker/Dockerfile.${t}" \
    -t "${img}" \
    docker
done

echo ""
echo "==> Done. Built image(s):"
for t in "${TARGETS[@]}"; do
  printf '    %-9s %s\n' "$t" "${IMAGE[$t]}"
done
echo ""
echo "    Run them with:  docker compose -f docker-compose.yml up -d"
