#!/usr/bin/env python3
"""Deploy a verified repository snapshot to the stopped local development app.

This command changes source files only. It does not rebuild/start an app, change
Supervisor options, touch persistent app data, or publish to GitHub.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from uuid import uuid4

import yaml

DEV_SLUG = "opencarwings-dev"
DEV_NAME = "OpenCarwings (Local Dev)"
ORIGINS = {
    "https://github.com/Chaoscontrol/opencarwings-app.git",
    "git@github.com:Chaoscontrol/opencarwings-app.git",
}
SENSITIVE = re.compile(r"(?i)(?:\.env(?:\..*)?|secrets?[^/]*|[^/]+\.(?:pem|key|p12|pfx))$")
SHA = re.compile(r"[0-9a-f]{40}\n")


class DeploymentError(RuntimeError):
    """A deployment safety check failed."""


def checked_path(path: Path, *, must_exist: bool = True) -> Path:
    """Reject symlinks in the path itself and every existing ancestor."""
    if ".." in path.parts:
        raise DeploymentError(f"Parent traversal is not allowed: {path}")
    path = path.absolute()
    for component in [*reversed(path.parents), path]:
        try:
            info = component.lstat()
        except FileNotFoundError:
            if component != path or must_exist:
                raise DeploymentError(f"Required directory is unavailable: {component}") from None
            continue
        if not stat.S_ISDIR(info.st_mode):
            raise DeploymentError(f"Refusing non-directory or symlink path: {component}")
    return path


def file_digest(path: Path) -> str:
    """Hash a regular file without following a last-moment symlink."""
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise DeploymentError(f"Refusing non-regular file: {path}")
        return hashlib.file_digest(stream, "sha256").hexdigest()


def manifest(root: Path) -> dict[str, tuple[str, int, str]]:
    """Describe the complete tree, including empty directories and file modes."""
    checked_path(root)
    entries = {".": ("directory", stat.S_IMODE(root.stat().st_mode), "")}
    def walk_error(error):
        raise error
    for parent, directories, files in os.walk(root, followlinks=False, onerror=walk_error):
        for name in sorted(directories + files):
            path = Path(parent) / name
            info = path.lstat()
            relative = path.relative_to(root).as_posix()
            mode = stat.S_IMODE(info.st_mode)
            if stat.S_ISDIR(info.st_mode):
                entries[relative] = ("directory", mode, "")
            elif stat.S_ISREG(info.st_mode):
                entries[relative] = ("file", mode, file_digest(path))
            else:
                raise DeploymentError(f"Refusing symlink or special file: {path}")
    return entries


def assert_manifest(root: Path, expected: dict) -> None:
    actual = manifest(root)
    if actual != expected:
        changed = sorted(key for key in actual.keys() | expected.keys()
                         if actual.get(key) != expected.get(key))
        raise DeploymentError(f"Tree differs from verified snapshot at {root}: {', '.join(changed[:12])}")


def dev_config(source_config: bytes) -> bytes:
    text = source_config.decode("utf-8")
    config = yaml.safe_load(text)
    if not isinstance(config, dict) or config.get("slug") != "opencarwings" or config.get("name") != "OpenCarwings":
        raise DeploymentError("Source config must describe the production OpenCarwings app.")
    for key, replacement in (("name", DEV_NAME), ("slug", DEV_SLUG)):
        pattern = rf"(?m)^{key}:[^\r\n]*"
        if len(re.findall(pattern, text)) != 1:
            raise DeploymentError(f"Source config must contain exactly one top-level {key} field.")
        text = re.sub(pattern, f"{key}: {replacement}", text)
    result = text.encode("utf-8")
    expected = dict(config, name=DEV_NAME, slug=DEV_SLUG)
    if yaml.safe_load(text) != expected:
        raise DeploymentError("Dev configuration differs beyond the exact name/slug transform.")
    return result


def validate_destination(destination: Path, source: Path) -> Path:
    destination = checked_path(destination, must_exist=False)
    if destination.name != DEV_SLUG:
        raise DeploymentError(f"Destination leaf must be exactly {DEV_SLUG}.")
    if destination == source or source in destination.parents or destination in source.parents:
        raise DeploymentError("Source and destination trees must not overlap.")
    if destination.exists():
        manifest(destination)  # Reject links and unsafe types anywhere in old source.
        config = yaml.safe_load((destination / "config.yaml").read_text(encoding="utf-8"))
        if not isinstance(config, dict) or config.get("slug") != DEV_SLUG or config.get("name") != DEV_NAME:
            raise DeploymentError("Existing destination is not the expected local dev app.")
    return destination


def git(repo: Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", "-c", f"safe.directory={repo}", "-C", str(repo), *arguments],
        check=False, text=True, capture_output=True,
        env={**os.environ, "GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0"},
        timeout=120,
    )
    if result.returncode:
        # Do not print transport diagnostics: authenticated remote URLs can appear.
        raise DeploymentError(f"git {arguments[0]} failed with exit code {result.returncode}.")
    return result.stdout.rstrip("\n")


def verify_git(repo: Path, allow_dirty: bool) -> tuple[str, str]:
    origin = git(repo, "remote", "get-url", "origin")
    if origin not in ORIGINS:
        raise DeploymentError("Unexpected origin; expected Chaoscontrol/opencarwings-app.")
    branch = git(repo, "symbolic-ref", "--short", "HEAD")
    head = git(repo, "rev-parse", "HEAD")
    origin_main = git(repo, "rev-parse", "refs/remotes/origin/main")
    remote = git(repo, "ls-remote", "--exit-code", "origin", "refs/heads/main").split()
    if len(remote) != 2 or remote[1] != "refs/heads/main" or remote[0] != origin_main:
        raise DeploymentError("Local origin/main is stale or unavailable. Fetch origin before deploying.")
    git(repo, "merge-base", "--is-ancestor", origin_main, head)
    changes = git(repo, "status", "--porcelain=v1", "--untracked-files=all", "--", "opencarwings")
    if changes:
        print("Uncommitted app source changes:\n" + changes)
        if not allow_dirty:
            raise DeploymentError("Uncommitted app source requires --allow-dirty.")
    return branch, head


def perform_deployment(source: Path, destination: Path, original: dict,
                       expected: dict, config: bytes) -> Path | None:
    """Stage, verify and swap source; retain old source even on rollback."""
    destination = validate_destination(destination, source)
    parent = destination.parent
    token = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid4().hex[:8]
    backup = parent / f".{DEV_SLUG}.previous-{token}"
    failed = parent / f".{DEV_SLUG}.failed-{token}"
    lock = parent / f".{DEV_SLUG}.deploy.lock"
    stage = None
    old_manifest = None
    old_moved = False
    swapped = False
    try:
        lock.mkdir(mode=0o700)
    except FileExistsError:
        raise DeploymentError(f"Deployment lock exists: {lock}. Check for an active deployment before removing it.") from None
    try:
        (lock / "owner.json").write_text(json.dumps({"pid": os.getpid(), "started": token}) + "\n")
        assert_manifest(source, original)
        # Revalidate after acquiring the lock.
        validate_destination(destination, source)
        if destination.exists():
            old_manifest = manifest(destination)
        stage = Path(tempfile.mkdtemp(prefix=f".{DEV_SLUG}.deploying-", dir=parent))
        shutil.copytree(source, stage, dirs_exist_ok=True, symlinks=False)
        (stage / "config.yaml").write_bytes(config)
        assert_manifest(source, original)
        assert_manifest(stage, expected)
        if destination.exists():
            assert_manifest(destination, old_manifest)
            destination.rename(backup)
            old_moved = True
            assert_manifest(backup, old_manifest)
        stage.rename(destination)
        swapped = True
        stage = None
        assert_manifest(destination, expected)
        assert_manifest(source, original)
        return backup if old_moved else None
    except BaseException as error:
        if old_moved or swapped:
            try:
                if destination.exists():
                    destination.rename(failed)
                if old_moved:
                    # Restore from a copy so the dated backup remains intact.
                    rollback = Path(tempfile.mkdtemp(prefix=f".{DEV_SLUG}.rollback-", dir=parent))
                    shutil.copytree(backup, rollback, dirs_exist_ok=True, symlinks=False)
                    assert_manifest(rollback, old_manifest)
                    rollback.rename(destination)
                    assert_manifest(destination, old_manifest)
                print(f"Deployment failed; previous state restored. Retained backup: {backup if old_moved else 'none'}", file=sys.stderr)
            except BaseException as rollback_error:
                raise DeploymentError(f"Deployment and rollback failed. Backup: {backup}; destination: {destination}; failed output: {failed}") from rollback_error
        raise
    finally:
        if stage is not None and stage.exists():
            shutil.rmtree(stage)
        (lock / "owner.json").unlink(missing_ok=True)
        lock.rmdir()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, default=Path("/addons/opencarwings-dev"))
    parser.add_argument("--confirm-dev-stopped", action="store_true")
    parser.add_argument("--allow-dirty", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    if not args.confirm_dev_stopped:
        raise DeploymentError("Confirm local_opencarwings-dev is stopped, then pass --confirm-dev-stopped.")
    repo = checked_path(Path(__file__).absolute().parent.parent)
    source = checked_path(repo / "opencarwings")
    original = manifest(source)
    for relative, entry in original.items():
        if entry[0] == "file" and SENSITIVE.fullmatch(Path(relative).name):
            raise DeploymentError(f"Refusing sensitive-looking source file: {relative}")
    if not SHA.fullmatch((source / ".upstream_sync").read_bytes().decode("ascii")):
        raise DeploymentError(".upstream_sync must contain one lowercase 40-character SHA followed by a newline.")
    config = dev_config((source / "config.yaml").read_bytes())
    expected = dict(original)
    kind, mode, _ = expected["config.yaml"]
    expected["config.yaml"] = (kind, mode, hashlib.sha256(config).hexdigest())
    destination = validate_destination(args.destination, source)
    branch, head = verify_git(repo, args.allow_dirty)
    assert_manifest(source, original)
    if args.dry_run:
        print(f"Dry run passed: {branch} at {head}; {len(original)} tree entries; destination {destination}.")
        print("No source or destination files were written.")
        return 0
    backup = perform_deployment(source, destination, original, expected, config)
    print(f"Deployment verified at {destination}; source {branch} at {head}.")
    print(f"Previous source retained at {backup}" if backup else "First deployment; no previous source existed.")
    print("Refresh the local store and rebuild local_opencarwings-dev. Verify isolated Supervisor ports and options before starting it.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (DeploymentError, OSError, ValueError, yaml.YAMLError, subprocess.TimeoutExpired) as exc:
        print(f"Deployment refused: {exc}", file=sys.stderr)
        sys.exit(1)
