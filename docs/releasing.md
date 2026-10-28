# Releasing the action

The actions (`publish`, `setup`, `auth`, `get` and the deprecated root alias) are released
together and versioned independently of the `sreg` CLI. A release is an annotated tag
`vX.Y.Z` on `main` with a GitHub release, plus the moving major tag `v1` that users
reference as `kduma-OSS/serverless-registry-action/<action>@v1`. Releases are made only by
the **Release** workflow (`.github/workflows/release.yml`); do not tag by hand.

The `sreg` release the actions install by default is the `default:` of the `sreg-version`
input, identical in every `action.yml` (the root one and `publish/`, `setup/`, `auth/`,
`get/`; CI and `scripts/prepare-release.py` refuse files that disagree). Changing it is a release of the action like any other change (a
patch release when nothing else changed), so `@v1` users get the new `sreg` and pinned
users (`@v1.2.3`) keep theirs.

## The Release workflow

Start it from **Actions** → **Release** → **Run workflow** on `main`, or:

```
gh workflow run release.yml -f bump=patch
gh workflow run release.yml -f sreg-version=v0.2.0             # new default sreg release
gh workflow run release.yml -f version=2.0.0                    # explicit version
```

| Input | Default | Description |
| --- | --- | --- |
| `sreg-version` | empty | New default `sreg` release (`v0.2.0`; a missing `v` is added). Empty keeps the current default. |
| `bump` | `patch` | `patch`, `minor` or `major`, applied to the latest `vX.Y.Z` tag. |
| `version` | empty | Explicit version (`X.Y.Z` or `X.Y.Z-pre`), overrides `bump`; must be greater than the latest tag. |
| `only-if-newer-sreg` | `false` | End quietly, without a release, unless `sreg-version` is newer than the current default (used by the automatic paths below, so that a duplicate trigger does nothing). |

The same inputs are available through `workflow_call`, which `sync-cli-release.yml` uses,
so every release goes through one code path. The run:

1. Refuses to run from any branch other than `main`; runs wait for each other
   (concurrency group `release`).
2. Checks out `main` with its tags and computes the version with
   `scripts/prepare-release.py`: the next `bump` of the latest `vX.Y.Z` tag (the first
   release is `1.0.0`, whatever the bump), or `version`. The tag must not exist yet.
3. With `sreg-version`, rewrites the `default:` of the `sreg-version` input in
   every `action.yml` and adds "Default sreg release: v…" to `### Changed` in `[Unreleased]`.
4. Rolls `CHANGELOG.md`: the `[Unreleased]` entries move under
   `## [<version>] - <today>` (UTC); a section written ahead (like `[1.0.0]`) gets the
   entries merged into it and the date set. An empty `[Unreleased]` without such a
   section is an error (nothing to release). The links at the bottom are updated.
5. Parses every `action.yml` and runs `test/smoke.sh`.
6. Commits `chore(release): v<version>` as `github-actions[bot]`, creates the annotated
   tag `v<version>` with the changelog section as its message and pushes both to `main`
   atomically.
7. Creates the GitHub release `v<version>` with the changelog section as its notes (a
   prerelease for a version with a suffix).
8. Moves the major tag to the release, for stable versions only:

   ```
   git tag -f v1 v<version>^{commit}
   git push -f origin v1
   ```

   `v1` therefore always follows the latest `1.x` release. Release an incompatible
   change of the inputs or outputs as `2.0.0` (`bump: major`); that creates `v2` and
   leaves `v1` where it is. Update the README examples to `@v2` in the same change.

