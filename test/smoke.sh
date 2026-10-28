#!/usr/bin/env bash
# Smoke test of install.sh and publish.sh without the network or a registry:
#
# - serves a fake sreg release (test/make-fake-release.sh) from a local HTTP server and
#   installs it with install.sh: the checksum is verified, the binary unpacked and its
#   directory written to $GITHUB_PATH; a wrong checksum, a missing release and an empty
#   sreg-version fail;
# - runs publish.sh with the fake sreg on PATH for a composer dry run and checks the
#   arguments sreg got and the step outputs; an input of another ecosystem fails.
#
# Needs bash, curl, python3, tar with xz, jq. Usage: test/smoke.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
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

python3 -u -m http.server 0 --bind 127.0.0.1 --directory "$work/releases" \
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
  bin_dir="$(head -n 1 "$work/github_path")"
  if [ -x "$bin_dir/sreg" ] && [ "$("$bin_dir/sreg" --version)" = "sreg 9.9.9 (fake)" ] &&
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

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "all checks passed"
