#!/bin/bash
# Seed robot.yaml (the single source of truth) on a fresh host.
# Run once after cloning; then edit robot.yaml or use deploy.sh flags.

set -e

INPUT_GID=$(getent group input | cut -d: -f3)
if [ -z "$INPUT_GID" ]; then
  echo "WARNING: 'input' group not found. host.input_gid will be empty."
fi

if [ -f robot.yaml ]; then
  echo "robot.yaml already exists — leaving it untouched."
  exit 0
fi

cp robot.example.yaml robot.yaml
if [ -n "$INPUT_GID" ]; then
  # Fill the host-detected joystick GID (was INPUT_GID in the old .env).
  sed -i "s/input_gid: \"\"/input_gid: ${INPUT_GID}/" robot.yaml
fi

echo "robot.yaml created (robot=cmexaiii, input_gid=${INPUT_GID})."
echo "Edit robot.yaml or pass deploy.sh flags (e.g. --robot cmexamini --instance cmexamini-001)."
