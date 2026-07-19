# cmexa_install

[![Release](https://img.shields.io/github/v/release/cme-research/cmexa_install?label=release)](https://github.com/cme-research/cmexa_install/releases)
[![Docker Build](https://github.com/cme-research/cmexa_install/actions/workflows/docker-build.yml/badge.svg?branch=jazzy)](https://github.com/cme-research/cmexa_install/actions/workflows/docker-build.yml)

Deploy and infrastructure repo for the CMEXAIII robot stack. Contains Docker Compose files, Dockerfiles, and the CI/CD pipeline for building and deploying multi-arch images.

---

## Repository Structure

```
cmexa_install/
├── docker/
│   ├── Dockerfile.hardware     # Hardware stack: ros2_control, stepper drivers, LiDAR, MQTT bridge
│   ├── Dockerfile.nav          # Nav stack: nav2, slam_toolbox
│   ├── cyclonedds.xml          # CycloneDDS config (required on Raspberry Pi aarch64)
│   ├── ros_entrypoint.sh       # ROS2 entrypoint (honours ROBOT/ROS_DOMAIN_ID)
│   └── mosquitto/
│       ├── bridge.conf.template # Bridge config template (rendered per instance)
│       └── bridge.conf          # Generated Mosquitto bridge config
├── docker-compose.yml          # Dev compose (local images)
├── docker-compose.prod.yml     # Production compose (ghcr.io images)
├── deploy.sh                   # Deploy script (see below)
├── setup.sh                    # First-time host setup (seeds robot.yaml)
├── robot.example.yaml          # Config schema / template (copy to robot.yaml)
├── scripts/render_config.py    # robot.yaml -> compose env-file + bridge.conf
├── clone_repos.sh              # Clone all workspace repos via vcs
└── cmexa_robot.repos           # vcs repos file
```

---

## Services

The stack runs as five Docker services with a defined startup order:

```
mosquitto → webapp + brickd → hardware → nav
```

| Service | Image | Description |
|---|---|---|
| `mosquitto` | `eclipse-mosquitto` | MQTT broker |
| `webapp` | `ghcr.io/cme-research/cmeresearch_amr_webcontrol` | Django web dashboard |
| `brickd` | `cmeresearch/brickd` | TinkerForge brick daemon (USB hardware access) |
| `hardware` | `ghcr.io/cme-research/cmexa_hardware` | ros2_control, stepper drivers, LiDAR, MQTT bridge |
| `nav` | `ghcr.io/cme-research/cmexa_nav` | Nav2 + SLAM Toolbox |

---

## Deployment

### Prerequisites

- Docker with Compose plugin
- `python3` + PyYAML (`apt install python3-yaml`) — `deploy.sh` compiles
  `robot.yaml` via `scripts/render_config.py`

All `ghcr.io/cme-research/...` images used here are **public** — no PAT or `docker login` required.

### Config model: `robot.yaml`

`robot.yaml` is the **single source of truth** for a robot host — identity, DDS
domain, image versions, nav mode, and runtime settings (see `robot.example.yaml`
for the full schema). `deploy.sh` compiles it into the derived artifacts the
stack consumes:

- `.compose.env` — a generated env-file for `docker compose` (never hand-edit)
- `docker/mosquitto/bridge.conf` — rendered per instance

`robot.yaml` replaces the old `.env` (a one-time migration runs automatically if
a legacy `.env` is present). All three files are per-host and gitignored.

#### Editing config from the web (config page)

The webapp serves a `/config/` page (behind an operator login) that edits
`robot.yaml` directly. Runtime settings (velocity limits, velocities, map) apply
live; boot-time settings (robot type, instance, DDS domain, nav mode) offer an
**Apply & restart** button that re-renders the config and recreates the ROS
containers.

Apply talks to Docker through a **least-privilege `socket-proxy`** (bound to
`127.0.0.1:2375`, not the LAN) — the webapp holds **no raw docker socket**. It
runs `docker compose` against this deploy dir, which is bind-mounted into the
webapp at its own host path (`DEPLOY_DIR`, set by `deploy.sh`) so compose paths
resolve. Apply actions are written to `config-audit.log`. If the deploy dir
isn't mounted (e.g. a manual `docker compose` without `deploy.sh`), the web
Apply button no-ops with a message and you redeploy from the CLI instead.

### First deploy on a fresh host

```bash
git clone git@github.com:cme-research/cmexa_install.git
cd cmexa_install
bash deploy.sh --version jazzy-latest
```

`deploy.sh` runs `setup.sh` automatically if no `robot.yaml` exists yet (seeding
it from `robot.example.yaml` with the host-detected joystick GID).

### Deploy a specific release

```bash
bash deploy.sh --version jazzy-0.1.1
```

This pulls `ghcr.io/cme-research/cmexa_hardware:jazzy-0.1.1`, `cmexa_nav:jazzy-0.1.1`, and `cmeresearch_amr_webcontrol:jazzy-0.1.1`, writes the version into `robot.yaml`, and starts all services. See `bash deploy.sh --help` for the full accepted version syntax.

### Deploying a second robot type (e.g. the diff-drive `cmexamini`)

The same `cmexa_hardware` / `cmexa_nav` / webapp images serve **every** robot — the
robot is selected at runtime, not by a separate image. Everything is driven by
`robot.yaml`; three fields do the heavy lifting:

| `robot.yaml` field | Selects |
|---|---|
| `identity.robot` | ROS launch + description (`<robot>_hardware.launch.py`, `urdf/<robot>/`, `config/<robot>/`) and the container names `<robot>-hardware` / `<robot>-nav` |
| `identity.instance` | MQTT topic prefix `cmeresearch/<instance>/…`, the rendered mosquitto `bridge.conf` routes, and the webapp config (`app_config.<instance>.json`) |
| `ros.domain_id` | DDS domain for this robot's ROS 2 graph (hardware + nav). Default `12`. Give a second robot on the **same subnet** its own domain so the graphs don't cross-discover |

Configure it either way:

```bash
# (a) via flags — deploy.sh writes them into robot.yaml for you:
bash deploy.sh --version jazzy-latest --robot cmexamini --instance cmexamini-001 --domain 13 --nav

# (b) or edit robot.yaml directly, then `bash deploy.sh`:
#   identity: { robot: cmexamini, instance: cmexamini-001 }
#   ros:      { domain_id: 13, nav_launch: cmexamini_nav_mapping.launch.py }
```

Leaving `robot.yaml` at its defaults reproduces the production mecanum
`cmexaiii` / `cmexaiii-001` deploy exactly.

> **Image rebuild required first.** The launch files, configs and per-instance
> webapp config for a new robot must be baked into the images: after the robot's
> `cmeresearch_bringup` / `cmeresearch_description` / `cmeresearch_amr_webcontrol`
> changes merge, bump their SHAs in `docker/hardware.repos` + `docker/nav.repos`
> and rebuild `cmexa_hardware` / `cmexa_nav` (and publish the webapp image).
> No Dockerfile changes are needed — the hardware image already installs
> lidar/mqtt_bridge/robot_state and the nav image already has nav2/slam.

### Update to latest

```bash
bash deploy.sh
```

### Switch nav mode

Set `ros.nav_launch` in `robot.yaml` to the mapping or localization launch, then
re-deploy:

```yaml
# robot.yaml
ros:
  nav_launch: cmexaiii_nav_mapping.launch.py        # mapping
  # nav_launch: cmexaiii_nav_localization.launch.py # localization (map from /robot/data/maps)
```

```bash
bash deploy.sh --nav
```

### Check running services

```bash
docker ps
docker logs -f <robot>-hardware      # e.g. cmexaiii-hardware
```

> **Note:** raw `docker compose` commands need the generated env to resolve
> `${ROBOT}`/`${ROS_DOMAIN_ID}` and, on a ROS host, the shell's own exported
> `ROS_DOMAIN_ID` would otherwise win. Prefer `docker ps`/`docker logs`, or
> prefix compose calls with `set -a; . .compose.env; set +a`. `deploy.sh` does
> this for you.

---

## Operating the robot

### Web dashboard

The webapp container serves a Django control panel on the robot host using `network_mode: host`. From any machine on the same LAN:

```
http://<robot-ip>/        # port 80 redirects to 8000
http://<robot-ip>:8000/   # Django app directly
```

Find `<robot-ip>` with `hostname -I` on the Pi (the robot is normally `192.168.1.202` on the lab subnet).

The dashboard provides:

- **Teleop** — touch joysticks to drive the base, plus live mini-tiles for stream status, motor voltage, system (Pi) stats, motor velocity and odometry.
- **Mission** — queue named poses / navigation goals.
- **Navigation** — live map view with pose markers.
- **Logs** — tail the Docker container logs from the browser.

Teleop and the webapp talk to the robot over **MQTT** (the `mosquitto` broker in the stack), not directly over ROS 2. The `hardware` container runs the MQTT↔ROS bridge that turns dashboard commands into `/cmexaiii/.../cmd_vel` messages and republishes odometry/voltage back to the dashboard.

### Switching nav mode

The `nav` container is only started when you pass `--nav` to `deploy.sh`. Choose mapping vs. localization with `ros.nav_launch` in `robot.yaml` (see [Switch nav mode](#switch-nav-mode) above). In localization mode the map is loaded from `/robot/data/maps` on the host (bind-mounted into the container at `/maps`).

---

## Connecting a Linux PC to the robot's ROS 2 graph

By default you only see the robot through the web dashboard (MQTT). To inspect the **ROS 2 topics directly** from your laptop (`ros2 topic list`, `ros2 topic echo`, RViz, `rqt`, etc.) the PC has to join the same DDS network as the containers.

The robot's containers run with this DDS configuration (`docker/ros_entrypoint.sh`):

| Setting | Value | Why |
|---|---|---|
| `RMW_IMPLEMENTATION` | `rmw_cyclonedds_cpp` | All nodes use CycloneDDS; a PC on the default Fast DDS will **not** discover them |
| `ROS_DOMAIN_ID` | `12` | Must match exactly or topics are invisible |
| `ROS_AUTOMATIC_DISCOVERY_RANGE` | `SUBNET` | Discovery stays within the local subnet |
| `CYCLONEDDS_URI` | `file:///cyclonedds.xml` | Multicast **disabled**, peers listed explicitly (see `docker/cyclonedds.xml`) |

Because multicast is off, your PC must be listed as a peer **and** must list the robot as a peer — discovery is unicast-only.

### 1. Prerequisites

- Same subnet as the robot (e.g. `192.168.1.0/24`), reachable via `ping 192.168.1.202`.
- ROS 2 **Jazzy** installed (`/opt/ros/jazzy`).
- The CycloneDDS RMW:

  ```bash
  sudo apt install ros-jazzy-rmw-cyclonedds-cpp
  ```

### 2. Create a CycloneDDS config on the PC

Copy `docker/cyclonedds.xml` from this repo to your home directory (the path the exports below point at) and adjust the peer list so it contains **the robot's IP and your PC's own IP**. Leave multicast disabled to match the robot:

```bash
cp docker/cyclonedds.xml ~/cyclonedds.xml
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CycloneDDS xmlns="https://cdds.io/config">
  <Domain>
    <General>
      <AllowMulticast>false</AllowMulticast>
    </General>
    <Discovery>
      <Peers>
        <Peer address="localhost"/>
        <Peer address="192.168.1.202"/>   <!-- the robot / docker host -->
        <Peer address="192.168.1.78"/>    <!-- THIS PC's LAN IP -->
      </Peers>
    </Discovery>
    <Tracing>
      <Verbosity>severe</Verbosity>
    </Tracing>
  </Domain>
</CycloneDDS>
```

> The robot's own `cyclonedds.xml` must in turn list your PC's IP under `<Peers>`. The shipped config already lists `192.168.1.78`; if your PC has a different IP, add it there too and redeploy (it is bind-mounted, so `bash deploy.sh` picks it up — mosquitto-style force-recreate not needed for the hardware/nav containers, just restart them).

### 3. Add the exports to your `~/.bashrc`

These five lines are all that is needed — they mirror the container settings exactly (only `CYCLONEDDS_URI` points at the PC-local copy):

```bash
source /opt/ros/jazzy/setup.bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export ROS_DOMAIN_ID=12
export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET
export CYCLONEDDS_URI=file:///home/<your-user>/cyclonedds.xml
```

Open a new shell (or `source ~/.bashrc`) so the exports take effect.

### 4. Verify

With the robot stack running:

```bash
ros2 topic list                     # should show /cmexaiii/..., /scan_combined, /tf, etc.
ros2 topic echo /base_mecanum_controller/tf_odometry --once
ros2 node list
```

If `ros2 topic list` is empty:

- **Domain mismatch** — confirm `echo $ROS_DOMAIN_ID` prints `12`.
- **Wrong RMW** — confirm `echo $RMW_IMPLEMENTATION` is `rmw_cyclonedds_cpp`; a stale Fast DDS shell sees nothing.
- **Peer/firewall** — your PC's IP must be in the robot's `cyclonedds.xml` peer list, and any host firewall must allow UDP in the 7400–7500 range on the subnet.
- **Different subnet / VPN** — `SUBNET` discovery won't cross routers; be on the same L2 network as the robot.

---

## CI/CD Pipeline

Images are built once on merge to `jazzy` and **promoted** (retagged, not rebuilt) when you push a `jazzy-v*` tag. Releases are byte-identical to what was tested on the merge commit, and tag-to-published is seconds, not minutes.

### Branch model

| Branch | Purpose | Protection |
|---|---|---|
| `jazzy_dev` | Active development on ROS Jazzy. Push freely. | None |
| `jazzy` | Stable releases on ROS Jazzy. Direct pushes blocked. Merges only via PR from `jazzy_dev`, all CI checks must pass. | Ruleset *Protect jazzy* |

PRs into `jazzy` from any branch other than `jazzy_dev` are rejected by the `verify-source` check.

When the project moves to a new ROS distro, mirror the pattern: a `<distro>` branch with the same protection ruleset, a `<distro>_dev` working branch, and tag releases as `<distro>-v*`. The workflow already derives the distro from the branch and tag names.

### Versioning

Every git tag and image tag is **prefixed with the ROS distro** so the underlying ROS version is unambiguous from the name alone.

| Event | Tags produced on `cmexa_hardware` and `cmexa_nav` |
|---|---|
| Merge PR into `jazzy` | `:jazzy`, `:jazzy-<full-sha>` (built fresh, multi-arch) |
| Push tag `jazzy-v1.4.0` | `:jazzy-1.4.0`, `:jazzy-1.4`, `:jazzy-1`, `:jazzy-latest` (retagged from `:jazzy-<sha>`, no rebuild) |
| Push tag `jazzy-v1.4.0-rc1` | `:jazzy-1.4.0-rc1`, `:jazzy-1.4`, `:jazzy-1` (no `:jazzy-latest` for pre-releases) |

The git tag format `<distro>-v<semver>` is enforced by the `Promote` job — tags that don't match (e.g. plain `v1.4.0`) are rejected with an explicit error.

The ROS base image itself is pinned by digest in both Dockerfiles, so upstream `ros:jazzy-ros-base-noble` updates can't shift a release. Bump the digest deliberately when you want to pull in upstream changes (see [Bumping the ROS base image](#bumping-the-ros-base-image) below).

### Releasing a new version — step by step

> **Prerequisite:** your changes are on `jazzy_dev` and pass tests locally.

**1. Open the release PR.** From the repo root on `jazzy_dev`:

```bash
gh pr create --base jazzy --head jazzy_dev \
  --title "Release jazzy-v1.4.0" \
  --body "Release notes here"
```

**2. Wait for CI to go green.** Four required checks must pass:

- `verify-source` — confirms the PR head is `jazzy_dev`
- `colcon build` — native amd64 colcon build of the full workspace
- `docker multi-arch (no push) (hardware)` — multi-arch hardware image builds
- `docker multi-arch (no push) (nav)` — multi-arch nav image builds

**3. Merge the PR.** This pushes `:jazzy` and `:jazzy-<sha>` images to GHCR. **Wait for the `Build` job to finish** (~10–20 min for multi-arch QEMU) — `Actions` tab on GitHub. Promotion in step 5 will fail if `:jazzy-<sha>` doesn't exist yet.

**4. Pull the merge commit locally.**

```bash
git checkout jazzy
git pull
```

**5. Tag and push.** Tag format is `<distro>-v<semver>`. The tag must point to the merge commit produced in step 3:

```bash
git tag -a jazzy-v1.4.0 -m "Release jazzy-v1.4.0"
git push origin jazzy-v1.4.0
```

**6. Promotion runs automatically** (~10–30 s). Watch the `Promote` job in `Actions`. It retags the existing `:jazzy-<sha>` manifest as `:jazzy-1.4.0`, `:jazzy-1.4`, `:jazzy-1`, and `:jazzy-latest`.

**7. Deploy on the robot.** SSH to the Pi:

```bash
cd ~/cmexa_install
git pull
bash deploy.sh --version jazzy-1.4.0
```

This writes `images.robot_version: jazzy-1.4.0` to `robot.yaml`, pulls the pinned images, and restarts services. Without `--version`, `deploy.sh` defaults to `:jazzy-latest` (the most recent stable release on jazzy) — never the rolling `:jazzy` build.

**8. Create a GitHub release** (optional but recommended) — generates release notes and pins documentation to the tag:

```bash
gh release create jazzy-v1.4.0 --generate-notes
```

### Pre-releases

For release candidates and beta builds, use a pre-release suffix. They get version tags but **not** `:jazzy-latest`, so `deploy.sh` (which defaults to `:jazzy-latest`) won't pick them up unless you pass `--version` explicitly.

```bash
git tag -a jazzy-v1.4.0-rc1 -m "Release candidate"
git push origin jazzy-v1.4.0-rc1
# On robot:
bash deploy.sh --version jazzy-1.4.0-rc1
```

### Hotfixing a released version

Tags are immutable. To publish a fix, open a new PR from `jazzy_dev` → `jazzy`, merge, and tag the new merge commit as `jazzy-v1.4.1`.

### Why distro-prefixed tags?

ROS releases are tied to a specific distro and the ABI is not portable across distros. Encoding the distro in every git tag and image tag means:

- A tag like `jazzy-v1.4.0` is self-describing — no need to look up which branch it lives on or read release notes to know which ROS distro it targets.
- `git tag --list 'jazzy-*'` lists all releases on a given distro.
- Two distros can be maintained in parallel: `jazzy-v1.4.1` (security fix on the old LTS) and `kilted-v2.0.0` (next-distro feature release) can ship the same week without tag conflicts.
- Image tags `cmexa_hardware:jazzy-1.4.0` make it impossible to accidentally deploy a `kilted` image where a `jazzy` one was expected.

### Bumping the ROS base image

The base image digest is pinned in `docker/Dockerfile.hardware` and `docker/Dockerfile.nav`. To pull in upstream updates:

```bash
docker buildx imagetools inspect ros:jazzy-ros-base-noble \
  --format '{{json .Manifest}}' | jq -r '.digest'
```

Replace the `sha256:…` in both Dockerfiles, open a PR, and follow the normal release flow.

### Manual rebuild

If a build needs to be re-run (e.g. transient registry failure), trigger `Docker Multi-Arch Build & Release` from the `Actions` tab via *Run workflow*.
