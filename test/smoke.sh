#!/usr/bin/env bash
# Smoke test of install.sh and publish.sh without the network or a registry:
#
# - serves a fake sreg release (test/make-fake-release.sh) from a local HTTP server and
#   installs it with install.sh: the checksum is verified, the binary unpacked and its
#   directory written to $GITHUB_PATH; a wrong checksum, a missing release and an empty
#   sreg-version fail;
#   a second run reuses the installed release without downloading it;
# - runs publish.sh with the fake sreg on PATH for a composer dry run and checks the
#   arguments sreg got and the step outputs; an input of another ecosystem fails;
# - runs auth.sh for composer, npm (with a scope), cargo (with the registry declaration)
#   and OIDC, and get.sh with and without `sole`, and checks the files and outputs.
#
# - runs install.sh as on a Windows runner (RUNNER_OS=Windows), which unpacks the zip.
#
# Needs bash, curl, python3, tar with xz, unzip, jq. Runs on Linux, macOS and Windows (Git
# Bash). Usage: test/smoke.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
python="$(command -v python3 || command -v python)"
# Under Git Bash install.sh writes Windows paths to GITHUB_PATH and the binary is sreg.exe.
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) windows=true exe=sreg.exe ;;
  *) windows=false exe=sreg ;;
esac
# A path as auth.sh hands it to sreg and writes it to the outputs: a Windows path under Git Bash.
native() {
  if $windows; then cygpath -w "$1"; else printf '%s\n' "$1"; fi
}
work="$(mktemp -d)"
server_pid=""
cleanup() {
  if [ -n "$server_pid" ]; then kill "$server_pid" 2> /dev/null || true; fi
  rm -rf "$work"
}
trap cleanup EXIT

failures=0
pass() { echo "ok - $*"; }
fail() {
  echo "not ok - $*" >&2
  failures=$((failures + 1))
}

# --- A fake release on a local HTTP server -------------------------------------------
"$root/test/make-fake-release.sh" "$work/releases" v9.9.9
"$root/test/make-fake-release.sh" "$work/releases" v9.9.8
for sum in "$work"/releases/v9.9.8/*.sha256; do
  # A digest that matches no archive.
  echo "$(printf '0%.0s' $(seq 64)) *$(basename "${sum%.sha256}")" > "$sum"
done

"$python" -u -m http.server 0 --bind 127.0.0.1 --directory "$work/releases" \
  > "$work/server.log" 2>&1 &
server_pid=$!
port=""
for _ in $(seq 50); do
  port="$(sed -n 's/^Serving HTTP on .* port \([0-9][0-9]*\).*/\1/p' "$work/server.log")"
  [ -n "$port" ] && break
  sleep 0.2
done
[ -n "$port" ] || {
  cat "$work/server.log" >&2
  echo "the HTTP server did not start" >&2
  exit 1
}
releases_url="http://127.0.0.1:$port"

# Runs install.sh into a fresh RUNNER_TEMP; prints its output.
install() {
  rm -rf "$work/runner"
  mkdir -p "$work/runner"
  : > "$work/github_path"
  env RUNNER_TEMP="$work/runner" GITHUB_PATH="$work/github_path" \
    SREG_RELEASES_URL="$releases_url" SREG_VERSION="$1" \
    bash "$root/install.sh" > "$work/install.log" 2>&1
}

# --- install.sh ------------------------------------------------------------------------
if install 9.9.9; then
  bin_dir="$(head -n 1 "$work/github_path" | tr -d '\r')"
  if $windows; then bin_dir="$(cygpath -u "$bin_dir")"; fi
  if [ -x "$bin_dir/$exe" ] && [ "$("$bin_dir/$exe" --version)" = "sreg 9.9.9 (fake)" ] &&
    grep -q '^Checksum verified: ' "$work/install.log"; then
    pass "install.sh installs the release and adds it to GITHUB_PATH"
  else
    cat "$work/install.log" "$work/github_path" >&2
    fail "install.sh did not install the binary"
  fi
else
  cat "$work/install.log" >&2
  fail "install.sh failed for a valid release"
fi

