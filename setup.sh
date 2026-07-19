#!/bin/bash
# Generates .env with system-specific values.
# Run once after cloning on a new host, then edit LAUNCH_FILE as needed.

set -e

INPUT_GID=$(getent group input | cut -d: -f3)

if [ -z "$INPUT_GID" ]; then
  echo "WARNING: 'input' group not found. INPUT_GID will be empty."
fi

cat > .env << EOF
# Nav mode: switch between <robot>_nav_mapping.launch.py and <robot>_nav_localization.launch.py
LAUNCH_FILE=cmexaiii_nav_mapping.launch.py

# Robot identity (see .env.example). Defaults target the production mecanum
# robot; deploy.sh --robot/--instance overwrites these.
ROBOT=cmexaiii
ROBOT_INSTANCE=cmexaiii-001

# DDS domain (see .env.example). Give a second robot on the same subnet its own.
ROS_DOMAIN_ID=12

# Input group GID for joystick access (auto-detected)
INPUT_GID=${INPUT_GID}
EOF

echo ".env created (ROBOT=cmexaiii, INPUT_GID=${INPUT_GID})"
