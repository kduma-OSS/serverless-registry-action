#!/usr/bin/env bash
# Installs the sreg release binary for the current runner into $RUNNER_TEMP/sreg and
# adds it to $GITHUB_PATH, after verifying the archive against the SHA-256 checksum
# published with the release. When that directory already holds the requested release
# (an earlier step of the job installed it), it is reused without a download. Writes the
# `version` and `path` (of the binary) outputs to $GITHUB_OUTPUT.
#
# Environment:
#   SREG_VERSION       release tag to install (`v0.1.0` or `0.1.0`), from the action's
#                      `sreg-version` input (whose default names the default release)
#   SREG_RELEASES_URL  base URL of the releases (default: the GitHub releases of
#                      kduma-OSS/serverless-registry-cli)
set -euo pipefail

releases_url="${SREG_RELEASES_URL:-https://github.com/kduma-OSS/serverless-registry-cli/releases/download}"

version="$(printf '%s' "${SREG_VERSION:-}" | tr -d '[:space:]')"
if [ -z "$version" ]; then
  echo "::error::the input 'sreg-version' is empty; pass a release such as v0.1.0 or omit it for the default" >&2
  exit 1
fi
version="v${version#v}"

os="${RUNNER_OS:-$(uname -s)}"
arch="${RUNNER_ARCH:-$(uname -m)}"
case "$os/$arch" in
  Linux/X64 | Linux/x86_64) target=x86_64-unknown-linux-musl ;;
  Linux/ARM64 | Linux/aarch64) target=aarch64-unknown-linux-gnu ;;
  macOS/X64 | Darwin/x86_64) target=x86_64-apple-darwin ;;
  macOS/ARM64 | Darwin/arm64) target=aarch64-apple-darwin ;;
  # Windows on ARM runs the x86_64 build through emulation.
  Windows/*) target=x86_64-pc-windows-msvc ;;
  *)
    echo "::error::sreg has no release build for $os/$arch" >&2
    exit 1
    ;;
esac

case "$target" in
  *windows*) archive="sreg-cli-$target.zip" ;;
  *) archive="sreg-cli-$target.tar.xz" ;;
esac

temp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
dest="$temp/sreg"
download="$temp/sreg-download"

find_binary() {
  { find "$dest" -type f \( -name sreg -o -name sreg.exe \) 2> /dev/null || true; } | head -n 1
}

# Adds the binary's directory to $GITHUB_PATH, writes the outputs and prints its version.
finish() {
  local binary="$1" bin_dir path_entry binary_entry
  bin_dir="$(dirname "$binary")"
  if command -v cygpath > /dev/null 2>&1; then
    path_entry="$(cygpath -w "$bin_dir")"
    binary_entry="$(cygpath -w "$binary")"
  else
    path_entry="$bin_dir"
    binary_entry="$binary"
  fi
  if [ -n "${GITHUB_PATH:-}" ]; then
    echo "$path_entry" >> "$GITHUB_PATH"
  fi
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "version=$version"
      echo "path=$binary_entry"
    } >> "$GITHUB_OUTPUT"
  fi
  "$binary" --version
}

# `sreg --version` prints `sreg <version>`.
existing="$(find_binary)"
if [ -n "$existing" ] && [ -x "$existing" ]; then
  installed="$("$existing" --version 2> /dev/null | awk '{ print $2; exit }' | tr -d '\r' || true)"
  if [ "v${installed#v}" = "$version" ]; then
    echo "sreg $version is already installed in $dest"
    finish "$existing"
    exit 0
  fi
fi

rm -rf "$dest" "$download"
mkdir -p "$dest" "$download"

echo "Installing sreg $version ($target)"
url="$releases_url/$version/$archive"
curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
  --output "$download/$archive" "$url"
curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
  --output "$download/$archive.sha256" "$url.sha256"

# The checksum file holds `<sha256>  <file name>`; compare the digest only, so the
# check does not depend on the tool or on the file name format.
expected="$(awk '{ print tolower($1); exit }' "$download/$archive.sha256")"
if command -v sha256sum > /dev/null 2>&1; then
  actual="$(sha256sum "$download/$archive" | awk '{ print tolower($1) }')"
else
  actual="$(shasum -a 256 "$download/$archive" | awk '{ print tolower($1) }')"
fi
if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
  echo "::error::checksum mismatch for $archive: expected ${expected:-nothing}, got $actual" >&2
  exit 1
fi
echo "Checksum verified: $actual"

case "$archive" in
  *.zip) unzip -q -o "$download/$archive" -d "$dest" ;;
  *) tar -xJf "$download/$archive" -C "$dest" ;;
esac
rm -rf "$download"

binary="$(find_binary)"
if [ -z "$binary" ]; then
  echo "::error::the archive $archive does not contain the sreg binary" >&2
  exit 1
fi
chmod +x "$binary" 2> /dev/null || true
finish "$binary"
