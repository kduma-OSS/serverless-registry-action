#!/usr/bin/env python3
"""Prepares a release of the action. Used by .github/workflows/release.yml and runnable locally.

    scripts/prepare-release.py [--bump patch|minor|major] [--version X.Y.Z]
                               [--sreg-version vX.Y.Z] [--date YYYY-MM-DD]
                               [--notes-file PATH] [--root DIR] [--latest-tag TAG] [--dry-run]
    scripts/prepare-release.py --newer-sreg-release < tags

It computes the next version from the latest `vX.Y.Z` tag (`--bump`, default `patch`; the
first release is 1.0.0) or takes `--version`, optionally sets the `default:` of the
`sreg-version` input in every action.yml (the root one and those of the subdirectory
actions, which must agree; adds "Default sreg release: v…" to the changelog),
rolls CHANGELOG.md (the [Unreleased] entries move under `## [<version>] - <date>`) and writes
the release notes. It prints the version on stdout; `--dry-run` changes no file.

`--newer-sreg-release` reads sreg release tags (one per line) on stdin and prints the highest
stable one (`vX.Y.Z`, no prerelease) when it is newer than the `sreg-version` default in
action.yml, and nothing otherwise (used by .github/workflows/sync-cli-release.yml).
Only the Python standard library is used.
"""

from __future__ import annotations

import argparse
import datetime
import os
import re
import subprocess
import sys
from pathlib import Path

SEMVER = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?$"
)
FIRST_VERSION = "1.0.0"
GROUP_ORDER = ["Added", "Changed", "Deprecated", "Removed", "Fixed", "Security"]
DEFAULT_REPO_URL = "https://github.com/kduma-OSS/serverless-registry-action"


class ReleaseError(Exception):
    pass


# --- Versions ------------------------------------------------------------------------------


def parse_version(text: str):
    match = SEMVER.match(text)
    if match is None:
        return None
    pre = match.group(4)
    return (
        int(match.group(1)),
        int(match.group(2)),
        int(match.group(3)),
        tuple(pre.split(".")) if pre else (),
    )


def _pre_key(pre: tuple):
    # A version without a prerelease ranks above its prereleases; numeric identifiers rank
    # below alphanumeric ones and compare as numbers.
    if not pre:
        return (1,)
    return (0, tuple((0, int(p), "") if p.isdigit() else (1, 0, p) for p in pre))


def version_key(text: str):
    v = parse_version(text)
    if v is None:
        raise ReleaseError(f"{text!r} is not a semver version")
    return (v[0], v[1], v[2], _pre_key(v[3]))


def latest_version(tags) -> str | None:
    """The highest `vX.Y.Z[-pre]` tag as a version; moving tags such as `v1` are ignored."""
    versions = [t[1:] for t in tags if t.startswith("v") and parse_version(t[1:]) is not None]
    return max(versions, key=version_key) if versions else None


def next_version(latest: str | None, bump: str, requested: str = "") -> str:
    if requested:
        requested = requested.strip()
        requested = requested[1:] if requested.startswith("v") else requested
        if parse_version(requested) is None:
            raise ReleaseError(f"the version {requested!r} is not semver (X.Y.Z or X.Y.Z-pre)")
        if latest is not None and version_key(requested) <= version_key(latest):
            raise ReleaseError(f"the version {requested} is not greater than the latest {latest}")
        return requested
    if latest is None:
        return FIRST_VERSION
    major, minor, patch, pre = parse_version(latest)
    if bump == "major":
        return f"{major}.0.0" if pre and minor == 0 and patch == 0 else f"{major + 1}.0.0"
    if bump == "minor":
        return f"{major}.{minor}.0" if pre and patch == 0 else f"{major}.{minor + 1}.0"
    if bump == "patch":
        return f"{major}.{minor}.{patch}" if pre else f"{major}.{minor}.{patch + 1}"
    raise ReleaseError(f"unknown bump {bump!r} (patch, minor or major)")


def normalize_sreg_version(text: str) -> str:
    text = text.strip()
    bare = text[1:] if text.startswith("v") else text
    if parse_version(bare) is None:
        raise ReleaseError(f"the sreg version {text!r} is not a release tag such as v0.1.0")
    return f"v{bare}"


def newer_sreg_release(tags, current: str) -> str | None:
    """The highest stable `vX.Y.Z` of `tags` when it is newer than `current`, else None."""
    stable = [
        t.strip()[1:]
        for t in tags
        if t.strip().startswith("v")
        and parse_version(t.strip()[1:]) is not None
        and not parse_version(t.strip()[1:])[3]
    ]
    if not stable:
        return None
    best = max(stable, key=version_key)
    current = current[1:] if current.startswith("v") else current
    if parse_version(current) is not None and version_key(best) <= version_key(current):
        return None
    return f"v{best}"


# --- action.yml ----------------------------------------------------------------------------


def action_files(root: Path):
    """The root action.yml and the action.yml of every subdirectory action."""
    return [root / "action.yml"] + sorted(root.glob("*/action.yml"))