The workflow declares `permissions: contents: write` itself. It pushes the release commit and
the tags straight to `main`, so branch protection or rulesets on `main` must let that push
through. `GITHUB_TOKEN` cannot be put on a ruleset's bypass list, so a ruleset that requires
status checks (for example `Changelog entry`, which only exists on pull requests) rejects it
with `GH013: Required status check … is expected`. For that case the workflow pushes as the
release GitHub App (the one that starts this workflow from the CLI release, below) when the
repository has the variable or secret `SERVERLESS_REGISTRY_RELEASE_APP_ID` and the secret
`SERVERLESS_REGISTRY_RELEASE_APP_PRIVATE_KEY`. The App needs the **Contents: Read and write**
permission (in addition to **Actions: Read and write**), must be installed on this repository
and must be on the ruleset's **Bypass list** (Add bypass → Apps, **Exempt**); the rule for the
`v1` tag, if you have one, needs the same bypass. Without the two values the workflow uses
`GITHUB_TOKEN`, which is enough when `main` has no such rule. Pushes made as the App start the
other workflows (a CI run on the release commit); the run checks the action itself before it
pushes.

## Following CLI releases

When a new stable `sreg` release should become the default (a CLI release that is not a
prerelease), the action is released with `sreg-version` set to it. This happens on its
own, in two ways; both end in the Release workflow with `bump: patch` and
`only-if-newer-sreg: true`, so whichever comes second does nothing.

1. **Push from the CLI release (immediate).** The CLI's cargo-dist `Release` workflow
   has a post-announce job (`.github/workflows/release-action.yml` in
   `kduma-OSS/serverless-registry-cli`) that, for a stable release, runs

   ```
   gh workflow run release.yml -R kduma-OSS/serverless-registry-action \
     -f sreg-version=v<version> -f bump=patch -f only-if-newer-sreg=true
   ```

   with a token minted from a GitHub App. Setup (once):

   1. Create a GitHub App (**Settings** → **Developer settings** → **GitHub Apps** →
      **New GitHub App**, for the `kduma-OSS` organization), named e.g.
      "Serverless Registry Release". Homepage URL: the CLI repository. Untick
      **Webhook** → **Active** (no webhook). Repository permissions: **Actions: Read and
      write** and **Metadata: Read-only** (the default); nothing else. "Only on this
      account".
   2. Install it on `kduma-OSS` with **Only select repositories** →
      `kduma-OSS/serverless-registry-action`.
   3. Generate a private key (a `.pem` file) on the App's page.
   4. In `kduma-OSS/serverless-registry-cli` → **Settings** → **Secrets and variables** →
      **Actions**, add two repository **secrets**: `SERVERLESS_REGISTRY_RELEASE_APP_ID`
      with the App ID and `SERVERLESS_REGISTRY_RELEASE_APP_PRIVATE_KEY` with the contents
      of the `.pem` file.

   The App can only start workflows in this repository; the commit, the tags and the
   GitHub release are made by this repository's own `GITHUB_TOKEN` in the Release run.
   Without the two secrets (e.g. in a fork) the CLI's job prints a notice and succeeds
   without doing anything; a failed token or dispatch only prints a warning.

2. **Hourly sync (fallback, no token).** `.github/workflows/sync-cli-release.yml` runs at
   minute 17 of every hour (and by hand: **Actions** → **Sync CLI release**). It lists the
   CLI's releases with the default `GITHUB_TOKEN` (they are public), takes the newest
   stable `v*` tag (no drafts, no prereleases) and, when it is newer than the current
   default, calls the Release workflow (`uses: ./.github/workflows/release.yml`) with that
   `sreg-version`. Otherwise it ends quietly. This covers a CLI release whose dispatch is
   not configured or failed, so the action follows CLI releases within an hour either
   way. GitHub disables scheduled workflows in a repository without activity for 60 days;
   re-enable it in the Actions tab if that happens.

**By hand**: run the Release workflow with `sreg-version` (and `bump`, usually `patch`).
To release a prerelease of `sreg` as the default, which the automatic paths never do,
this is the only way.

## Order with the CLI and the Worker

The Worker raises its minimum client version only after a `sreg` release that satisfies
it exists and the action defaults to it: release the CLI, wait for (or start) the action
release that makes it the default, then release the Worker. See the CLI's
[release process](https://github.com/kduma-OSS/serverless-registry-cli/blob/main/docs/releasing.md).

## Testing a release candidate

Before releasing, a workflow elsewhere can use the action from a branch or commit
(`uses: kduma-OSS/serverless-registry-action/publish@<sha>`) with `dry-run: true`, or with
`sreg-version` set to a CLI prerelease.
