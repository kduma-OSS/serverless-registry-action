# Serverless Registry actions

Composite GitHub Actions for a
[Serverless Registry](https://github.com/kduma-OSS/serverless-registry-worker), built on
[`sreg`](https://github.com/kduma-OSS/serverless-registry-cli), the registry's CLI:

| Action | What it does |
| --- | --- |
| [`kduma-OSS/serverless-registry-action/publish@v1`](#publish) | Installs `sreg` and publishes one package version (`sreg <ecosystem> publish`). |
| [`kduma-OSS/serverless-registry-action/setup@v1`](#setup) | Installs `sreg` and adds it to `PATH`, for running it yourself. |
| [`kduma-OSS/serverless-registry-action/auth@v1`](#auth) | Installs `sreg` and writes the registry's credentials for Composer, npm, cargo, NuGet, Swift or Maven (`sreg auth <ecosystem> --write`), so that installing packages works. |
| [`kduma-OSS/serverless-registry-action/get@v1`](#get) | Installs `sreg` and downloads the files of a generic package version (`sreg generic get`). |

```yaml
- uses: kduma-OSS/serverless-registry-action/publish@v1
  with:
    ecosystem: composer
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_PUBLISH_TOKEN }}
```

Every action installs `sreg` the same way: it picks the release build for the runner
(Linux x86_64 (musl) and arm64, macOS x86_64 and arm64, Windows x86_64), downloads the
archive and its `.sha256` file from the
[CLI releases](https://github.com/kduma-OSS/serverless-registry-cli/releases), verifies the
checksum, unpacks it into `$RUNNER_TEMP/sreg` and adds it to `PATH`. When an earlier step
of the job installed the same release, it is reused without a download. All of them work
on Linux, macOS and Windows runners (every step runs in `bash`) and take the
`sreg-version` input (see [Pinning `sreg`](#pinning-sreg)).

> **Moved.** This repository was `kduma-OSS/serverless-registry-publish-action`, and the
> publish action was its root. `kduma-OSS/serverless-registry-publish-action@v1` and
> `kduma-OSS/serverless-registry-action@v1` keep working in v1 (GitHub redirects the old
> name; the root action takes the same inputs as `publish` and prints a deprecation
> warning) and will be removed in v2: switch to
> `kduma-OSS/serverless-registry-action/publish@v1`.

## Publish

`publish` runs `sreg <ecosystem> publish --json …` with `REGISTRY_URL` and
`REGISTRY_TOKEN` (or `--oidc`) and turns the result into step outputs. The packaging tools
themselves (`npm`, `cargo`, `dotnet`, `swift`, the Maven or Gradle build) are not
installed by the action: set them up in earlier steps, as for a local build. To run
`sreg` without the action, see the CLI's
[installation instructions](https://github.com/kduma-OSS/serverless-registry-cli#install).

### Inputs

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
| `archive` | empty | composer, npm, cargo, nuget: publish this archive (`.zip`, `.tgz`, `.crate`, `.nupkg`), built earlier, byte for byte (`--archive`). See [Publishing a prebuilt archive](#publishing-a-prebuilt-archive). |
| `source-registry-index` | empty | cargo, with `archive`: index URL of the retired registry the crate was built for (`--source-registry-index`). |
| `from-dir` | empty | maven: local repository the build deployed to (`--from-dir`). |
| `coords` | empty | maven: `<groupId>:<artifactId>` to publish (`--coords`). |
| `scope` | empty | swift: registry scope (`--scope`, required by `sreg swift publish`). |
| `generic-files` | empty | generic: files to publish, one per line; glob patterns are expanded. |
| `generic-labels` | empty | generic: `key=value` labels for every file, one per line or comma-separated. |
| `extra-flags` | empty | Additional `sreg … publish` flags before `--`, e.g. `--tag beta` or `--no-symbols` (shell-like quoting, no expansion). |
| `args` | empty | Arguments for the packaging tool, placed after `--`, e.g. `--locked` or `-c Release`. |
| `dry-run` | `false` | Stop after the registry accepted the upload declaration (`--dry-run`). |
| `skip-existing` | `true` | Succeed when the version is already published (`--skip-existing`), so re-running a workflow is safe. |
| `sreg-version` | the release named in `publish/action.yml` | Release of `sreg` to install, e.g. `v0.1.0`. See [Pinning `sreg`](#pinning-sreg). |

An input that does not apply to the selected ecosystem fails the step instead of being
ignored. Without `version` and `tag-prefix`, `sreg` takes the version from the
`v<semver>` tag on `HEAD` (npm, cargo and nuget fall back to their manifest), so
checking out a tag is usually enough.

### Outputs

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
  uses: kduma-OSS/serverless-registry-action/publish@v1
  with:
    ecosystem: cargo
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_PUBLISH_TOKEN }}
- if: steps.publish.outputs.skipped != 'true'
  run: echo "Published ${{ steps.publish.outputs.name }} ${{ steps.publish.outputs.version }}: ${{ steps.publish.outputs.url }}"
```

### Authentication

The action needs a credential with the `publish` role of the registry project. There are three ways to
pass it; the first one that applies wins.

**Token.** With `token`, the action exports it as `REGISTRY_TOKEN`. Store the token of
a token whose scope includes `publish` (`<project>:<secret>`) as a repository or environment secret:

```yaml
- uses: kduma-OSS/serverless-registry-action/publish@v1
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
- uses: kduma-OSS/serverless-registry-action/publish@v1
  with:
    ecosystem: composer
    registry: ${{ secrets.REGISTRY_URL }}
```

**OIDC (no secret).** Without `token` and without credentials in `registry`, the action
authenticates with the job's GitHub Actions OIDC token (`sreg … publish --oidc`). No
secret is stored anywhere, but the job must be allowed to request the token
(`id-token: write`), and the registry needs a credential with the `publish` role and a `gh`
secret scoped to `publish` that trusts the repository (and, ideally, only the release
workflow or tags). One credential may also hold the `read` role, with a separate `gh` secret
scoped to `read`: the registry picks the entry by the role the command needs, so the same
repository can install and publish without `oidc-project`. See
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
      - uses: kduma-OSS/serverless-registry-action/publish@v1
        with:
          ecosystem: composer
          registry: https://packages.example.com
          # oidc-project: acme-sdk   # only when several credentials hold the publish role for the repository
```

With OIDC, `registry` must be exactly the registry's `PUBLIC_URL` (the token's audience).

### Examples

All examples run on a pushed release tag:

```yaml
on:
  push:
    tags: ["v*"]
```

#### Composer

```yaml
- uses: actions/checkout@v4
- uses: kduma-OSS/serverless-registry-action/publish@v1
  with:
    ecosystem: composer
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_PUBLISH_TOKEN }}
```

#### npm

```yaml
- uses: actions/checkout@v4
- uses: actions/setup-node@v4
  with:
    node-version: 22
- run: npm ci
- uses: kduma-OSS/serverless-registry-action/publish@v1
  with:
    ecosystem: npm
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_PUBLISH_TOKEN }}
    extra-flags: --tag next
    args: --ignore-scripts
```

#### cargo

```yaml
- uses: actions/checkout@v4
- uses: dtolnay/rust-toolchain@stable
- uses: kduma-OSS/serverless-registry-action/publish@v1
  with:
    ecosystem: cargo
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_PUBLISH_TOKEN }}
    args: --locked
```

#### NuGet

```yaml
- uses: actions/checkout@v4
- uses: actions/setup-dotnet@v4
  with:
    dotnet-version: 8.0.x
- uses: kduma-OSS/serverless-registry-action/publish@v1
  with:
    ecosystem: nuget
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_PUBLISH_TOKEN }}
    project: src/Acme.Sdk/Acme.Sdk.csproj
    args: -c Release
```

#### Generic files

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
      - uses: kduma-OSS/serverless-registry-action/publish@v1
        with:
          ecosystem: generic
          registry: https://packages.example.com
          package: tools/acme-tool
          version: ${{ github.ref_name }}
          generic-files: |
            dist/acme-tool-*
          generic-labels: os=${{ matrix.label }}
```

#### Swift

macOS runners come with Swift:

```yaml
- uses: actions/checkout@v4
- uses: kduma-OSS/serverless-registry-action/publish@v1
  with:
    ecosystem: swift
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_PUBLISH_TOKEN }}
    scope: acme
```

#### Maven and Gradle

Deploy into a local directory first, then publish from it:

```yaml
- uses: actions/checkout@v4
- uses: actions/setup-java@v4
  with:
    distribution: temurin
    java-version: 21
- run: mvn -B deploy -DaltDeploymentRepository=local::file:./out
- uses: kduma-OSS/serverless-registry-action/publish@v1
  with:
    ecosystem: maven
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_PUBLISH_TOKEN }}
    from-dir: out
    coords: com.acme:sdk
```

With Gradle, point a `maven-publish` repository at a `file://` directory, run
`./gradlew publish` and pass that directory as `from-dir`.

### Monorepos

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
      - uses: kduma-OSS/serverless-registry-action/publish@v1
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

### Publishing a prebuilt archive

Build, test and protect the archive in one job, download that artifact in the publishing
job and pass it as `archive`: exactly those bytes are uploaded, the package, version and
dependencies are read from the manifest inside the archive, and neither a checkout nor
`npm`, `cargo`, `dotnet` or `git` is needed.

```yaml
publish:
  runs-on: ubuntu-latest
  permissions:
    id-token: write
  steps:
    - uses: actions/download-artifact@v4
      with:
        name: dist
        path: dist
    - uses: kduma-OSS/serverless-registry-action/publish@v1
      with:
        ecosystem: npm
        registry: https://packages.example.com
        archive: dist/package.tgz
```

`version` is then only a consistency check (for a Composer archive whose `composer.json`
has no `version`, it is the version to publish); `tag-prefix`, `path`, `workspace`,
`package`, `project` and `args` cannot be combined with `archive`. Migrating a crate built
for a retired registry:

```yaml
- uses: kduma-OSS/serverless-registry-action/publish@v1
  with:
    ecosystem: cargo
    registry: https://packages.example.com
    archive: dist/licensing-kit-example-1.2.3.crate
    source-registry-index: sparse+https://old.example.com/cargo/index/
```

`archive` needs an `sreg` release that has `--archive`: set `sreg-version` to the release
that introduced it until this action's default catches up.

## Setup

`setup` only installs `sreg`, for workflows that call it directly (`sreg whoami`,
`sreg generic publish --spec …`, several commands in one step):

```yaml
- id: sreg
  uses: kduma-OSS/serverless-registry-action/setup@v1
- run: sreg whoami
  env:
    REGISTRY_URL: https://packages.example.com
    REGISTRY_TOKEN: ${{ secrets.REGISTRY_TOKEN }}
```

| Input | Default | Description |
| --- | --- | --- |
| `sreg-version` | the release named in `setup/action.yml` | Release of `sreg` to install, e.g. `v0.1.0`. |

| Output | Description |
| --- | --- |
| `version` | Installed release, e.g. `v0.1.1`. |
| `path` | Path of the `sreg` binary. |

## Auth

`auth` lets the package manager install packages from the registry: it runs
`sreg auth <ecosystem> --write <file>`, which adds the registry's token to the package
manager's credentials file (other content of the file is kept). See
[`sreg auth`](https://github.com/kduma-OSS/serverless-registry-cli/blob/main/docs/cli-auth.md)
for the exact entries.

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: shivammathur/setup-php@v2
        with:
          php-version: "8.3"
      - uses: kduma-OSS/serverless-registry-action/auth@v1
        with:
          ecosystem: composer
          registry: https://packages.example.com
      - run: composer install
```

The token is passed like for `publish`: `token` (a token whose scope includes `read`, e.g. `${{ secrets.REGISTRY_TOKEN }}`), credentials in `registry`, or, without
either, the job's OIDC token (`id-token: write`, optional `oidc-project`, passed as
`sreg auth --project`). GitHub OIDC tokens are valid for minutes only, so run `auth`
right before the step that installs packages.

| Input | Default | Description |
| --- | --- | --- |
| `ecosystem` | – (required) | `composer`, `npm`, `cargo`, `nuget`, `swift` or `maven`. |
| `registry` | – (required) | Base URL of the registry; may carry the token as `https://<login>:<password>@host`. |
| `token` | empty | Token (`REGISTRY_TOKEN`). Empty, and no credentials in `registry`: OIDC. |
| `oidc-project` | empty | With OIDC: the project of the token. |
| `write` | the package manager's user file (below) | Credentials file to write. |
| `registry-name` | `sreg` | cargo, nuget, maven: registry name, NuGet source name, Maven server `<id>`. |
| `npm-scope` | empty | npm: also write `@<scope>:registry=<registry>/npm/` to the file. |
| `cargo-config` | `true` | cargo: also declare `[registries.<name>]` with `index = "sparse+<registry>/cargo/index/"` in `config.toml` next to the credentials file (left alone when it is declared already). |
| `swift-scope` | empty | swift: also run `swift package-registry set --global <registry>/swift --scope <scope>`. |
| `sreg-version` | the release named in `auth/action.yml` | Release of `sreg` to install. |

| Output | Description |
| --- | --- |
| `file` | Path of the credentials file that was written. |

Default credentials files:

| Ecosystem | File |
| --- | --- |
| composer | `auth.json` in `$COMPOSER_HOME`, or in `composer config --global home` (Composer must then be installed) |
| npm | npm's user config (`npm config get userconfig`, which follows `NPM_CONFIG_USERCONFIG`), else `~/.npmrc` |
| cargo | `$CARGO_HOME/credentials.toml` (default `~/.cargo`) |
| nuget | `~/.nuget/NuGet/NuGet.Config`; on Windows `%APPDATA%\NuGet\NuGet.Config` |
| swift | `~/.netrc`; on Windows `%USERPROFILE%\_netrc` |
| maven | `~/.m2/settings.xml` |

Composite actions have no post step, so the file stays on the runner after the job. That
does not matter on GitHub-hosted runners; on self-hosted runners prefer short-lived OIDC
tokens, or pass a `write` path under `$RUNNER_TEMP` and point the package manager at it.

### npm

```yaml
- uses: actions/setup-node@v4
  with:
    node-version: 22
- uses: kduma-OSS/serverless-registry-action/auth@v1
  with:
    ecosystem: npm
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_TOKEN }}
    npm-scope: "@acme"
- run: npm ci
```

### cargo

```yaml
- uses: dtolnay/rust-toolchain@stable
- uses: kduma-OSS/serverless-registry-action/auth@v1
  with:
    ecosystem: cargo
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_TOKEN }}
    registry-name: acme # dependencies use `registry = "acme"`
- run: cargo build --locked
```

### NuGet, Swift, Maven

```yaml
- uses: kduma-OSS/serverless-registry-action/auth@v1
  with:
    ecosystem: nuget # adds the source `sreg` with its credentials
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_TOKEN }}
- run: dotnet restore
```

For Swift, `swift-scope: acme` also points the scope at the registry. For Maven, the
`<repository>` (or `<mirror>`) of the build must use the `registry-name` as its `<id>`.

## Get

`get` downloads the files of one generic package version, verified against their size and
SHA-256. The version (`latest`, an exact version or a constraint) is resolved first, so
the `version` output always names what was downloaded.

```yaml
- id: tool
  uses: kduma-OSS/serverless-registry-action/get@v1
  with:
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_TOKEN }}
    name: tools/acme-tool
    version: ^1.2
    labels: os=linux
    sole: true
    out: bin/acme-tool.tar.gz
- run: tar -xzf "${{ steps.tool.outputs.path }}" -C bin
```

| Input | Default | Description |
| --- | --- | --- |
| `registry` | – (required) | Base URL of the registry; may carry the token. |
| `token` | empty | Token. Empty, and no credentials in `registry`: OIDC (`id-token: write`). |
| `oidc-project` | empty | With OIDC: the project of the token. |
| `name` | – (required) | Package name, `[<group>/]<name>`. |
| `version` | `latest` | Exact version, constraint (`^1.2`, `>=1 <2`, `1.x`) or `latest`. |
| `labels` | empty | `key=value` labels the files must have, one per line or comma-separated. |
| `sole` | `false` | Fail unless the labels select exactly one file; `out` may then name the file. |
| `out` | `.` | Directory for the files; with `sole` also a file path. |
| `prerelease` | `false` | With `latest` or a constraint, consider prereleases. |
| `sreg-version` | the release named in `get/action.yml` | Release of `sreg` to install. |

| Output | Description |
| --- | --- |
| `version` | The downloaded version. |
| `files` | Paths of the downloaded files, one per line. |
| `path` | The downloaded file when there is exactly one (always with `sole`), else empty. |

## Pinning `sreg`

Each release of the actions installs one `sreg` release by default: the `default:` of the
`sreg-version` input, the same in every `action.yml`, named as "Default sreg release" in
the [changelog](CHANGELOG.md). The action follows stable `sreg` releases on its own: a new
CLI release triggers a patch release of the action with the new default (within an hour
at the latest), so `@v1` picks it up without any change in your workflow.

Pass `sreg-version` to install another release, e.g. to stay on a tested one or to try a
prerelease:

```yaml
- uses: kduma-OSS/serverless-registry-action/publish@v1
  with:
    ecosystem: composer
    registry: https://packages.example.com
    token: ${{ secrets.REGISTRY_PUBLISH_TOKEN }}
    sreg-version: v0.1.0
```

A pinned `sreg-version` is never updated for you: when the registry later requires a
newer client, the step fails with exit code `3` until you raise it.

## Versioning

The actions are released together, under one version, independently of the `sreg` CLI
([semver](https://semver.org); see the [changelog](CHANGELOG.md)); `@v1` of `publish`,
`setup`, `auth` and `get` is the same commit:

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
  `kduma-OSS/serverless-registry-action` only. Its App ID and private key (PEM)
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

The scripts (`install.sh`, `publish.sh`, `auth.sh`, `get.sh` and the shared `lib.sh`) are
plain bash; `test/smoke.sh` tests them against a fake `sreg` release served from a local
HTTP server, without network access or a registry:

```
test/smoke.sh
shellcheck install.sh publish.sh auth.sh get.sh lib.sh test/*.sh test/fake-sreg
python3 -m unittest discover -s scripts
```

See [`AGENTS.md`](AGENTS.md) for the contribution rules.

## License

MIT, see [`LICENSE`](LICENSE).
