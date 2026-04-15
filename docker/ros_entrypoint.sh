#!/bin/bash

source "/robot/ros2_ws/install/setup.bash"

#/usr/bin/brickd &

export ROBOT=cmexaiii
export ROBOT_ENV=house
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export ROS_DOMAIN_ID=12
export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET
export CYCLONEDDS_URI=file:///cyclonedds.xml

exec "$@"
