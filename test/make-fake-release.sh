#!/usr/bin/env bash
# Builds a fake sreg release in the layout of the GitHub releases of the CLI:
#
#   <dir>/<tag>/sreg-cli-<target>.tar.xz          (holds sreg-cli-<target>/sreg)
#   <dir>/<tag>/sreg-cli-<target>.tar.xz.sha256   (`<sha256> *<archive>`)
#
# for every non-Windows target install.sh knows, with test/fake-sreg as the binary.
# Serve <dir> over HTTP and point SREG_RELEASES_URL at it.
#
# Usage: test/make-fake-release.sh <dir> <tag>
set -euo pipefail

[ "$#" -eq 2 ] || {
  echo "usage: $0 <dir> <tag>" >&2
  exit 2
}
dir="$1"
tag="$2"
here="$(cd "$(dirname "$0")" && pwd)"

sha256() {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

mkdir -p "$dir/$tag"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

for target in x86_64-unknown-linux-musl aarch64-unknown-linux-gnu x86_64-apple-darwin aarch64-apple-darwin; do
  name="sreg-cli-$target"
  mkdir -p "$staging/$name"
  cp "$here/fake-sreg" "$staging/$name/sreg"
  chmod +x "$staging/$name/sreg"
  tar -cJf "$dir/$tag/$name.tar.xz" -C "$staging" "$name"
  echo "$(sha256 "$dir/$tag/$name.tar.xz") *$name.tar.xz" > "$dir/$tag/$name.tar.xz.sha256"
done
