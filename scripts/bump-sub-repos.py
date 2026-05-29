#!/usr/bin/env python3
"""Auto-bump SHAs in docker/*.repos files when upstream jazzy HEADs move.

For each unique sub-repo across all docker/*.repos files:
  * Resolve upstream jazzy HEAD via the GitHub API.
  * If different from the pinned SHA, create a branch off jazzy_dev,
    edit every .repos file that references the repo, commit one
    fix(repos):-style change, push, and open a PR.

Idempotent: a second run with no upstream drift is a no-op; a re-run while a
bump PR for the same SHA is already open is also a no-op.

Run from the repository root with gh authenticated for the cme-research org.
"""
from __future__ import annotations

import os
import pathlib
import re
import subprocess
import sys
import textwrap
from collections import defaultdict
from typing import Any

import yaml

REPO_ROOT = pathlib.Path(os.environ.get("GITHUB_WORKSPACE", ".")).resolve()
DOCKER_DIR = REPO_ROOT / "docker"
BASE_BRANCH = "jazzy_dev"
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
URL_RE = re.compile(r"^https://github\.com/([^/]+/[^/]+?)(?:\.git)?$")


def run(args: list[str], **kw: Any) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, check=True, text=True, capture_output=True, **kw)


def gh(args: list[str]) -> str:
    return run(["gh"] + args).stdout.strip()


def collect_pins() -> dict[str, dict[str, Any]]:
    """Aggregate {repo_name: {url, sha, files: [Path,...]}} across docker/*.repos."""
    pins: dict[str, dict[str, Any]] = defaultdict(
        lambda: {"url": None, "sha": None, "files": []}
    )
    for path in sorted(DOCKER_DIR.glob("*.repos")):
        with path.open() as fh:
            data = yaml.safe_load(fh) or {}
        for name, meta in (data.get("repositories") or {}).items():
            version = str(meta.get("version", ""))
            if not SHA_RE.match(version):
                continue  # branch tip or tag — not our concern
            entry = pins[name]
            if entry["url"] and entry["url"] != meta["url"]:
                sys.exit(f"URL mismatch for {name}: {entry['url']!r} vs {meta['url']!r}")
            if entry["sha"] and entry["sha"] != version:
                sys.exit(
                    f"SHA mismatch for {name}: pinned to {entry['sha']} in one file "
                    f"and {version} in another. Fix manually before re-running."
                )
            entry["url"] = meta["url"]
            entry["sha"] = version
            entry["files"].append(path)
    return pins


def upstream_sha(owner_repo: str) -> str:
    return gh(["api", f"repos/{owner_repo}/branches/jazzy", "--jq", ".commit.sha"])


def pr_already_open(branch: str) -> bool:
    count = gh(["pr", "list", "--state", "open", "--head", branch, "--json", "number", "--jq", "length"])
    return count == "1"


def open_pr(name: str, info: dict[str, Any], new_sha: str) -> None:
    short_new, short_old = new_sha[:7], info["sha"][:7]
    branch = f"bump/{name}-{short_new}"

    if pr_already_open(branch):
        print(f"{name}: PR for {short_new} already open, skipping")
        return

    print(f"{name}: drift {short_old} -> {short_new}; opening PR")

    run(["git", "fetch", "origin", BASE_BRANCH])
    run(["git", "checkout", "-B", branch, f"origin/{BASE_BRANCH}"])

    for path in info["files"]:
        text = path.read_text()
        new_text = text.replace(info["sha"], new_sha)
        if new_text == text:
            sys.exit(f"BUG: no replacement made in {path} for {name}")
        path.write_text(new_text)

    files_rel = [str(p.relative_to(REPO_ROOT)) for p in info["files"]]
    run(["git", "add", *files_rel])

    upstream_url = info["url"].removesuffix(".git")
    body = textwrap.dedent(
        f"""\
        Upstream jazzy HEAD of `{name}` moved from `{short_old}` to `{short_new}`.

        Bumped pin in: {", ".join(p.name for p in info["files"])}

        Compare upstream: {upstream_url}/compare/{info["sha"]}...{new_sha}

        Auto-opened by `.github/workflows/bump-sub-repos.yml`. Review the upstream
        diff, merge to roll forward, close to skip.
        """
    )

    run([
        "git", "commit",
        "--author", "cme-research <39484176+cme-research@users.noreply.github.com>",
        "-m", f"fix(repos): bump {name} to {short_new}",
        "-m", body,
    ])
    run(["git", "push", "--force-with-lease", "origin", branch])
    gh([
        "pr", "create",
        "--base", BASE_BRANCH,
        "--head", branch,
        "--title", f"fix(repos): bump {name} to {short_new}",
        "--body", body,
    ])


def main() -> None:
    pins = collect_pins()
    if not pins:
        print("No SHA-pinned entries found in docker/*.repos — nothing to do.")
        return

    drift_count = 0
    for name in sorted(pins):
        info = pins[name]
        m = URL_RE.match(info["url"])
        if not m:
            sys.exit(f"Cannot parse owner/repo from URL {info['url']!r}")
        owner_repo = m.group(1)
        new_sha = upstream_sha(owner_repo)
        if new_sha == info["sha"]:
            print(f"{name}: up to date ({info['sha'][:7]})")
            continue
        drift_count += 1
        open_pr(name, info, new_sha)

    if not drift_count:
        print("All sub-repos up to date.")


if __name__ == "__main__":
    main()
