# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The action is versioned independently of the `sreg` CLI; the `sreg` release it installs by
default is named in each release ("Default sreg release").

## [Unreleased]

## [1.0.0] - 2026-10-28

### Added

- Composite action `kduma-OSS/serverless-registry-publish-action@v1` that publishes one
  package version to a [Serverless Registry](https://github.com/kduma-OSS/serverless-registry-worker)
  with [`sreg`](https://github.com/kduma-OSS/serverless-registry-cli). It moved here from
  the `action/` directory of the CLI repository, with its history.
- Installs the `sreg` release build for the runner (Linux x86_64 (musl) and arm64, macOS
  x86_64 and arm64, Windows x86_64) from the CLI's GitHub releases, verifies the archive
  against its published SHA-256 checksum and adds it to `PATH`.
- Default sreg release: v0.1.0. The `sreg-version` input pins another release; its
  `default:` in `action.yml` is the default (the `VERSION` file is gone).
- Publishes the `composer`, `npm`, `cargo`, `nuget`, `generic`, `swift` and `maven`
  ecosystems through `sreg <ecosystem> publish --json`, with inputs for the version
  (`version`, `tag-prefix`), the monorepo flags (`path`, `workspace`, `package`,
  `project`, `from-dir`, `coords`, `scope`), generic files and labels, `extra-flags`,
  `args`, `dry-run` and `skip-existing` (on by default). An input that does not apply to
  the ecosystem fails the step.
- Authentication with a `token` input, with credentials in the `registry` URL
  (`https://<login>:<password>@host`), or, without either, with the job's GitHub Actions
  OIDC token (`--oidc`, optional `oidc-project`).
- Outputs `name`, `version`, `url` and `skipped`; the step fails with `sreg`'s exit code
  and explains codes `2` (version exists) and `3` (registry requires a newer `sreg`).
- CI: shellcheck, a parse of `action.yml`, a smoke test of `install.sh` and `publish.sh`
  against a fake release on a local HTTP server, and a run of the action itself.
- **Release** workflow (`.github/workflows/release.yml`, `workflow_dispatch` and
  `workflow_call`): optionally sets the default `sreg-version`, computes the next version
  from the latest tag (`patch`, `minor`, `major` or an explicit version; the first release
  is `1.0.0`), rolls this changelog with the dependency-free
  `scripts/prepare-release.py`, commits `chore(release): v<version>`, pushes the annotated
  tag `v<version>`, creates the GitHub release and moves the major tag (`v1`).
- The action follows stable `sreg` releases: the CLI's release dispatches the Release
  workflow with the new `sreg-version` through a GitHub App (repository secrets
  `SERVERLESS_REGISTRY_RELEASE_APP_ID` and `SERVERLESS_REGISTRY_RELEASE_APP_PRIVATE_KEY`
  in the CLI repository), and the hourly **Sync CLI release**
  workflow (`.github/workflows/sync-cli-release.yml`) does the same with no token when the
  dispatch is not configured or fails.

[Unreleased]: https://github.com/kduma-OSS/serverless-registry-publish-action/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/kduma-OSS/serverless-registry-publish-action/releases/tag/v1.0.0