def common_sreg_version_default(texts) -> str:
    """The `sreg-version` default shared by all action.yml files, given as {path: text}."""
    defaults = {path: sreg_version_default(text) for path, text in texts.items()}
    if len(set(defaults.values())) != 1:
        listed = ", ".join(f"{path}: {value}" for path, value in sorted(defaults.items()))
        raise ReleaseError(f"the sreg-version defaults of the action.yml files differ ({listed})")
    return next(iter(defaults.values()))



def sreg_version_default(action_yml: str) -> str:
    _, index = _sreg_default_line(action_yml.split("\n"))
    return action_yml.split("\n")[index].split(":", 1)[1].strip().strip("\"'")


def set_sreg_version_default(action_yml: str, version: str) -> str:
    lines = action_yml.split("\n")
    indent, index = _sreg_default_line(lines)
    lines[index] = f'{indent}default: "{version}"'
    return "\n".join(lines)


def _sreg_default_line(lines):
    start = next((i for i, line in enumerate(lines) if line == "  sreg-version:"), None)
    if start is None:
        raise ReleaseError("action.yml has no sreg-version input")
    for i in range(start + 1, len(lines)):
        line = lines[i]
        if line.strip() and not line.startswith("    "):
            break
        match = re.match(r"^(\s+)default:", line)
        if match and len(match.group(1)) == 4:
            return match.group(1), i
    raise ReleaseError("the sreg-version input in action.yml has no default")


# --- CHANGELOG.md --------------------------------------------------------------------------


def _find_section(lines, name: str) -> int:
    pattern = re.compile(rf"^## \[{re.escape(name)}\](\s|$)", re.IGNORECASE)
    return next((i for i, line in enumerate(lines) if pattern.match(line)), -1)


def _section_end(lines, start: int) -> int:
    for i in range(start + 1, len(lines)):
        if lines[i].startswith("## ") or re.match(r"^\[[^\]]+\]:\s", lines[i]):
            return i
    return len(lines)


def _trim(lines):
    lines = list(lines)
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    return lines


def _split_groups(lines):
    """`(preamble, [(name, lines)])` for the `### <name>` groups of a section body."""
    preamble, groups = [], []
    for line in lines:
        match = re.match(r"^### (.+?)\s*$", line)
        if match:
            groups.append((match.group(1), []))
        elif groups:
            groups[-1][1].append(line)
        else:
            preamble.append(line)
    return preamble, groups


def _join_groups(preamble, groups):
    out = _trim(preamble)
    for name, body in groups:
        body = _trim(body)
        if not body:
            continue
        if out:
            out.append("")
        out += [f"### {name}", "", *body]
    return out


def _merge(existing, entries):
    pre_a, groups_a = _split_groups(existing)
    pre_b, groups_b = _split_groups(entries)
    groups = [(name, list(body)) for name, body in groups_a]
    for name, body in groups_b:
        target = next((g for g in groups if g[0] == name), None)
        if target is not None:
            target[1][:] = _trim(target[1]) + _trim(body)
            continue
        rank = GROUP_ORDER.index(name) if name in GROUP_ORDER else len(GROUP_ORDER)
        before = next(
            (
                i
                for i, (other, _) in enumerate(groups)
                if (GROUP_ORDER.index(other) if other in GROUP_ORDER else len(GROUP_ORDER)) > rank
            ),
            len(groups),
        )
        groups.insert(before, (name, list(body)))
    return _join_groups(_trim(pre_a) + _trim(pre_b), groups)


def add_changelog_entry(text: str, group: str, entry: str) -> str:
    """Appends `- <entry>` to the `### <group>` of [Unreleased]."""
    lines = text.split("\n")
    start = _find_section(lines, "Unreleased")
    if start == -1:
        raise ReleaseError("CHANGELOG.md has no ## [Unreleased] section")
    end = _section_end(lines, start)
    merged = _merge(lines[start + 1 : end], [f"### {group}", "", f"- {entry}"])
    body = ["", *merged, ""] if merged else [""]
    return "\n".join(lines[: start + 1] + body + lines[end:])


def roll_changelog(text: str, version: str, date: str, repo_url: str):
    """Moves [Unreleased] under `## [<version>] - <date>` (merging into a section written
    ahead), keeps an empty [Unreleased] and updates the links. Returns (text, notes)."""
    lines = text.replace("\r\n", "\n").split("\n")
    unreleased = _find_section(lines, "Unreleased")
    if unreleased == -1:
        raise ReleaseError("CHANGELOG.md has no ## [Unreleased] section")
    unreleased_end = _section_end(lines, unreleased)
    entries = _trim(lines[unreleased + 1 : unreleased_end])
    existing = _find_section(lines, version)
    if existing != -1 and existing < unreleased:
        raise ReleaseError(f"the ## [{version}] section must come after ## [Unreleased]")
    if not entries and existing == -1:
        raise ReleaseError(
            f"nothing to release: [Unreleased] is empty and there is no ## [{version}] section"
        )

    heading = f"## [{version}] - {date}"
    if existing == -1:
        out = lines[: unreleased + 1] + ["", heading, "", *entries, ""] + lines[unreleased_end:]
    else:
        existing_end = _section_end(lines, existing)
        merged = _merge(lines[existing + 1 : existing_end], entries)
        out = (
            lines[: unreleased + 1]
            + [""]
            + lines[unreleased_end:existing]
            + [heading, ""]
            + ([*merged, ""] if merged else [])
            + lines[existing_end:]
        )
    out = _update_links(out, version, repo_url)
    start = _find_section(out, version)
    notes = "\n".join(_trim(out[start + 1 : _section_end(out, start)]))
    return "\n".join(out), notes


