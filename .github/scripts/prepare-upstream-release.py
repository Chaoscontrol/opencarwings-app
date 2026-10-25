#!/usr/bin/env python3
"""Prepare and verify pinned upstream releases without executing upstream code."""
from __future__ import annotations

import argparse
import ast
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile

UPSTREAM = "https://github.com/developerfromjokela/opencarwings"
VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9]+)?")
SHA = re.compile(r"[0-9a-f]{40}")
FILES = {"opencarwings/config.yaml", "opencarwings/CHANGELOG.md", "opencarwings/.upstream_sync"}


class ReleaseError(RuntimeError):
    pass


def require(value, pattern, description):
    if not pattern.fullmatch(value):
        raise ReleaseError(f"Invalid {description}")
    return value


def git(repo, *args, allow_failure=False):
    result = subprocess.run(["git", "-c", f"safe.directory={Path(repo).resolve()}", "-C", str(repo), *args],
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode and not allow_failure:
        raise ReleaseError(f"git {args[0]} failed; required history or release source is unavailable")
    return result.returncode if allow_failure else result.stdout


def read_version(text):
    matches = re.findall(r'^version: "([^"\n]+)"$', text, re.MULTILINE)
    if len(matches) != 1:
        raise ReleaseError("Expected exactly one quoted app version")
    return require(matches[0], VERSION, "app version")


def marker(text):
    if not re.fullmatch(r"[0-9a-f]{40}\n", text):
        raise ReleaseError("Upstream marker must be one lowercase SHA followed by a newline")
    return text[:-1]


def validate_tag(tag):
    if not tag.startswith("v"):
        raise ReleaseError("Invalid app release tag")
    require(tag[1:], VERSION, "app release tag")
    return tag


def next_version(version):
    major, minor, patch = version.split("-", 1)[0].split(".")
    return f"{major}.{minor}.{int(patch) + 1}"


def show(repo, tag, filename):
    return git(repo, "show", f"{tag}:{filename}")


def require_ancestor(repo, base, target):
    git(repo, "cat-file", "-e", f"{base}^{{commit}}")
    git(repo, "cat-file", "-e", f"{target}^{{commit}}")
    if git(repo, "merge-base", "--is-ancestor", base, target, allow_failure=True):
        raise ReleaseError("Upstream history is missing, diverged or would move backwards")


def release_changelog(old, version, previous, target, commits, upstream_version=None, date=None):
    """Replace an unpublished candidate once, preserving its curated summary."""
    date = date or datetime.now(timezone.utc).date().isoformat()
    first = re.match(r"\A## v([^\s]+)[^\n]*\n(.*?)(?=^## |\Z)", old, re.MULTILINE | re.DOTALL)
    summary, remainder = "", old
    if first and first[1] == version:
        summary = first[2].split("\n### Upstream commits\n", 1)[0]
        summary = re.sub(r"^(?:Upstream source:|Comparison:)[^\n]*\n?", "", summary, flags=re.MULTILINE).strip()
        remainder = old[first.end():]
    label = f"{upstream_version} / {target}" if upstream_version else target
    body = f"## v{version} - {date} [Upstream Update]\n\n"
    if summary:
        body += summary + "\n\n"
    body += (f"Upstream source: [`{label}`]({UPSTREAM}/commit/{target}).\n"
             f"Comparison: [{previous[:7]}...{target[:7]}]({UPSTREAM}/compare/{previous}...{target}).\n\n"
             f"### Upstream commits\n\n{commits.rstrip()}\n\n")
    return body + remainder.lstrip("\n")


def upstream_version(repo, target):
    result = subprocess.run(["git", "-C", str(repo), "show", f"{target}:tculink/__init__.py"],
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if result.returncode:
        return None
    try:
        for node in ast.parse(result.stdout).body:
            if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "VERSION" for t in node.targets):
                value = ast.literal_eval(node.value)
                if isinstance(value, str) and re.fullmatch(r"[0-9A-Za-z.+_-]{1,40}", value):
                    return value
    except (SyntaxError, ValueError, TypeError):
        pass
    return None


def prepare(repo, upstream_repo, event, override=""):
    base = git(repo, "rev-parse", "HEAD").strip()
    last_tag = validate_tag(git(repo, "describe", "--tags", "--abbrev=0", "--match", "v[0-9]*").strip())
    last_version = read_version(show(repo, last_tag, "opencarwings/config.yaml"))
    if last_tag != "v" + last_version:
        raise ReleaseError("The last app tag and its config version differ")
    previous = marker(show(repo, last_tag, "opencarwings/.upstream_sync"))
    current_path = repo / "opencarwings/config.yaml"
    current_config = current_path.read_text()
    current_version = read_version(current_config)
    current = marker((repo / "opencarwings/.upstream_sync").read_text())
    latest = require(git(upstream_repo, "rev-parse", "refs/heads/main").strip(), SHA, "upstream main SHA")
    target = override or (current if event == "push" else latest)
    require(target, SHA, "target upstream SHA")
    require_ancestor(upstream_repo, previous, target)
    require_ancestor(upstream_repo, current, target)
    require_ancestor(upstream_repo, target, latest)
    version = next_version(last_version)
    if current_version not in {last_version, version}:
        raise ReleaseError("Current app version is neither the last release nor the next upstream candidate")
    output = {"mode": "normal", "base_sha": base, "target_upstream": target,
              "has_changes": "false", "new_version": last_version, "release_tag": last_tag,
              "release_sha": git(repo, "rev-parse", f"{last_tag}^{{commit}}").strip()}
    if previous == target:
        return output
    commits = git(upstream_repo, "log", "--pretty=format:- %s (%h)", f"{previous}..{target}")
    if not commits.strip():
        raise ReleaseError("Changed upstream marker produced no commit history")
    changelog = repo / "opencarwings/CHANGELOG.md"
    updated = release_changelog(changelog.read_text(), version, previous, target, commits,
                                upstream_version(upstream_repo, target))
    current_path.write_text(re.sub(r'^version: "[^"\n]+"$', f'version: "{version}"', current_config, flags=re.MULTILINE))
    (repo / "opencarwings/.upstream_sync").write_text(target + "\n")
    changelog.write_text(updated)
    return {**output, "has_changes": "true", "new_version": version, "release_tag": "v" + version, "release_sha": ""}


def verify_recovery(repo, tag, tested_commit, validated):
    validate_tag(tag)
    require(tested_commit, SHA, "tested app commit")
    if not validated or git(repo, "rev-parse", "HEAD").strip() != tested_commit:
        raise ReleaseError("Tag-only recovery requires the exact dev-validated main commit")
    if read_version((repo / "opencarwings/config.yaml").read_text()) != tag[1:]:
        raise ReleaseError("Recovery tag does not match the existing app version")
    if git(repo, "log", "-1", "--pretty=%s").strip() != f"Upstream sync - {tag}":
        raise ReleaseError("Recovery is limited to an existing upstream release commit")
    if git(repo, "show-ref", "--verify", "--quiet", f"refs/tags/{tag}", allow_failure=True) == 0:
        raise ReleaseError("Recovery refuses to overwrite an existing tag")
    pin = marker((repo / "opencarwings/.upstream_sync").read_text())
    return {"mode": "recover", "base_sha": tested_commit, "target_upstream": pin,
            "has_changes": "false", "new_version": tag[1:], "release_tag": tag, "release_sha": tested_commit}


def verify_artifact(repo, base, version, target):
    require(base, SHA, "base app SHA")
    require(version, VERSION, "release version")
    require(target, SHA, "target upstream SHA")
    if git(repo, "rev-parse", "HEAD").strip() != base:
        raise ReleaseError("Publish checkout differs from the tested app source")
    changes = set(git(repo, "diff", "--name-only").splitlines())
    untracked = git(repo, "ls-files", "--others", "--exclude-standard").splitlines()
    if not changes or not changes <= FILES or untracked:
        raise ReleaseError("Release artifact must change only the three allowed release files")
    for path in FILES:
        if not stat.S_ISREG((repo / path).lstat().st_mode):
            raise ReleaseError("Release files must be regular files")
    original = show(repo, base, "opencarwings/config.yaml")
    read_version(original)
    expected = re.sub(r'^version: "[^"\n]+"$', f'version: "{version}"', original, flags=re.MULTILINE)
    if (repo / "opencarwings/config.yaml").read_text() != expected:
        raise ReleaseError("Artifact changed app configuration beyond its version")
    if marker((repo / "opencarwings/.upstream_sync").read_text()) != target:
        raise ReleaseError("Artifact upstream pin differs from the tested pin")
    if not re.match(rf"\A## v{re.escape(version)} - [0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}} \[Upstream Update\]\n", (repo / "opencarwings/CHANGELOG.md").read_text()):
        raise ReleaseError("Artifact changelog lacks the expected official release heading")


def notes(repo, tag):
    validate_tag(tag)
    text = show(repo, tag, "opencarwings/CHANGELOG.md")
    match = re.search(rf"^## v{re.escape(tag[1:])}[^\n]*\n(.*?)(?=^## |\Z)", text, re.MULTILINE | re.DOTALL)
    if not match:
        raise ReleaseError("Tagged changelog has no matching release section")
    pin = marker(show(repo, tag, "opencarwings/.upstream_sync"))
    return f"Home Assistant app **{tag[1:]}**; upstream commit [`{pin}`]({UPSTREAM}/commit/{pin}).\n\n" + match[1].strip() + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "verify", "recover", "notes"))
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--upstream-dir", type=Path)
    parser.add_argument("--event", choices=("push", "schedule", "workflow_dispatch"), default="workflow_dispatch")
    parser.add_argument("--target", default="")
    parser.add_argument("--base", default="")
    parser.add_argument("--version", default="")
    parser.add_argument("--tag", default="")
    parser.add_argument("--tested-commit", default="")
    parser.add_argument("--dev-validated", choices=("true", "false"), default="false")
    parser.add_argument("--notes-file", type=Path)
    args = parser.parse_args()
    repo = args.repo.resolve()
    if args.command == "prepare":
        if args.target:
            require(args.target, SHA, "target upstream SHA")
        if args.upstream_dir:
            output = prepare(repo, args.upstream_dir.resolve(), args.event, args.target)
        else:
            with tempfile.TemporaryDirectory(prefix="ocw-upstream-release-") as temporary:
                upstream_repo = Path(temporary) / "upstream"
                result = subprocess.run(["git", "clone", "--filter=blob:none", "--branch", "main", UPSTREAM + ".git", str(upstream_repo)])
                if result.returncode:
                    raise ReleaseError("Unable to fetch upstream main history")
                output = prepare(repo, upstream_repo, args.event, args.target)
    elif args.command == "recover":
        output = verify_recovery(repo, args.tag, args.tested_commit, args.dev_validated == "true")
    elif args.command == "verify":
        verify_artifact(repo, args.base, args.version, args.target)
        output = {"verified": "true"}
    else:
        if args.notes_file is None:
            raise ReleaseError("--notes-file is required")
        args.notes_file.write_text(notes(repo, args.tag))
        output = {"notes_written": "true"}
    if os.environ.get("GITHUB_OUTPUT"):
        with Path(os.environ["GITHUB_OUTPUT"]).open("a") as stream:
            for key, value in output.items():
                stream.write(f"{key}={value}\n")
    print(json.dumps(output, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (ReleaseError, OSError) as error:
        print(f"release-error: {error}", file=sys.stderr)
        sys.exit(1)
