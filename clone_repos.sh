#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
vcs import "$SCRIPT_DIR/../" < "$SCRIPT_DIR/cmexa_robot.repos"
