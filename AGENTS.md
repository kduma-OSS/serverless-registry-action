# AGENTS.md

Guidelines for contributors and coding agents working on this repository.

## What this is

`kduma-OSS/serverless-registry-action` (formerly `serverless-registry-publish-action`):
composite GitHub Actions that install the
[`sreg`](https://github.com/kduma-OSS/serverless-registry-cli) CLI from its GitHub releases
(checksum verified) and use it with a
[Serverless Registry](https://github.com/kduma-OSS/serverless-registry-worker): `publish`
(one package version), `setup` (only install), `auth` (credentials files for package
managers) and `get` (download generic files). The publish action was split out of the
`action/` directory of the CLI repository with its history.

```
publish/action.yml  # publish: install.sh + publish.sh
setup/action.yml    # setup: install.sh only
auth/action.yml     # auth: install.sh + auth.sh
get/action.yml      # get: install.sh + get.sh
action.yml          # deprecated alias of publish/ for v1 (same inputs and outputs, a warning)
install.sh          # installs sreg (reads only SREG_VERSION, i.e. the sreg-version input)
publish.sh          # maps the INPUT_* variables to `sreg <ecosystem> publish --json`
auth.sh             # maps the INPUT_* variables to `sreg auth <ecosystem> --write <file>`
get.sh              # maps the INPUT_* variables to `sreg generic get` (resolve, download)
lib.sh              # helpers sourced by the three scripts above (token / URL / OIDC choice)
test/               # smoke test, fake sreg and fake release builder
scripts/            # prepare-release.py (version, action.yml defaults, changelog) + tests
docs/releasing.md   # release process, v1 tag, following CLI releases
.github/workflows/  # ci.yml, release.yml, sync-cli-release.yml
```

The subdirectory actions call the root scripts as `$GITHUB_ACTION_PATH/../<script>`
(a composite action cannot `uses: ./…` a sibling: relative paths resolve against the
workspace). The root `action.yml` must keep exactly the inputs and outputs of
`publish/action.yml` (CI checks it) until it is removed in `v2`.

The default `sreg` release is the `default:` of the `sreg-version` input, identical in
every `action.yml` (CI and the release script check it); there is no other place that
names it. Inputs and outputs are a public interface: an incompatible change needs a new
major version (`v2`).

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
test/smoke.sh                                    # all scripts, offline
shellcheck install.sh publish.sh auth.sh get.sh lib.sh test/*.sh test/fake-sreg
python3 -c 'import glob, yaml; [yaml.safe_load(open(f)) for f in glob.glob("**/action.yml", recursive=True)]'
python3 -m unittest discover -s scripts         # release script
```

`test/smoke.sh` builds a fake `sreg-cli-<target>.tar.xz` release with its `.sha256`
(`test/make-fake-release.sh`), serves it with `python3 -m http.server` and points
`install.sh` at it through `SREG_RELEASES_URL`; it then runs `publish.sh`, `auth.sh` and
`get.sh` with a fake `sreg` (`test/fake-sreg`) on `PATH` and checks the arguments, files
and outputs. CI also runs every action itself (`uses: ./setup`, `./publish`, `./`,
`./auth`, `./get`) against the fake release. Keep the scripts working on Linux,
macOS and Windows (Git Bash) runners, and shellcheck-clean.

## Releasing

Only through the **Release** workflow (`workflow_dispatch` on `main`); never tag by hand.
It updates every `action.yml` (with `sreg-version`) and `CHANGELOG.md`, commits
`chore(release): v<version>`, tags, creates the GitHub release and moves `v1` to it, so
`@v1` follows the latest 1.x release. New stable CLI releases are picked up
automatically (push from the CLI release through a GitHub App, hourly sync as fallback).
See [`docs/releasing.md`](docs/releasing.md).
