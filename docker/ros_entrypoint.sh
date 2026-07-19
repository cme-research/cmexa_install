#!/bin/bash

source "/robot/ros2_ws/install/setup.bash"

#/usr/bin/brickd &

# Robot identity + DDS domain are overridable from the environment (set by
# docker-compose per robot). Defaults preserve the production mecanum cmexaiii.
# Without the ${VAR:-default} form these exports would clobber the compose env
# and every robot would come up as cmexaiii on domain 12.
export ROBOT="${ROBOT:-cmexaiii}"
export ROBOT_ENV="${ROBOT_ENV:-house}"
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-12}"
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET
export CYCLONEDDS_URI=file:///cyclonedds.xml

exec "$@"
