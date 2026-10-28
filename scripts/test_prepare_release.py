"""Tests of scripts/prepare-release.py: python3 -m unittest discover -s scripts"""

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("prepare_release", HERE / "prepare-release.py")
pr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pr)

REPO = "https://github.com/acme/action"

ACTION_YML = """name: test
inputs:
  sreg-version:
    description: >-
      Release of sreg.
    required: false
    default: "v0.1.0"
  other:
    default: ""
runs:
  using: composite
"""

CHANGELOG = """# Changelog

## [Unreleased]

### Fixed

- A fix.

## [1.0.0] - 2026-01-01

### Added

- First.

[Unreleased]: https://github.com/acme/action/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/acme/action/releases/tag/v1.0.0
"""


class Versions(unittest.TestCase):
    def test_latest_ignores_moving_tags(self):
        self.assertEqual(pr.latest_version(["v1", "v1.0.0", "v1.2.0", "v1.10.0", "v2"]), "1.10.0")
        self.assertIsNone(pr.latest_version(["v1"]))

    def test_prerelease_ranks_below_release(self):
        self.assertEqual(pr.latest_version(["v1.1.0-rc.1", "v1.1.0", "v1.1.0-rc.2"]), "1.1.0")

    def test_bumps(self):
        self.assertEqual(pr.next_version(None, "major"), "1.0.0")
        self.assertEqual(pr.next_version("1.2.3", "patch"), "1.2.4")
        self.assertEqual(pr.next_version("1.2.3", "minor"), "1.3.0")
        self.assertEqual(pr.next_version("1.2.3", "major"), "2.0.0")
        self.assertEqual(pr.next_version("1.3.0-rc.1", "minor"), "1.3.0")

    def test_explicit_version(self):
        self.assertEqual(pr.next_version("1.2.3", "patch", "v1.5.0"), "1.5.0")
        with self.assertRaises(pr.ReleaseError):
            pr.next_version("1.2.3", "patch", "1.2.3")
        with self.assertRaises(pr.ReleaseError):
            pr.next_version("1.2.3", "patch", "1.3")

    def test_newer_sreg_release(self):
        tags = ["v0.1.0", "v0.3.0-beta.1", "v0.2.0", "nightly"]
        self.assertEqual(pr.newer_sreg_release(tags, "v0.1.0"), "v0.2.0")
        self.assertIsNone(pr.newer_sreg_release(tags, "v0.2.0"))
        self.assertIsNone(pr.newer_sreg_release(tags, "v0.3.0"))
        self.assertIsNone(pr.newer_sreg_release([], "v0.1.0"))


class ActionYml(unittest.TestCase):
    def test_reads_and_sets_the_default(self):
        self.assertEqual(pr.sreg_version_default(ACTION_YML), "v0.1.0")
        updated = pr.set_sreg_version_default(ACTION_YML, "v0.2.0")
        self.assertEqual(pr.sreg_version_default(updated), "v0.2.0")
        self.assertIn('  other:\n    default: ""', updated)
        self.assertEqual(updated.count("v0.2.0"), 1)


class Changelog(unittest.TestCase):
    def test_roll_into_a_new_section(self):
        text = pr.add_changelog_entry(CHANGELOG, "Changed", "Default sreg release: v0.2.0.")
        out, notes = pr.roll_changelog(text, "1.0.1", "2026-02-02", REPO)
        self.assertIn("## [Unreleased]\n\n## [1.0.1] - 2026-02-02\n\n### Changed\n", out)
        self.assertEqual(
            notes, "### Changed\n\n- Default sreg release: v0.2.0.\n\n### Fixed\n\n- A fix."
        )
        self.assertIn(f"[Unreleased]: {REPO}/compare/v1.0.1...HEAD\n", out)
        self.assertIn(f"[1.0.1]: {REPO}/compare/v1.0.0...v1.0.1\n", out)

    def test_merge_into_a_section_written_ahead(self):
        text = "# Changelog\n\n## [Unreleased]\n\n### Added\n\n- Late.\n\n## [1.0.0]\n\n### Added\n\n- Early.\n\n[Unreleased]: https://github.com/acme/action/commits/main\n"
        out, notes = pr.roll_changelog(text, "1.0.0", "2026-03-03", REPO)
        self.assertEqual(notes, "### Added\n\n- Early.\n- Late.")
        self.assertIn("## [Unreleased]\n\n## [1.0.0] - 2026-03-03\n", out)
        self.assertIn(f"[Unreleased]: {REPO}/compare/v1.0.0...HEAD\n[1.0.0]: {REPO}/releases/tag/v1.0.0\n", out)

    def test_nothing_to_release(self):
        text = "# Changelog\n\n## [Unreleased]\n\n## [1.0.0] - 2026-01-01\n\n- x\n"
        with self.assertRaises(pr.ReleaseError):
            pr.roll_changelog(text, "1.0.1", "2026-02-02", REPO)


class CommandLine(unittest.TestCase):
    def test_apply(self):
        with tempfile.TemporaryDirectory() as root:
            Path(root, "action.yml").write_text(ACTION_YML)
            Path(root, "CHANGELOG.md").write_text(CHANGELOG)
            notes = Path(root, "notes.md")
            result = subprocess.run(
                [sys.executable, str(HERE / "prepare-release.py"), "--root", root,
                 "--latest-tag", "v1.0.0", "--sreg-version", "0.2.0", "--date", "2026-02-02",
                 "--notes-file", str(notes)],
                capture_output=True, text=True, check=True,
            )
            self.assertEqual(result.stdout, "1.0.1\n")
            self.assertIn('default: "v0.2.0"', Path(root, "action.yml").read_text())
            self.assertIn("## [1.0.1] - 2026-02-02", Path(root, "CHANGELOG.md").read_text())
            self.assertIn("- Default sreg release: v0.2.0.", notes.read_text())


if __name__ == "__main__":
    unittest.main()
