#!/usr/bin/env python3
"""Standalone tests for render_config. Run: python3 scripts/test_render_config.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_config as rc  # noqa: E402

failures = []


def check(name, got, want):
    if got != want:
        failures.append(f"{name}: got {got!r}, want {want!r}")


# --- defaults (empty config) preserve cmexaiii ---
env = rc.resolve({})
check("default robot", env["ROBOT"], "cmexaiii")
check("default instance", env["ROBOT_INSTANCE"], "cmexaiii-001")
check("default domain", env["ROS_DOMAIN_ID"], "12")
check("default nav", env["LAUNCH_FILE"], "cmexaiii_nav_mapping.launch.py")
check("default hw", env["HARDWARE_LAUNCH_FILE"], "cmexaiii_hardware.launch.py")

# --- instance derives from robot when unset ---
env = rc.resolve({"identity": {"robot": "cmexamini"}})
check("derived instance", env["ROBOT_INSTANCE"], "cmexamini-001")
check("derived hw launch", env["HARDWARE_LAUNCH_FILE"], "cmexamini_hardware.launch.py")

# --- stale cross-robot nav_launch is auto-corrected ---
env = rc.resolve({"identity": {"robot": "cmexamini"},
                  "ros": {"nav_launch": "cmexaiii_nav_mapping.launch.py"}})
check("nav auto-correct", env["LAUNCH_FILE"], "cmexamini_nav_mapping.launch.py")

# --- a valid same-robot nav choice (localization) is preserved ---
env = rc.resolve({"identity": {"robot": "cmexamini"},
                  "ros": {"nav_launch": "cmexamini_nav_localization.launch.py"}})
check("nav preserve", env["LAUNCH_FILE"], "cmexamini_nav_localization.launch.py")

# --- webapp version falls back to robot version when empty/latest ---
env = rc.resolve({"images": {"robot_version": "jazzy-1.2.3", "webapp_version": "latest"}})
check("webapp fallback", env["WEBAPP_VERSION"], "jazzy-1.2.3")
env = rc.resolve({"images": {"robot_version": "jazzy-1.2.3", "webapp_version": "jazzy-0.9.0"}})
check("webapp explicit", env["WEBAPP_VERSION"], "jazzy-0.9.0")

# --- domain + input_gid pass through ---
env = rc.resolve({"ros": {"domain_id": 13}, "host": {"input_gid": 995}})
check("domain", env["ROS_DOMAIN_ID"], "13")
check("input_gid", env["INPUT_GID"], "995")

# --- .env migration maps flat keys to dotted yaml ---
cfg = {}
import tempfile  # noqa: E402
with tempfile.NamedTemporaryFile("w", suffix=".env", delete=False) as f:
    f.write("ROBOT=cmexamini\nROS_DOMAIN_ID=13\nINPUT_GID=995\nROBOT_VERSION=jazzy-0.4.0\n")
    envpath = f.name
cfg = rc.migrate_env(envpath, cfg)
os.unlink(envpath)
check("migrate robot", cfg["identity"]["robot"], "cmexamini")
check("migrate domain", cfg["ros"]["domain_id"], 13)
check("migrate gid", cfg["host"]["input_gid"], 995)
check("migrate version", cfg["images"]["robot_version"], "jazzy-0.4.0")

if failures:
    print("FAIL:")
    for line in failures:
        print("  -", line)
    sys.exit(1)
print("render_config: all checks passed")
