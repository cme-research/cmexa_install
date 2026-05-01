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

This writes `ROBOT_VERSION=jazzy-1.4.0` to `.env`, pulls the pinned images, and restarts services. Without `--version`, `deploy.sh` defaults to `:jazzy-latest` (the most recent stable release on jazzy) — never the rolling `:jazzy` build.

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
