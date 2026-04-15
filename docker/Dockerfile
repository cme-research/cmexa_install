FROM ros:jazzy-ros-base-noble

LABEL maintainer="Christian Ehrmann"
LABEL version="0.1"
LABEL description="Workspace for CMEXA Robot image for ROS2"

# USE BASH
SHELL ["/bin/bash", "-c"]

RUN apt-get update && apt-get install --no-install-recommends -y \
    build-essential \
    git \
    python3-colcon-common-extensions \
    python3-colcon-mixin \
    python3-rosdep \
    python3-vcstool \
    && rm -rf /var/lib/apt/lists/*

ENV DEBIAN_FRONTEND=noninteractive
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# install helpers and requirements
RUN apt-get update && apt-get -y install curl software-properties-common vim wget joystick
RUN add-apt-repository universe
#RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
#RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null

# upgrade and install build tools (catkin)
# run all commands in one call is important

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y ros-dev-tools python3-rosdep


# workaround for ros2 not running on raspi aarch64 --> use other dds layer
# make sure to add export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp to sourceing file (or bashrc)
RUN apt-get update \
   && apt-get install -y ros-jazzy-rmw-cyclonedds-cpp


# workaround for missing rosdep definition for mqtt_bridge (external package)
RUN apt-get update \
    && apt-get install -y python3-pip
ENV PIP_BREAK_SYSTEM_PACKAGES=1


# Create local catkin workspace
ENV CATKIN_WS=/robot/ros2_ws

#### Clone all ROS2 packages from GitHub (branch jazzy) ###
RUN mkdir -p /robot/ros2_ws/src \
    && cd /robot/ros2_ws/src \
    && git clone -b jazzy https://github.com/cme-research/cmeresearch_bringup.git \
    && git clone -b jazzy https://github.com/cme-research/cmeresearch_description.git \
    && git clone -b jazzy https://github.com/cme-research/cmeresearch_msgs.git \
    && git clone -b jazzy https://github.com/cme-research/cmeresearch_environments.git \
    && git clone -b jazzy https://github.com/cme-research/cmexa_base.git \
    && git clone -b jazzy https://github.com/cme-research/cmeresearch_stepper_driver.git \
    && git clone -b jazzy https://github.com/cme-research/mqtt_bridge.git \
    && git clone -b jazzy https://github.com/cme-research/joy2twist.git \
    && git clone -b jazzy https://github.com/cme-research/ldlidar_stl_ros2.git \
    && git clone -b jazzy https://github.com/cme-research/dual_laser_merger.git

# 3d party non ros specific dependencies
# - tinkerforge bindings
RUN wget https://download.tinkerforge.com/apt/$(. /etc/os-release; echo $ID)/tinkerforge.gpg -q -O - | sudo tee /etc/apt/trusted.gpg.d/tinkerforge.gpg > /dev/null \
    && echo "deb https://download.tinkerforge.com/apt/$(. /etc/os-release; echo $ID $VERSION_CODENAME) main" | sudo tee /etc/apt/sources.list.d/tinkerforge.list \
    && apt-get update \
    && apt-get install python3-tinkerforge -y

# install brickd (tinkerforge daemon)
RUN apt-get update \
    && apt-get install brickd -y

# add package specific ros dependencies to workspace
RUN source /opt/ros/jazzy/setup.bash \
    && cd /robot/ros2_ws/  \
#    && rosdep init \
    && apt-get update \
    && rosdep update \
    && rosdep fix-permissions \
    && rosdep install -y -r --from-paths src --ignore-src --rosdistro=jazzy -y


RUN apt-get update
RUN source /opt/ros/jazzy/setup.bash \
    && cd /robot/ros2_ws \
    && colcon build

# create folder for file sharing with host system for map data
RUN mkdir /robot/data \
    && cp -r /robot/ros2_ws/src/cmeresearch_environments/envs/laboriii/* /robot/data/

# just leave install space inside container
RUN cd /robot/ros2_ws/ \
    && rm -rf build \
    && rm -rf log \
    && rm -rf src

RUN rm -rf /var/lib/apt/lists/*

# Always source ros_entrypoint.sh when launching bash (e.g. when attaching to container)
RUN echo "source /ros_entrypoint.sh" >> /root/.bashrc

COPY ros_entrypoint.sh /
RUN chmod +x /ros_entrypoint.sh

# cyclonedds for multi machine communication
COPY cyclonedds.xml /
RUN chmod +x /cyclonedds.xml


ENV ROBOT=cmexaiii

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["ros2", "launch", "cmeresearch_bringup", "cmexaiii_omni_navi_mapping.launch.py"]
#CMD ["bash"]