# Installing the same release again into the same RUNNER_TEMP downloads nothing: the
# releases URL points at a closed port.
: > "$work/github_output"
if env RUNNER_TEMP="$work/runner" GITHUB_PATH="$work/github_path" \
  GITHUB_OUTPUT="$work/github_output" SREG_RELEASES_URL=http://127.0.0.1:9 SREG_VERSION=v9.9.9 \
  bash "$root/install.sh" > "$work/install.log" 2>&1 &&
  grep -q 'already installed' "$work/install.log" &&
  grep -qx 'version=v9.9.9' "$work/github_output" &&
  grep -Eq '^path=.*[/\\]sreg(\.exe)?$' "$work/github_output"; then
  pass "install.sh reuses an installed release and writes the outputs"
else
  cat "$work/install.log" "$work/github_output" >&2
  fail "install.sh did not reuse the installed release"
fi

# The Windows build: a zip with sreg.exe; the runner variables select it on any host.
rm -rf "$work/runner"
mkdir -p "$work/runner"
if env RUNNER_OS=Windows RUNNER_ARCH=X64 RUNNER_TEMP="$work/runner" \
  SREG_RELEASES_URL="$releases_url" SREG_VERSION=9.9.9 \
  bash "$root/install.sh" > "$work/install.log" 2>&1 &&
  grep -q 'x86_64-pc-windows-msvc' "$work/install.log" &&
  [ -n "$(find "$work/runner/sreg" -type f -name sreg.exe)" ]; then
  pass "install.sh unpacks the Windows zip"
else
  cat "$work/install.log" >&2
  fail "install.sh did not install the Windows build"
fi

if install v9.9.8; then
  fail "install.sh accepted a checksum mismatch"
elif grep -q 'checksum mismatch' "$work/install.log"; then
  pass "install.sh rejects a checksum mismatch"
else
  cat "$work/install.log" >&2
  fail "install.sh failed without reporting the checksum mismatch"
fi

if install v1.0.0; then
  fail "install.sh accepted a missing release"
else
  pass "install.sh fails for a missing release"
fi

if install ""; then
  fail "install.sh accepted an empty sreg-version"
elif grep -q "sreg-version" "$work/install.log"; then
  pass "install.sh rejects an empty sreg-version"
else
  cat "$work/install.log" >&2
  fail "install.sh failed without naming sreg-version"
fi

# --- publish.sh ------------------------------------------------------------------------
# A directory with the fake sreg, independent of the install cases above.
mkdir -p "$work/bin"
cp "$root/test/fake-sreg" "$work/bin/sreg"
chmod +x "$work/bin/sreg"

# Runs publish.sh with only the given variables (and PATH) set.
publish() {
  : > "$work/github_output"
  rm -f "$work/sreg.log" "$work/sreg.log.env"
  env -i PATH="$work/bin:$PATH" HOME="${HOME:-/tmp}" GITHUB_OUTPUT="$work/github_output" \
    FAKE_SREG_LOG="$work/sreg.log" "$@" \
    bash "$root/publish.sh" > "$work/publish.log" 2>&1
}

if publish INPUT_ECOSYSTEM=composer REGISTRY_URL=https://packages.example.com \
  REGISTRY_TOKEN=ci-acme-sdk:secret INPUT_PATH=packages/sdk INPUT_DRY_RUN=true \
  INPUT_SKIP_EXISTING=true INPUT_EXTRA_FLAGS="--label 'a b=c'" INPUT_ARGS=--no-dev; then
  expected="composer publish --json --path packages/sdk --dry-run --skip-existing --label a b=c -- --no-dev"
  actual="$(paste -sd' ' "$work/sreg.log")"
  outputs="$(cat "$work/github_output")"
  expected_outputs="$(printf 'name=acme/sdk\nversion=1.2.0\nurl=\nskipped=false')"
  if [ "$actual" != "$expected" ]; then
    fail "publish.sh passed: $actual (expected: $expected)"
  elif [ "$(sed -n 5p "$work/sreg.log")" != packages/sdk ] || [ "$(sed -n 9p "$work/sreg.log")" != "a b=c" ]; then
    fail "publish.sh split the arguments wrongly: $(cat "$work/sreg.log")"
  elif ! grep -qx 'REGISTRY_TOKEN=ci-acme-sdk:secret' "$work/sreg.log.env"; then
    fail "publish.sh did not pass REGISTRY_TOKEN: $(cat "$work/sreg.log.env")"
  elif [ "$outputs" != "$expected_outputs" ]; then
    fail "publish.sh wrote the outputs: $outputs"
  else
    pass "publish.sh runs a composer dry run and writes the outputs"
  fi
