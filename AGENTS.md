# AGENTS.md

Guidelines for contributors and coding agents working on this repository.

## What this is

`kduma-OSS/serverless-registry-publish-action`, a composite GitHub Action that installs
the [`sreg`](https://github.com/kduma-OSS/serverless-registry-cli) CLI from its GitHub
releases (checksum verified) and publishes one package version to a
[Serverless Registry](https://github.com/kduma-OSS/serverless-registry-worker). It was
split out of the `action/` directory of the CLI repository with its history.

```
action.yml          # the action: inputs, outputs, two bash steps; must stay at the root
install.sh          # installs sreg (reads only SREG_VERSION, i.e. the sreg-version input)
publish.sh          # maps the INPUT_* variables to `sreg <ecosystem> publish --json`
test/               # smoke test, fake sreg and fake release builder
scripts/            # prepare-release.py (version, action.yml default, changelog) + tests
docs/releasing.md   # release process, v1 tag, following CLI releases
.github/workflows/  # ci.yml, release.yml, sync-cli-release.yml
```

The default `sreg` release is the `default:` of the `sreg-version` input in `action.yml`;
there is no other place that names it. Inputs and outputs are a public interface: an
incompatible change needs a new major version (`v2`).

## Language

Everything in this repository is in **English**: code, comments, documentation, commit
messages, issues.

## Commits

- [Conventional Commits](https://www.conventionalcommits.org/): `type(scope)?: description`,
  types `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `build`, `ci`,
  `perf`, `revert`. Small, focused commits.
- **No trailers of any kind**: no `Co-Authored-By`, no `Claude-Session`, no other
  generated lines.
- Enable the hook that enforces this once per clone:

  ```
  git config core.hooksPath .githooks
  ```

- Record user-visible changes in `CHANGELOG.md` under `[Unreleased]`
  ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)).

## Testing

```
test/smoke.sh                                    # install.sh + publish.sh, offline
shellcheck install.sh publish.sh test/*.sh test/fake-sreg
python3 -c 'import yaml; yaml.safe_load(open("action.yml"))'
python3 -m unittest discover -s scripts         # release script
```

`test/smoke.sh` builds a fake `sreg-cli-<target>.tar.xz` release with its `.sha256`
(`test/make-fake-release.sh`), serves it with `python3 -m http.server` and points
`install.sh` at it through `SREG_RELEASES_URL`; it then runs `publish.sh` with a fake
`sreg` (`test/fake-sreg`) on `PATH` and checks the arguments and outputs. CI also runs the
action itself (`uses: ./`) against the fake release. Keep the scripts working on Linux,
macOS and Windows (Git Bash) runners, and shellcheck-clean.

## Releasing

Only through the **Release** workflow (`workflow_dispatch` on `main`); never tag by hand.
It updates `action.yml` (with `sreg-version`) and `CHANGELOG.md`, commits
`chore(release): v<version>`, tags, creates the GitHub release and moves `v1` to it, so
`@v1` follows the latest 1.x release. New stable CLI releases are picked up
automatically (push from the CLI release through a GitHub App, hourly sync as fallback).
See [`docs/releasing.md`](docs/releasing.md).
