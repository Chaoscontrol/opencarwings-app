#!/usr/bin/env python3
"""Offline release scenarios using disposable app and upstream Git histories."""
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from datetime import datetime, timedelta, timezone

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("release", Path(__file__).with_name("prepare-upstream-release.py"))
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], check=True, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.strip()


def init(repo):
    repo.mkdir()
    git(repo, "init", "-q", "-b", "main")
    git(repo, "config", "user.name", "Release test")
    git(repo, "config", "user.email", "release-test@example.invalid")


def commit(repo, message):
    git(repo, "add", ".")
    git(repo, "commit", "-q", "-m", message)
    return git(repo, "rev-parse", "HEAD")


class ReleaseScenarios(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ocw-release-tests-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.upstream = self.root / "upstream"
        init(self.upstream)
        (self.upstream / "tculink").mkdir()
        (self.upstream / "tculink/__init__.py").write_text('VERSION = "1.1"\n')
        self.previous = commit(self.upstream, "Baseline upstream")
        self.repo = self.root / "app"
        init(self.repo)
        (self.repo / "opencarwings").mkdir()
        self.config = self.repo / "opencarwings/config.yaml"
        self.pin = self.repo / "opencarwings/.upstream_sync"
        self.changelog = self.repo / "opencarwings/CHANGELOG.md"
        self.config.write_text('name: OpenCarwings\nversion: "0.0.24-3"\noptions:\n  enabled: true\n')
        self.pin.write_text(self.previous + "\n")
        self.changelog.write_text("## v0.0.24-3 - 2026-07-18 [Addon Patch]\n\n- Earlier app fix\n")
        self.base = commit(self.repo, "Baseline app")
        git(self.repo, "tag", "v0.0.24-3")

    def advance(self, count=3):
        for i in range(count):
            path = self.upstream / "changes"
            path.write_text((path.read_text() if path.exists() else "") + f"change {i}\n")
            target = commit(self.upstream, f"Feature {i}")
        return target

    def candidate(self, target):
        self.config.write_text(self.config.read_text().replace('"0.0.24-3"', '"0.0.25"'))
        self.pin.write_text(target + "\n")
        self.changelog.write_text("## v0.0.25 - 2026-10-25 [Upstream Update Candidate]\n\n- Curated feature summary\n\n" + self.changelog.read_text())
        return commit(self.repo, "Tested upstream candidate")

    def snapshot(self):
        return {p.name: p.read_bytes() for p in (self.repo / "opencarwings").iterdir()}

    def run_keepalive(self, *, old=False, race=False):
        if old:
            date = (datetime.now(timezone.utc) - timedelta(days=31)).isoformat()
            subprocess.run(["git", "-C", str(self.repo), "commit", "--amend", "--no-edit", "-q"],
                           check=True, env={**os.environ, "GIT_COMMITTER_DATE": date})
        base = git(self.repo, "rev-parse", "HEAD")
        remote = self.root / "origin.git"
        subprocess.run(["git", "clone", "--bare", "-q", str(self.repo), str(remote)], check=True)
        git(self.repo, "remote", "add", "origin", str(remote))
        git(self.repo, "fetch", "-q", "origin", "main")
        if race:
            peer = self.root / "peer"
            subprocess.run(["git", "clone", "-q", str(remote), str(peer)], check=True)
            git(peer, "config", "user.name", "Release test")
            git(peer, "config", "user.email", "release-test@example.invalid")
            (peer / "raced").write_text("new main commit\n")
            commit(peer, "Concurrent main update")
            git(peer, "push", "-q", "origin", "main")
        workflow = Path(__file__).parents[1] / "workflows/upstream-sync.yml"
        section = workflow.read_text().split("  keepalive:\n", 1)[1].split("\n  recover-publish:", 1)[0]
        body = section.split("        run: |\n", 1)[1]
        body = "\n".join(line[10:] if line.startswith("          ") else line for line in body.splitlines())
        result = subprocess.run(["bash", "-c", body], cwd=self.repo,
                                env={**os.environ, "BASE_SHA": base}, capture_output=True, text=True)
        return base, remote, result

    def test_keepalive_skips_recent_activity(self):
        base, remote, result = self.run_keepalive()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(git(self.repo, "rev-parse", "HEAD"), base)
        self.assertEqual(git(remote, "rev-parse", "main"), base)

    def test_keepalive_commits_no_app_changes_after_30_quiet_days(self):
        before = self.snapshot()
        base, remote, result = self.run_keepalive(old=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(git(self.repo, "rev-parse", "HEAD^"), base)
        self.assertEqual(git(self.repo, "diff", "HEAD^", "HEAD", "--name-only"), "")
        self.assertEqual(git(remote, "rev-parse", "main"), git(self.repo, "rev-parse", "HEAD"))
        self.assertEqual(self.snapshot(), before)

    def test_keepalive_refuses_a_concurrent_main_change(self):
        base, remote, result = self.run_keepalive(old=True, race=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(git(self.repo, "rev-parse", "HEAD"), base)
        self.assertNotEqual(git(remote, "rev-parse", "main"), base)

    def test_no_change_is_no_bump_and_can_repair_tagged_notes(self):
        before = self.snapshot()
        result = release.prepare(self.repo, self.upstream, "schedule")
        self.assertEqual(result["has_changes"], "false")
        self.assertEqual(result["release_tag"], "v0.0.24-3")
        self.assertEqual(result["release_sha"], self.base)
        self.assertEqual(before, self.snapshot())
        self.assertIn("Earlier app fix", release.notes(self.repo, result["release_tag"]))

    def test_normal_catchup_updates_all_three_release_files(self):
        target = self.advance()
        result = release.prepare(self.repo, self.upstream, "schedule")
        self.assertEqual(result["new_version"], "0.0.25")
        self.assertEqual(self.pin.read_text(), target + "\n")
        self.assertIn("Feature 0", self.changelog.read_text())
        self.assertIn(f"{self.previous}...{target}", self.changelog.read_text())
        self.assertIn(f"1.1 / {target}", self.changelog.read_text())
        release.verify_artifact(self.repo, self.base, "0.0.25", target)

    def test_first_tested_candidate_stays_25_and_only_changelog_may_change(self):
        target = self.advance()
        tested = self.candidate(target)
        newer = self.advance(1)
        result = release.prepare(self.repo, self.upstream, "push")
        self.assertEqual(result["new_version"], "0.0.25")
        self.assertEqual(result["target_upstream"], target)
        self.assertNotEqual(target, newer)
        self.assertEqual(git(self.repo, "diff", "--name-only"), "opencarwings/CHANGELOG.md")
        self.assertEqual(self.changelog.read_text().count("## v0.0.25 -"), 1)
        self.assertIn("Curated feature summary", self.changelog.read_text())
        release.verify_artifact(self.repo, tested, "0.0.25", target)

    def test_main_is_resolved_once_even_if_it_advances_during_preparation(self):
        target = self.advance()
        original = release.git
        resolutions = []
        def moving_main(repo, *args, **kwargs):
            value = original(repo, *args, **kwargs)
            if repo == self.upstream and args == ("rev-parse", "refs/heads/main"):
                resolutions.append(value.strip())
                self.advance(1)
            return value
        with patch.object(release, "git", side_effect=moving_main):
            result = release.prepare(self.repo, self.upstream, "schedule")
        self.assertEqual(resolutions, [target])
        self.assertEqual(result["target_upstream"], target)

    def test_manual_override_uses_exact_reachable_commit(self):
        target = self.advance(1)
        self.advance(1)
        result = release.prepare(self.repo, self.upstream, "workflow_dispatch", target)
        self.assertEqual(result["target_upstream"], target)

    def test_historical_patch_suffix_advances_to_plain_next_patch(self):
        self.config.write_text(self.config.read_text().replace('"0.0.24-3"', '"0.0.25-1"'))
        commit(self.repo, "Historical app patch")
        git(self.repo, "tag", "v0.0.25-1")
        self.advance()
        result = release.prepare(self.repo, self.upstream, "schedule")
        self.assertEqual(result["new_version"], "0.0.26")

    def test_unexpected_version_is_not_silently_downgraded(self):
        self.advance()
        self.config.write_text(self.config.read_text().replace('"0.0.24-3"', '"1.2.3"'))
        before = self.snapshot()
        with self.assertRaises(release.ReleaseError):
            release.prepare(self.repo, self.upstream, "schedule")
        self.assertEqual(before, self.snapshot())

    def test_invalid_sha_or_marker_is_rejected(self):
        with self.assertRaises(release.ReleaseError):
            release.prepare(self.repo, self.upstream, "schedule", "main")
        self.pin.write_text(self.previous)
        with self.assertRaises(release.ReleaseError):
            release.prepare(self.repo, self.upstream, "schedule")

    def test_missing_upstream_commit_is_rejected(self):
        before = self.snapshot()
        with self.assertRaises(release.ReleaseError):
            release.prepare(self.repo, self.upstream, "workflow_dispatch", "0" * 40)
        self.assertEqual(before, self.snapshot())

    def test_diverged_or_rewritten_main_is_rejected(self):
        git(self.upstream, "checkout", "-q", "--orphan", "replacement")
        git(self.upstream, "rm", "-q", "-rf", ".")
        (self.upstream / "replacement").write_text("unrelated history\n")
        commit(self.upstream, "Unrelated replacement")
        git(self.upstream, "branch", "-f", "main", "HEAD")
        with self.assertRaises(release.ReleaseError):
            release.prepare(self.repo, self.upstream, "schedule")

    def test_target_outside_main_is_rejected(self):
        git(self.upstream, "checkout", "-q", "-b", "side")
        side = self.advance(1)
        git(self.upstream, "checkout", "-q", "main")
        (self.upstream / "main-only").write_text("different branch content\n")
        commit(self.upstream, "Main branch only")
        with self.assertRaises(release.ReleaseError):
            release.prepare(self.repo, self.upstream, "workflow_dispatch", side)

    def test_published_release_retry_does_not_bump_and_notes_use_its_tag(self):
        target = self.advance()
        release.prepare(self.repo, self.upstream, "schedule")
        published = commit(self.repo, "Upstream sync - v0.0.25")
        git(self.repo, "tag", "v0.0.25")
        result = release.prepare(self.repo, self.upstream, "schedule")
        self.assertEqual(result["has_changes"], "false")
        self.assertEqual(result["release_sha"], published)
        self.assertEqual(result["release_tag"], "v0.0.25")
        self.changelog.write_text("## v99.0.0 - unrelated\n\nUnpublished notes\n")
        notes = release.notes(self.repo, "v0.0.25")
        self.assertIn(target, notes)
        self.assertNotIn("Unpublished notes", notes)

    def test_artifact_rejects_non_version_configuration_changes_or_extra_files(self):
        target = self.advance()
        release.prepare(self.repo, self.upstream, "schedule")
        self.config.write_text(self.config.read_text().replace("enabled: true", "enabled: false"))
        with self.assertRaises(release.ReleaseError):
            release.verify_artifact(self.repo, self.base, "0.0.25", target)
        self.config.write_text(self.config.read_text().replace("enabled: false", "enabled: true"))
        (self.repo / "extra").write_text("not a release artifact")
        with self.assertRaises(release.ReleaseError):
            release.verify_artifact(self.repo, self.base, "0.0.25", target)

    def test_artifact_rejects_wrong_pin_and_wrong_source(self):
        target = self.advance()
        release.prepare(self.repo, self.upstream, "schedule")
        self.pin.write_text(self.previous + "\n")
        with self.assertRaises(release.ReleaseError):
            release.verify_artifact(self.repo, self.base, "0.0.25", target)
        with self.assertRaises(release.ReleaseError):
            release.verify_artifact(self.repo, "0" * 40, "0.0.25", target)

    def test_candidate_changelog_transformation_is_idempotent(self):
        target = self.advance()
        self.candidate(target)
        first = release.release_changelog(self.changelog.read_text(), "0.0.25", self.previous, target, "- Feature (1234567)", "1.1", "2026-10-25")
        second = release.release_changelog(first, "0.0.25", self.previous, target, "- Feature (1234567)", "1.1", "2026-10-25")
        self.assertEqual(first, second)
        self.assertEqual(first.count("## v0.0.25 -"), 1)

    def test_recovery_is_exact_commit_tag_only_and_requires_attestation(self):
        target = self.advance()
        release.prepare(self.repo, self.upstream, "schedule")
        tested = commit(self.repo, "Upstream sync - v0.0.25")
        before = self.snapshot()
        with self.assertRaises(release.ReleaseError):
            release.verify_recovery(self.repo, "v0.0.25", tested, False)
        result = release.verify_recovery(self.repo, "v0.0.25", tested, True)
        self.assertEqual(result["mode"], "recover")
        self.assertEqual(before, self.snapshot())
        git(self.repo, "tag", "v0.0.25")
        with self.assertRaises(release.ReleaseError):
            release.verify_recovery(self.repo, "v0.0.25", tested, True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
