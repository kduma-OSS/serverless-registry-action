# Serverless Registry publish action

A composite GitHub Action that publishes one package version to a
[Serverless Registry](https://github.com/kduma-OSS/serverless-registry-worker) with
[`sreg`](https://github.com/kduma-OSS/serverless-registry-cli), the registry's CLI.

```yaml
- uses: kduma-OSS/serverless-registry-publish-action@v1
  with:
    ecosystem: composer
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_PUBLISH_TOKEN }}
```

What it does:

1. Installs `sreg`: picks the release build for the runner (Linux x86_64 (musl) and
   arm64, macOS x86_64 and arm64, Windows x86_64), downloads the archive and its
   `.sha256` file from the
   [CLI releases](https://github.com/kduma-OSS/serverless-registry-cli/releases), verifies
   the checksum, unpacks it into `$RUNNER_TEMP/sreg` and adds it to `PATH`.
2. Runs `sreg <ecosystem> publish --json …` with `REGISTRY_URL` and `REGISTRY_TOKEN` (or
   `--oidc`) and turns the result into step outputs.

It works on Linux, macOS and Windows runners (every step runs in `bash`). The packaging
tools themselves (`npm`, `cargo`, `dotnet`, `swift`, the Maven or Gradle build) are not
installed by the action: set them up in earlier steps, as for a local build. To run
`sreg` without the action, see the CLI's
[installation instructions](https://github.com/kduma-OSS/serverless-registry-cli#install).

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `ecosystem` | – (required) | `composer`, `npm`, `cargo`, `nuget`, `generic`, `swift` or `maven`. |
| `registry` | – (required) | Base URL of the registry (`REGISTRY_URL`), exactly the registry's `PUBLIC_URL`; may carry the token as `https://<login>:<password>@host`. |
| `token` | empty | Publish token (`REGISTRY_TOKEN`). Empty, and no credentials in `registry`: OIDC (`--oidc`, needs `id-token: write`). |
| `oidc-project` | empty | With OIDC: the project of the token (`--oidc-project`). By default the registry finds it from the repository. |
| `version` | empty | Version to publish (`--version`); a leading `v` is dropped, so `${{ github.ref_name }}` works. Required for `generic`. |
| `tag-prefix` | empty | Take the version from the tag on `HEAD` with this prefix (`--tag-prefix`), for monorepos. |
| `path` | empty | composer, swift: package directory (`--path`). |
| `workspace` | empty | npm: workspace to publish (`--workspace`). |
| `package` | empty | cargo: crate to publish (`--package`); generic: the package name. |
| `project` | empty | nuget: project file (`--project`). |
| `from-dir` | empty | maven: local repository the build deployed to (`--from-dir`). |
| `coords` | empty | maven: `<groupId>:<artifactId>` to publish (`--coords`). |
| `scope` | empty | swift: registry scope (`--scope`, required by `sreg swift publish`). |
| `generic-files` | empty | generic: files to publish, one per line; glob patterns are expanded. |
| `generic-labels` | empty | generic: `key=value` labels for every file, one per line or comma-separated. |
| `extra-flags` | empty | Additional `sreg … publish` flags before `--`, e.g. `--tag beta` or `--no-symbols` (shell-like quoting, no expansion). |
| `args` | empty | Arguments for the packaging tool, placed after `--`, e.g. `--locked` or `-c Release`. |
| `dry-run` | `false` | Stop after the registry accepted the upload declaration (`--dry-run`). |
| `skip-existing` | `true` | Succeed when the version is already published (`--skip-existing`), so re-running a workflow is safe. |
| `sreg-version` | the release named in `action.yml` | Release of `sreg` to install, e.g. `v0.1.0`. See [Pinning `sreg`](#pinning-sreg). |

An input that does not apply to the selected ecosystem fails the step instead of being
ignored. Without `version` and `tag-prefix`, `sreg` takes the version from the
`v<semver>` tag on `HEAD` (npm, cargo and nuget fall back to their manifest), so
checking out a tag is usually enough.

## Outputs

| Output | Description |
| --- | --- |
| `name` | Name of the package. |
| `version` | Published version. |
| `url` | URL of the published version; empty for a dry run or a skipped version. |
| `skipped` | `true` when the version was already published and `skip-existing` let the step pass. |

The step fails with `sreg`'s exit code: `1` for an error, `2` when the version exists
and `skip-existing` is `false`, `3` when the registry requires a newer `sreg` (raise
`sreg-version`, or update the action).

```yaml
- id: publish
  uses: kduma-OSS/serverless-registry-publish-action@v1
  with:
    ecosystem: cargo
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_PUBLISH_TOKEN }}
- if: steps.publish.outputs.skipped != 'true'
  run: echo "Published ${{ steps.publish.outputs.name }} ${{ steps.publish.outputs.version }}: ${{ steps.publish.outputs.url }}"
```

## Authentication

The action needs a `publish` credential of the registry project. There are three ways to
pass it; the first one that applies wins.

**Token.** With `token`, the action exports it as `REGISTRY_TOKEN`. Store the token of
the `publish` credential (`<project>:<secret>`) as a repository or environment secret:

```yaml
- uses: kduma-OSS/serverless-registry-publish-action@v1
  with:
    ecosystem: composer
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_PUBLISH_TOKEN }}
```

**Registry URL with credentials.** The token can instead be part of `registry`, as
`https://<login>:<password>@packages.example.com` (percent-encode a `@` or `:` in the
login or password); `token` may then be omitted and OIDC is not used. Store such a URL as
a secret so that GitHub masks it in the logs; `sreg` itself never prints the
credentials. If both are given, `token` must equal the URL's credentials.

```yaml
- uses: kduma-OSS/serverless-registry-publish-action@v1
  with:
    ecosystem: composer
    registry: ${{ secrets.REGISTRY_URL }}
```

**OIDC (no secret).** Without `token` and without credentials in `registry`, the action
authenticates with the job's GitHub Actions OIDC token (`sreg … publish --oidc`). No
secret is stored anywhere, but the job must be allowed to request the token
(`id-token: write`), and the registry needs a `publish` credential with a `gh` secret
that trusts the repository (and, ideally, only the release workflow or tags). See
[A publish credential for GitHub Actions](https://github.com/kduma-OSS/serverless-registry-worker/blob/main/docs/deployment.md#a-publish-credential-for-github-actions-oidc-no-secret)
in the Worker's deployment guide.

```yaml
jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: kduma-OSS/serverless-registry-publish-action@v1
        with:
          ecosystem: composer
          registry: https://packages.example.com
          # oidc-project: acme-sdk   # only when several credentials match the repository
```

With OIDC, `registry` must be exactly the registry's `PUBLIC_URL` (the token's audience).

## Examples

All examples run on a pushed release tag:

```yaml
on:
  push:
    tags: ["v*"]
```

### Composer

```yaml
- uses: actions/checkout@v4
- uses: kduma-OSS/serverless-registry-publish-action@v1
  with:
    ecosystem: composer
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_PUBLISH_TOKEN }}
```

### npm

```yaml
- uses: actions/checkout@v4
- uses: actions/setup-node@v4
  with:
    node-version: 22
- run: npm ci
- uses: kduma-OSS/serverless-registry-publish-action@v1
  with:
    ecosystem: npm
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_PUBLISH_TOKEN }}
    extra-flags: --tag next
    args: --ignore-scripts
```

### cargo

```yaml
- uses: actions/checkout@v4
- uses: dtolnay/rust-toolchain@stable
- uses: kduma-OSS/serverless-registry-publish-action@v1
  with:
    ecosystem: cargo
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_PUBLISH_TOKEN }}
    args: --locked
```

### NuGet

```yaml
- uses: actions/checkout@v4
- uses: actions/setup-dotnet@v4
  with:
    dotnet-version: 8.0.x
- uses: kduma-OSS/serverless-registry-publish-action@v1
  with:
    ecosystem: nuget
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_PUBLISH_TOKEN }}
    project: src/Acme.Sdk/Acme.Sdk.csproj
    args: -c Release
```

### Generic files

A CI matrix where every job adds its own build of the same version:

```yaml
jobs:
  build:
    strategy:
      matrix:
        include:
          - { os: ubuntu-latest, label: linux }
          - { os: macos-latest, label: macos }
          - { os: windows-latest, label: windows }
    runs-on: ${{ matrix.os }}
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - run: ./build.sh # writes dist/acme-tool-*
        shell: bash
      - uses: kduma-OSS/serverless-registry-publish-action@v1
        with:
          ecosystem: generic
          registry: https://packages.example.com
          package: tools/acme-tool
          version: ${{ github.ref_name }}
          generic-files: |
            dist/acme-tool-*
          generic-labels: os=${{ matrix.label }}
```

### Swift

macOS runners come with Swift:

```yaml
- uses: actions/checkout@v4
- uses: kduma-OSS/serverless-registry-publish-action@v1
  with:
    ecosystem: swift
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_PUBLISH_TOKEN }}
    scope: acme
```

### Maven and Gradle

Deploy into a local directory first, then publish from it:

```yaml
- uses: actions/checkout@v4
- uses: actions/setup-java@v4
  with:
    distribution: temurin
    java-version: 21
- run: mvn -B deploy -DaltDeploymentRepository=local::file:./out
- uses: kduma-OSS/serverless-registry-publish-action@v1
  with:
    ecosystem: maven
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_PUBLISH_TOKEN }}
    from-dir: out
    coords: com.acme:sdk
```

With Gradle, point a `maven-publish` repository at a `file://` directory, run
`./gradlew publish` and pass that directory as `from-dir`.

## Monorepos

Tag every package with its own prefix (`sdk/v1.2.0`, `client/v0.4.0`) and derive the
package from the pushed tag; `tag-prefix` makes `sreg` take the version from the tag with
that prefix:

```yaml
on:
  push:
    tags: ["*/v*"]

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - id: tag
        run: echo "package=${GITHUB_REF_NAME%/v*}" >> "$GITHUB_OUTPUT"
      - uses: kduma-OSS/serverless-registry-publish-action@v1
        with:
          ecosystem: composer
          registry: https://packages.example.com
          token: ${{ secrets.REGISTRY_PUBLISH_TOKEN }}
          path: packages/${{ steps.tag.outputs.package }}
          tag-prefix: ${{ steps.tag.outputs.package }}/v
```

The flag that selects the package depends on the ecosystem, always together with the same
`tag-prefix`:

| Ecosystem | Input | Example |
| --- | --- | --- |
| composer, swift | `path` | `path: packages/sdk` |
| npm | `workspace` | `workspace: "@acme/sdk"` |
| cargo | `package` | `package: acme-sdk` |
| nuget | `project` | `project: src/Acme.Sdk/Acme.Sdk.csproj` |
| maven | `coords` (with `from-dir`) | `coords: com.acme:sdk` |

## Pinning `sreg`

Each release of the action installs one `sreg` release by default: the `default:` of the
`sreg-version` input in [`action.yml`](action.yml), named as "Default sreg release" in the
[changelog](CHANGELOG.md). The action follows stable `sreg` releases on its own: a new
CLI release triggers a patch release of the action with the new default (within an hour
at the latest), so `@v1` picks it up without any change in your workflow.

Pass `sreg-version` to install another release, e.g. to stay on a tested one or to try a
prerelease:

```yaml
- uses: kduma-OSS/serverless-registry-publish-action@v1
  with:
    ecosystem: composer
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_PUBLISH_TOKEN }}
    sreg-version: v0.1.0
```

A pinned `sreg-version` is never updated for you: when the registry later requires a
newer client, the step fails with exit code `3` until you raise it.

## Versioning

The action is versioned independently of the `sreg` CLI ([semver](https://semver.org);
see the [changelog](CHANGELOG.md)):

- `@v1` is a moving tag that follows the latest `1.x` release. It moves only while
  the inputs and outputs stay compatible; an incompatible change starts `v2`.
- `@v1.2.3` (a release tag) or a commit SHA pins the action, and with it the default
  `sreg` release, for fully reproducible workflows.

Releases are made only by the **Release** workflow of this repository
(`.github/workflows/release.yml`); it also moves `v1` to every stable 1.x release.

### Following CLI releases

A stable `sreg` release becomes the action's default through a patch release of the
action, started in one of two ways (both go through the Release workflow with
`only-if-newer-sreg: true`, so the second one does nothing):

- **Push from the CLI.** The CLI's release workflow ends with a job that dispatches this
  repository's Release workflow with `sreg-version: v<version>`. It authenticates as a
  GitHub App, e.g. "Serverless Registry Release": no webhook, repository permissions
  **Actions: Read and write** and **Metadata: Read-only** only, installed on
  `kduma-OSS/serverless-registry-publish-action` only. Its App ID and private key (PEM)
  are the repository secrets `SERVERLESS_REGISTRY_RELEASE_APP_ID` and
  `SERVERLESS_REGISTRY_RELEASE_APP_PRIVATE_KEY` of `kduma-OSS/serverless-registry-cli`.
  The App can only start the workflow; this repository's own `GITHUB_TOKEN` makes the
  commit, the tags and the release.
- **Hourly sync.** The **Sync CLI release** workflow checks the CLI's newest stable
  release every hour with the default `GITHUB_TOKEN` and releases the action when it is
  newer than the default. It needs no token or secret and covers a missing or failed
  dispatch, so `@v1` follows CLI releases within an hour either way.

By hand, run the Release workflow with `sreg-version` (and `bump`). See
[`docs/releasing.md`](docs/releasing.md) for the whole process and the App setup, and the
CLI's [release process](https://github.com/kduma-OSS/serverless-registry-cli/blob/main/docs/releasing.md).

## Development

`install.sh` and `publish.sh` are plain bash; `test/smoke.sh` tests them against a fake
`sreg` release served from a local HTTP server, without network access or a registry:

```
test/smoke.sh
shellcheck install.sh publish.sh test/*.sh test/fake-sreg
python3 -m unittest discover -s scripts
```

See [`AGENTS.md`](AGENTS.md) for the contribution rules.

## License

MIT, see [`LICENSE`](LICENSE).