else
  cat "$work/publish.log" >&2
  fail "publish.sh failed for a composer dry run"
fi

if publish INPUT_ECOSYSTEM=composer REGISTRY_URL=https://packages.example.com \
  REGISTRY_TOKEN=ci-acme-sdk:secret INPUT_WORKSPACE=sdk; then
  fail "publish.sh accepted an npm input for composer"
elif grep -q "does not apply to composer" "$work/publish.log" && [ ! -e "$work/sreg.log" ]; then
  pass "publish.sh rejects an input of another ecosystem before running sreg"
else
  cat "$work/publish.log" >&2
  fail "publish.sh failed without naming the input"
fi

# --- auth.sh ---------------------------------------------------------------------------
# Runs a script of the action ($1) with only the given variables (and PATH, HOME) set.
run_script() {
  local script="$1"
  shift
  : > "$work/github_output"
  rm -f "$work/sreg.log" "$work/sreg.log.all" "$work/sreg.log.env"
  env -i PATH="$work/bin:$PATH" HOME="$work/home" GITHUB_OUTPUT="$work/github_output" \
    FAKE_SREG_LOG="$work/sreg.log" "$@" \
    bash "$root/$script" > "$work/script.log" 2>&1
}
mkdir -p "$work/home"

if run_script auth.sh INPUT_ECOSYSTEM=composer REGISTRY_URL=https://packages.example.com \
  REGISTRY_TOKEN=acme:secret COMPOSER_HOME="$work/composer"; then
  if [ "$(cat "$work/sreg.log.all")" != "auth composer --write $(native "$work/composer/auth.json")" ]; then
    fail "auth.sh ran: $(cat "$work/sreg.log.all")"
  elif ! grep -qx 'composer token=acme:secret' "$work/composer/auth.json"; then
    fail "auth.sh did not write auth.json in COMPOSER_HOME"
  elif ! grep -qxF "file=$(native "$work/composer/auth.json")" "$work/github_output"; then
    fail "auth.sh wrote the outputs: $(cat "$work/github_output")"
  else
    pass "auth.sh writes composer's auth.json in COMPOSER_HOME"
  fi
else
  cat "$work/script.log" >&2
  fail "auth.sh failed for composer"
fi

npmrc="$work/npm/.npmrc"
for _ in 1 2; do
  run_script auth.sh INPUT_ECOSYSTEM=npm REGISTRY_URL=https://ci:secret@packages.example.com/ \
    INPUT_WRITE="$npmrc" INPUT_NPM_SCOPE=acme || {
    cat "$work/script.log" >&2
    fail "auth.sh failed for npm"
  }
done
if [ "$(grep -c '^@acme:registry=https://packages.example.com/npm/$' "$npmrc")" = 1 ] &&
  grep -qx 'REGISTRY_TOKEN=<unset>' "$work/sreg.log.env" &&
  ! grep -q 'secret@' "$npmrc"; then
  pass "auth.sh writes the npm scope line once, without the URL credentials"
else
  cat "$npmrc" "$work/sreg.log.env" >&2
  fail "auth.sh wrote the npm scope line wrongly"
fi

for _ in 1 2; do
  run_script auth.sh INPUT_ECOSYSTEM=cargo REGISTRY_URL=https://packages.example.com \
    REGISTRY_TOKEN=acme:secret CARGO_HOME="$work/cargo" INPUT_REGISTRY_NAME=internal || {
    cat "$work/script.log" >&2
    fail "auth.sh failed for cargo"
  }
