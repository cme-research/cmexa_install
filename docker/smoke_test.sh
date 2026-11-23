#!/usr/bin/env bash
# Smoke test for a built robot image. Runs INSIDE the image (via its entrypoint,
# so the workspace is sourced exactly as in production):
#
#   docker run --rm -v "$PWD/docker/smoke_test.sh:/smoke_test.sh:ro" \
#     <image> bash /smoke_test.sh hardware|nav
#
# Checks that the launch files compose uses can be loaded and that everything
# they reference (executables, packages) is present in the image, plus a few
# image-specific runtime checks. Exits non-zero on the first failing section.
set -uo pipefail

TARGET="${1:?usage: smoke_test.sh hardware|nav}"
FAILED=0
pass() { echo "  ok   $*"; }
fail() { echo "  FAIL $*"; FAILED=1; }

case "$TARGET" in
  hardware)
    REQUIRED_LAUNCH=(cmexaiii_hardware.launch.py)
    OPTIONAL_LAUNCH=(cmexamini_hardware.launch.py)
    ;;
  nav)
    REQUIRED_LAUNCH=(cmexaiii_nav_mapping.launch.py cmexaiii_nav_localization.launch.py)
    OPTIONAL_LAUNCH=(cmexamini_nav_mapping.launch.py cmexamini_nav_localization.launch.py)
    ;;
  *) echo "unknown target $TARGET"; exit 2 ;;
esac

BRINGUP_SHARE="$(ros2 pkg prefix --share cmeresearch_bringup 2>/dev/null)" \
  || { echo "cmeresearch_bringup is not installed"; exit 1; }

# Print "pkg exe" for every literal package=/executable= pair and "pkg -" for every
# literal FindPackageShare()/get_package_share_directory() in a launch file.
launch_refs() {
  python3 - "$1" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
out = set()
for n in ast.walk(tree):
    if not isinstance(n, ast.Call):
        continue
    name = getattr(n.func, 'id', None) or getattr(n.func, 'attr', None)
    kw = {k.arg: k.value for k in n.keywords}
    pkg, exe = kw.get('package'), kw.get('executable')
    if isinstance(pkg, ast.Constant) and isinstance(exe, ast.Constant):
        out.add((pkg.value, exe.value))
    if name in ('FindPackageShare', 'get_package_share_directory') and n.args \
            and isinstance(n.args[0], ast.Constant):
        out.add((n.args[0].value, '-'))
for pkg, exe in sorted(out):
    print(pkg, exe)
PY
}

check_launch() {
  local file="$1" path="$BRINGUP_SHARE/launch/$1"
  echo "== launch file $file"
  ros2 launch cmeresearch_bringup "$file" --show-args > /tmp/show_args.log 2>&1 \
    && pass "loads (--show-args)" || { fail "does not load:"; sed 's/^/       /' /tmp/show_args.log | tail -15; }
  while read -r pkg exe; do
    if ! ros2 pkg prefix "$pkg" > /dev/null 2>&1; then
      fail "package $pkg not installed"
    elif [ "$exe" != "-" ]; then
      ros2 pkg executables "$pkg" | grep -qx "$pkg $exe" \
        && pass "$pkg/$exe" || fail "executable $pkg/$exe missing"
    fi
  done < <(launch_refs "$path")
}

for f in "${REQUIRED_LAUNCH[@]}"; do
  if [ -f "$BRINGUP_SHARE/launch/$f" ]; then check_launch "$f"
  else echo "== launch file $f"; fail "not installed"; fi
done
for f in "${OPTIONAL_LAUNCH[@]}"; do
  [ -f "$BRINGUP_SHARE/launch/$f" ] && check_launch "$f"
done

echo "== image-specific checks ($TARGET)"
if [ "$TARGET" = hardware ]; then
  grep -rqs "cmexa_base/CmexaBaseBotSystemHardware" \
    "$(ros2 pkg prefix --share cmexa_base)" \
    && pass "cmexa_base ros2_control plugin registered" \
    || fail "cmexa_base plugin description not installed"

  python3 -c "import inject, paho.mqtt.client, msgpack, mqtt_bridge.bridge" 2> /tmp/py.log \
    && pass "mqtt_bridge python dependencies import" \
    || { fail "mqtt_bridge imports:"; sed 's/^/       /' /tmp/py.log | tail -5; }

  urdf="$(ros2 pkg prefix --share cmeresearch_description)/urdf/${ROBOT:-cmexaiii}/robot.urdf.xacro"
  xacro "$urdf" use_mock_hardware:=false > /tmp/robot.urdf 2> /tmp/xacro.log \
    && grep -q "<ros2_control" /tmp/robot.urdf \
    && pass "robot description for ${ROBOT:-cmexaiii} expands" \
    || { fail "xacro ${urdf}:"; sed 's/^/       /' /tmp/xacro.log | tail -5; }

  timeout 15 ros2 run cmeresearch_stepper_driver stepper_driver_node \
      --ros-args -p hw_simulation:=true > /tmp/stepper.log 2>&1
  if grep -qi "waiting for commands" /tmp/stepper.log; then
    pass "stepper_driver_node starts (hw_simulation)"
  elif grep -q "Connection failed" /tmp/stepper.log; then
    # Drivers before cmeresearch_stepper_driver#10 still connect to brickd in
    # hw_simulation mode, so they cannot start without hardware.
    echo "  skip stepper_driver_node start: pinned driver predates offline hw_simulation"
  else
    fail "stepper_driver_node did not start:"; sed 's/^/       /' /tmp/stepper.log | tail -10
  fi
else
  env_dir="$(ros2 pkg prefix --share cmeresearch_environments)/envs/${ROBOT_ENV:-house}"
  [ -f "$env_dir/map.yaml" ] && [ -f "$env_dir/map.pgm" ] \
    && pass "map for ROBOT_ENV=${ROBOT_ENV:-house} installed" \
    || fail "map files missing in $env_dir"
fi

echo
if [ "$FAILED" -ne 0 ]; then echo "SMOKE TEST FAILED ($TARGET)"; exit 1; fi
echo "SMOKE TEST PASSED ($TARGET)"