def _update_links(lines, version: str, repo_url: str):
    tag = f"v{version}"
    out = list(lines)
    index = next((i for i, l in enumerate(out) if re.match(r"^\[Unreleased\]:\s*\S", l, re.I)), -1)
    previous = None
    if index != -1:
        match = re.match(r"^\[Unreleased\]:\s*\S+/compare/(\S+)\.\.\.HEAD\s*$", out[index], re.I)
        previous = match.group(1) if match else None
        out[index] = f"[Unreleased]: {repo_url}/compare/{tag}...HEAD"
    else:
        while out and not out[-1].strip():
            out.pop()
        out += ["", f"[Unreleased]: {repo_url}/compare/{tag}...HEAD"]
        index = len(out) - 1
    link = re.compile(rf"^\[{re.escape(version)}\]:")
    if not any(link.match(l) for l in out):
        target = (
            f"{repo_url}/compare/{previous}...{tag}"
            if previous and previous != tag
            else f"{repo_url}/releases/tag/{tag}"
        )
        out.insert(index + 1, f"[{version}]: {target}")
    if out[-1] != "":
        out.append("")
    return out


# --- Command line --------------------------------------------------------------------------


def git_tags(root: Path):
    result = subprocess.run(
        ["git", "tag", "--list", "v*"], cwd=root, check=True, capture_output=True, text=True
    )
    return result.stdout.split()


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[1])
    parser.add_argument("--bump", choices=["patch", "minor", "major"], default="patch")
    parser.add_argument("--version", default="", help="explicit version, overrides --bump")
    parser.add_argument("--sreg-version", default="", help="new default sreg release")
    parser.add_argument("--date", default=datetime.datetime.now(datetime.timezone.utc).date().isoformat())
    parser.add_argument("--notes-file", default="")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parent.parent))
    parser.add_argument("--latest-tag", default=None, help="use this instead of the git tags")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--newer-sreg-release", action="store_true")
    args = parser.parse_args(argv)

    root = Path(args.root)
    repo_url = DEFAULT_REPO_URL
    if os.environ.get("GITHUB_SERVER_URL") and os.environ.get("GITHUB_REPOSITORY"):
        repo_url = f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}"

    if args.newer_sreg_release:
        try:
            texts = {str(p.relative_to(root)): p.read_text(encoding="utf-8") for p in action_files(root)}
            current = common_sreg_version_default(texts)
        except ReleaseError as error:
            print(f"error: {error}", file=sys.stderr)
            return 1
        newer = newer_sreg_release(sys.stdin.read().split(), current)
        print(f"default sreg release: {current}; newer stable release: {newer or 'none'}", file=sys.stderr)
        if newer:
            print(newer)
        return 0

    try:
        if not re.match(r"^\d{4}-\d{2}-\d{2}$", args.date):
            raise ReleaseError(f"the date {args.date!r} is not YYYY-MM-DD")
        tags = [args.latest_tag] if args.latest_tag else ([] if args.latest_tag == "" else git_tags(root))
        latest = latest_version(tags)
        version = next_version(latest, args.bump, args.version)

        action_paths = action_files(root)
        changelog_path = root / "CHANGELOG.md"
        action_ymls = {str(p.relative_to(root)): p.read_text(encoding="utf-8") for p in action_paths}
        changelog = changelog_path.read_text(encoding="utf-8")
        current = common_sreg_version_default(action_ymls)

        if args.sreg_version:
            sreg = normalize_sreg_version(args.sreg_version)
            if sreg != current:
                action_ymls = {path: set_sreg_version_default(text, sreg) for path, text in action_ymls.items()}
                changelog = add_changelog_entry(changelog, "Changed", f"Default sreg release: {sreg}.")
                print(f"sreg-version default: {current} -> {sreg}", file=sys.stderr)
            else:
                print(f"sreg-version default is already {sreg}", file=sys.stderr)

        changelog, notes = roll_changelog(changelog, version, args.date, repo_url)
        print(f"{latest or '(no release)'} -> {version}", file=sys.stderr)
        if args.dry_run:
            print(notes, file=sys.stderr)
        else:
            for path, text in action_ymls.items():
                (root / path).write_text(text, encoding="utf-8")
            changelog_path.write_text(changelog, encoding="utf-8")
            if args.notes_file:
                Path(args.notes_file).write_text(notes + "\n", encoding="utf-8")
    except ReleaseError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(version)
    return 0


if __name__ == "__main__":
    sys.exit(main())
