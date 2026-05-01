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

Images are built once on merge to `jazzy` and **promoted** (retagged, not rebuilt) when you push a `v*` tag. Releases are byte-identical to what was tested on the merge commit, and tag-to-published is seconds, not minutes.

### Branch model

| Branch | Purpose | Protection |
|---|---|---|
| `jazzy_dev` | Active development. Push freely. | None |
| `jazzy` | Stable. Direct pushes blocked. Merges only via PR from `jazzy_dev`, all CI checks must pass. | Ruleset *Protect jazzy* |

PRs into `jazzy` from any branch other than `jazzy_dev` are rejected by the `verify-source` check.

### Versioning

| Event | Tags produced on `cmexa_hardware` and `cmexa_nav` |
|---|---|
| Merge PR into `jazzy` | `:jazzy`, `:jazzy-<full-sha>` (built fresh, multi-arch) |
| Push tag `v1.2.3` | `:1.2.3`, `:1.2`, `:1`, `:latest` (retagged from `:jazzy-<sha>`, no rebuild) |
| Push tag `v1.2.3-rc1` | `:1.2.3-rc1`, `:1.2`, `:1` (no `:latest` for pre-releases) |

The ROS base image is pinned by digest in both Dockerfiles, so upstream `ros:jazzy-ros-base-noble` updates can't shift a release. Bump the digest deliberately when you want to pull in upstream changes (see [Bumping the ROS base image](#bumping-the-ros-base-image) below).

### Releasing a new version — step by step

> **Prerequisite:** your changes are on `jazzy_dev` and pass tests locally.

**1. Open the release PR.** From the repo root on `jazzy_dev`:

```bash
gh pr create --base jazzy --head jazzy_dev \
  --title "Release v1.2.3" \
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

**5. Tag and push.** Use [SemVer](https://semver.org). The tag must point to the merge commit produced in step 3:

```bash
git tag -a v1.2.3 -m "Release v1.2.3"
git push origin v1.2.3
```

**6. Promotion runs automatically** (~10–30 s). Watch the `Promote` job in `Actions`. It retags the existing `:jazzy-<sha>` manifest as `:1.2.3`, `:1.2`, `:1`, and `:latest`.

**7. Deploy on the robot.** SSH to the Pi:

```bash
cd ~/cmexa_install
git pull
bash deploy.sh --version 1.2.3
```

This writes `IMAGE_TAG=1.2.3` to `.env`, pulls the pinned images, and restarts services.

**8. Create a GitHub release** (optional but recommended) — generates release notes and pins documentation to the tag:

```bash
gh release create v1.2.3 --generate-notes
```

### Pre-releases

For release candidates and beta builds, use a pre-release suffix. They get version tags but **not** `:latest`, so `deploy.sh` (which defaults to `:latest`) won't pick them up unless you pass `--version` explicitly.

```bash
git tag -a v1.2.3-rc1 -m "Release candidate"
git push origin v1.2.3-rc1
# On robot:
bash deploy.sh --version 1.2.3-rc1
```

### Hotfixing a released version

Tags are immutable. To publish a fix, open a new PR from `jazzy_dev` → `jazzy`, merge, and tag the new merge commit as `v1.2.4`.

### Bumping the ROS base image

The base image digest is pinned in `docker/Dockerfile.hardware` and `docker/Dockerfile.nav`. To pull in upstream updates:

```bash
docker buildx imagetools inspect ros:jazzy-ros-base-noble \
  --format '{{json .Manifest}}' | jq -r '.digest'
```

Replace the `sha256:…` in both Dockerfiles, open a PR, and follow the normal release flow.

### Manual rebuild

If a build needs to be re-run (e.g. transient registry failure), trigger `Docker Multi-Arch Build & Release` from the `Actions` tab via *Run workflow*.
