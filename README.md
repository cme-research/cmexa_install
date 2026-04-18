# cmexa_install

Deploy and infrastructure repo for the CMEXAIII robot stack. Contains Docker Compose files, Dockerfiles, and the CI/CD pipeline for building and deploying multi-arch images.

---

## Repository Structure

```
cmexa_install/
├── docker/
│   ├── Dockerfile.hardware     # Hardware stack: ros2_control, stepper drivers, LiDAR, MQTT bridge
│   ├── Dockerfile.nav          # Nav stack: nav2, slam_toolbox
│   ├── cyclonedds.xml          # CycloneDDS config (required on Raspberry Pi aarch64)
│   ├── ros_entrypoint.sh       # ROS2 entrypoint
│   └── mosquitto/bridge.conf   # Mosquitto MQTT broker config
├── docker-compose.yml          # Dev compose (local images)
├── docker-compose.prod.yml     # Production compose (ghcr.io images)
├── deploy.sh                   # Deploy script (see below)
├── setup.sh                    # First-time host setup (generates .env)
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
- GitHub Personal Access Token (PAT) with `read:packages` scope for pulling from `ghcr.io`

Store the PAT on the Pi to avoid being prompted on every deploy:

```bash
export GHCR_TOKEN=your_pat_here
# Add to ~/.bashrc to persist across reboots
```

### First deploy on a fresh host

```bash
git clone git@github.com:cme-research/cmexa_install.git
cd cmexa_install
bash deploy.sh
```

`deploy.sh` runs `setup.sh` automatically if no `.env` exists yet.

### Deploy a specific release

```bash
bash deploy.sh --version 1.2.3
```

This pulls `ghcr.io/cme-research/cmexa_hardware:1.2.3` and `cmexa_nav:1.2.3`, writes the version into `.env`, and starts all services.

### Update to latest

```bash
bash deploy.sh
```

### Switch nav mode (without restarting hardware)

Edit `LAUNCH_FILE` in `.env`, then restart only the nav container:

```bash
# Mapping mode
LAUNCH_FILE=cmexaiii_nav_mapping.launch.py

# Localization mode (loads map from /robot/data/maps)
LAUNCH_FILE=cmexaiii_nav_localization.launch.py
```

```bash
docker compose -f docker-compose.prod.yml stop nav
docker compose -f docker-compose.prod.yml up -d nav
```

### Check running services

```bash
docker compose -f docker-compose.prod.yml ps
docker compose -f docker-compose.prod.yml logs -f hardware
```

---

## CI/CD Pipeline

Images are built automatically via GitHub Actions on every push to the `jazzy` branch and on `v*` tags.

### Versioning

| Event | Tags produced |
|---|---|
| Push to `jazzy` | `:jazzy` |
| Git tag `v1.2.3` | `:1.2.3`, `:1.2`, `:1`, `:latest` |

### Releasing a new version

```bash
git tag v1.2.3
git push origin v1.2.3
```

GitHub Actions builds both images for `linux/amd64` and `linux/arm64` and pushes them to `ghcr.io/cme-research/`.

### Branch conventions

| Branch | Purpose |
|---|---|
| `jazzy` | Stable — triggers CI builds |
| `jazzy_dev` | Active development |
