# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The action is versioned independently of the `sreg` CLI; the `sreg` release it installs by
default is named in each release ("Default sreg release").

## [Unreleased]

## [1.0.6] - 2026-10-28

### Changed

- Documentation: the registry can give one credential both the `read` and the `publish` role,
  with a `gh` secret scoped to each. The README now says which role and scope each input needs
  and that `oidc-project` is only needed when several credentials hold the needed role for the
  repository. No change to inputs, outputs or scripts.
- Default sreg release: v0.2.0.

## [1.0.5] - 2026-10-28

### Changed

- Default sreg release: v0.1.5.

### Fixed

- The release workflow pushes the release commit and tags as the release GitHub App
  (`SERVERLESS_REGISTRY_RELEASE_APP_ID` and `SERVERLESS_REGISTRY_RELEASE_APP_PRIVATE_KEY`) when
  they are set. A ruleset that requires status checks on `main` rejects the push made with
  `GITHUB_TOKEN` (`GH013`, "Required status check is expected"); the App can be put on the
  ruleset's bypass list. Without them it still uses `GITHUB_TOKEN`.

## [1.0.4] - 2026-10-28

### Added

- `publish`: the inputs `archive` (`sreg <composer|npm|cargo|nuget> publish --archive`,
  publishes an archive built earlier byte for byte) and `source-registry-index`
  (`sreg cargo publish --source-registry-index`, with `archive`). They need an `sreg`
  release that has `--archive`; set `sreg-version` accordingly.

### Changed

- Default sreg release: v0.1.3.

## [1.0.3] - 2026-10-28

### Changed

- Default sreg release: v0.1.2.

## [1.0.2] - 2026-10-28

### Added

- `kduma-OSS/serverless-registry-action/setup@v1`: installs `sreg` only (outputs
  `version` and `path`).
- `kduma-OSS/serverless-registry-action/auth@v1`: writes the registry's credentials to the
  credentials file of Composer, npm, cargo, NuGet, Swift or Maven with
  `sreg auth <ecosystem> --write` (by default the package manager's user-level file, or
  `write`), with a token, credentials in the registry URL or OIDC; optionally the npm
  scope line (`npm-scope`), the cargo registry declaration (`cargo-config`, on by
  default) and the Swift scope (`swift-scope`). Output `file`.
- `kduma-OSS/serverless-registry-action/get@v1`: downloads the files of a generic package
  version with `sreg generic get` (exact version, constraint or `latest`, labels, `sole`,
  `out`, `prerelease`); outputs `version`, `files` and `path`.
- `kduma-OSS/serverless-registry-action/publish@v1`: the publish action, with the same
  inputs and outputs as before.

### Changed

- The repository is renamed from `kduma-OSS/serverless-registry-publish-action` to
  `kduma-OSS/serverless-registry-action`.
- `install.sh` reuses a release an earlier step of the job installed, without
  downloading it again, and writes the `version` and `path` outputs.

### Deprecated

- The root action (`kduma-OSS/serverless-registry-action@v1`, formerly
  `kduma-OSS/serverless-registry-publish-action@v1`) prints a warning; use `/publish`. It
  will be removed in v2.

## [1.0.1] - 2026-10-28

### Changed

- Default sreg release: v0.1.1.

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

[Unreleased]: https://github.com/kduma-OSS/serverless-registry-action/compare/v1.0.6...HEAD
[1.0.6]: https://github.com/kduma-OSS/serverless-registry-action/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/kduma-OSS/serverless-registry-action/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/kduma-OSS/serverless-registry-action/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/kduma-OSS/serverless-registry-action/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/kduma-OSS/serverless-registry-action/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/kduma-OSS/serverless-registry-action/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/kduma-OSS/serverless-registry-action/releases/tag/v1.0.0