done
if [ "$(cat "$work/sreg.log.all")" = "auth cargo --write $(native "$work/cargo/credentials.toml") --registry-name internal" ] &&
  [ "$(grep -c -x '\[registries.internal\]' "$work/cargo/config.toml")" = 1 ] &&
  grep -qx 'index = "sparse+https://packages.example.com/cargo/index/"' "$work/cargo/config.toml"; then
  pass "auth.sh writes cargo's credentials and declares the registry once"
else
  cat "$work/sreg.log.all" "$work/cargo/config.toml" >&2
  fail "auth.sh configured cargo wrongly"
fi

if run_script auth.sh INPUT_ECOSYSTEM=maven REGISTRY_URL=https://packages.example.com \
  ACTIONS_ID_TOKEN_REQUEST_URL=https://token.example.com INPUT_OIDC_PROJECT=acme-sdk &&
  [ "$(cat "$work/sreg.log.all")" = "auth maven --write $(native "$work/home/.m2/settings.xml") --oidc --project acme-sdk" ]; then
  pass "auth.sh uses OIDC with --project and writes ~/.m2/settings.xml"
else
  cat "$work/script.log" "$work/sreg.log.all" >&2
  fail "auth.sh did not use OIDC for maven"
fi

if run_script auth.sh INPUT_ECOSYSTEM=composer REGISTRY_URL=https://packages.example.com \
  REGISTRY_TOKEN=acme:secret INPUT_WRITE="$work/auth.json" INPUT_NPM_SCOPE=acme; then
  fail "auth.sh accepted an npm input for composer"
elif grep -q "does not apply to composer" "$work/script.log" && [ ! -e "$work/sreg.log" ]; then
  pass "auth.sh rejects an input of another ecosystem before running sreg"
else
  cat "$work/script.log" >&2
  fail "auth.sh failed without naming the input"
fi

# --- get.sh ----------------------------------------------------------------------------
if run_script get.sh REGISTRY_URL=https://packages.example.com REGISTRY_TOKEN=acme:secret \
  INPUT_NAME=acme/tool INPUT_VERSION=^1 INPUT_LABELS="os=linux, arch=x64" INPUT_SOLE=true \
  INPUT_OUT="$work/dist" INPUT_PRERELEASE=false; then
  expected="$(printf '%s\n' \
    "generic get acme/tool ^1 --json --label os=linux --label arch=x64 --sole" \
    "generic get acme/tool 1.4.0 --label os=linux --label arch=x64 --sole --out $work/dist")"
  expected_outputs="$(printf '%s\n' version=1.4.0 "files=$work/dist/tool-linux.tar.gz" \
    "path=$work/dist/tool-linux.tar.gz")"
  if [ "$(cat "$work/sreg.log.all")" != "$expected" ]; then
    fail "get.sh ran: $(cat "$work/sreg.log.all")"
  elif [ "$(cat "$work/github_output")" != "$expected_outputs" ]; then
    fail "get.sh wrote the outputs: $(cat "$work/github_output")"
  else
    pass "get.sh resolves the version, downloads the sole file and writes the outputs"
  fi
else
  cat "$work/script.log" >&2
  fail "get.sh failed with sole"
fi

if run_script get.sh REGISTRY_URL=https://packages.example.com \
  ACTIONS_ID_TOKEN_REQUEST_URL=https://token.example.com INPUT_NAME=acme/tool \
  INPUT_OUT="$work/all"; then
  if [ "$(head -n 1 "$work/sreg.log.all")" != "generic get acme/tool latest --json --oidc" ]; then
    fail "get.sh ran: $(cat "$work/sreg.log.all")"
  elif ! grep -q '^files<<EOF_' "$work/github_output" || ! grep -qx 'path=' "$work/github_output" ||
    ! grep -qx "$work/all/tool-macos.tar.gz" "$work/github_output"; then
    fail "get.sh wrote the outputs: $(cat "$work/github_output")"
  else
    pass "get.sh downloads every file of the latest version with OIDC"
  fi
else
  cat "$work/script.log" >&2
  fail "get.sh failed without sole"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "all checks passed"
