#!/usr/bin/env bash
# Builds a fake sreg release in the layout of the GitHub releases of the CLI:
#
#   <dir>/<tag>/sreg-cli-<target>.tar.xz          (holds sreg-cli-<target>/sreg)
#   <dir>/<tag>/sreg-cli-<target>.tar.xz.sha256   (`<sha256> *<archive>`)
#   <dir>/<tag>/sreg-cli-x86_64-pc-windows-msvc.zip   (holds sreg-cli-<target>/sreg.exe)
#   <dir>/<tag>/sreg-cli-x86_64-pc-windows-msvc.zip.sha256
#
# for every target install.sh knows, with test/fake-sreg as the binary (a bash script,
# also under the name sreg.exe, which Git Bash on Windows runs through its shebang).
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

# The Windows archive is a zip; Python writes it, as Git Bash on Windows has no `zip`.
python="$(command -v python3 || command -v python)"
name="sreg-cli-x86_64-pc-windows-msvc"
"$python" - "$here/fake-sreg" "$dir/$tag/$name.zip" "$name" << 'PYTHON'
import sys
import zipfile

fake, archive, name = sys.argv[1:]
with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
    z.write(fake, f"{name}/sreg.exe")
PYTHON
echo "$(sha256 "$dir/$tag/$name.zip") *$name.zip" > "$dir/$tag/$name.zip.sha256"
