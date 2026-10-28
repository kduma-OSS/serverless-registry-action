#!/usr/bin/env bash
# Runs `sreg auth <ecosystem> --write <file>` with the auth action's inputs (INPUT_*
# variables), so that the package manager can install packages from the registry, and
# writes the `file` output to $GITHUB_OUTPUT. Without the `write` input, the file is the
# package manager's own user-level credentials file. Optionally also declares the
# registry: the npm scope line, the cargo registry and the Swift scope.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ecosystem="$(printf '%s' "${INPUT_ECOSYSTEM:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
case "$ecosystem" in
  composer | npm | cargo | nuget | swift | maven) ;;
  "") fail "the input 'ecosystem' is required" ;;
  generic) fail "generic packages have no package manager: use kduma-OSS/serverless-registry-action/get" ;;
  *) fail "unknown ecosystem '$ecosystem' (composer, npm, cargo, nuget, swift or maven)" ;;
esac
[ -n "${REGISTRY_URL:-}" ] || fail "the input 'registry' is required"

# Rejects an input that the selected ecosystem does not take.
only_for() {
  local input="$1" value="$2"
  shift 2
  [ -z "$value" ] && return 0
  local eco
  for eco in "$@"; do
    [ "$eco" = "$ecosystem" ] && return 0
  done
  fail "the input '$input' does not apply to $ecosystem (only to: $*)"
}

only_for registry-name "${INPUT_REGISTRY_NAME:-}" cargo nuget maven
only_for npm-scope "${INPUT_NPM_SCOPE:-}" npm
only_for swift-scope "${INPUT_SWIFT_SCOPE:-}" swift

# The registry URL without credentials and without a trailing slash.
base="$(printf '%s' "$REGISTRY_URL" | sed -E 's#^([A-Za-z][A-Za-z0-9+.-]*://)[^/?#]*@#\1#; s#/+$##')"
registry_name="${INPUT_REGISTRY_NAME:-sreg}"

# A path in the POSIX form of this shell (Git Bash on Windows).
posix_path() {
  if command -v cygpath > /dev/null 2>&1; then
    cygpath -u "$1"
  else
    printf '%s' "$1"
  fi
}

windows() {
  [ "${RUNNER_OS:-}" = Windows ] || command -v cygpath > /dev/null 2>&1
}

# The user-level credentials file of the package manager.
default_file() {
  case "$ecosystem" in
    composer)
      local home="${COMPOSER_HOME:-}"
      if [ -z "$home" ]; then
        command -v composer > /dev/null 2>&1 ||
          fail "composer is not installed, so its home directory is unknown: install it in an earlier step or pass 'write'"
        home="$(composer config --global home 2> /dev/null | tr -d '\r')"
        [ -n "$home" ] || fail "'composer config --global home' printed nothing: pass 'write'"
      fi
      printf '%s/auth.json' "$(posix_path "$home")"
      ;;
    npm)
      local userconfig=""
      if command -v npm > /dev/null 2>&1; then
        userconfig="$(npm config get userconfig 2> /dev/null | tr -d '\r' || true)"
      fi
      if [ -n "$userconfig" ]; then
        posix_path "$userconfig"
      else
        printf '%s/.npmrc' "$HOME"
      fi
      ;;
    cargo)
      printf '%s/credentials.toml' "$(posix_path "${CARGO_HOME:-$HOME/.cargo}")"
      ;;
    nuget)
      if windows && [ -n "${APPDATA:-}" ]; then
        printf '%s/NuGet/NuGet.Config' "$(posix_path "$APPDATA")"
      else
        printf '%s/.nuget/NuGet/NuGet.Config' "$HOME"
      fi
      ;;
    swift)
      if windows && [ -n "${USERPROFILE:-}" ]; then
        printf '%s/_netrc' "$(posix_path "$USERPROFILE")"
      else
        printf '%s/.netrc' "$HOME"
      fi
      ;;
    maven)
      printf '%s/.m2/settings.xml' "$HOME"
      ;;
  esac
}

if [ -n "${INPUT_WRITE:-}" ]; then
  file="$INPUT_WRITE"
else
  file="$(default_file)"
fi

cmd=(sreg auth "$ecosystem" --write "$(native_path "$file")")
[ -z "${INPUT_REGISTRY_NAME:-}" ] || cmd+=(--registry-name "$INPUT_REGISTRY_NAME")
auth_flags cmd --project

print_command "${cmd[@]}"
"${cmd[@]}"

# npm: the scope line that sends the scope's packages to the registry.
if [ -n "${INPUT_NPM_SCOPE:-}" ]; then
  scope="$(trim "$INPUT_NPM_SCOPE")"
  scope="@${scope#@}"
  [[ "$scope" =~ ^@[a-z0-9][a-z0-9._~-]*$ ]] || fail "npm: '$INPUT_NPM_SCOPE' is not a scope such as @acme"
  line="$scope:registry=$base/npm/"
  temp_file="$file.sreg-tmp"
  { grep -v -F -e "$scope:registry=" "$file" || true; } > "$temp_file"
  printf '%s\n' "$line" >> "$temp_file"
  mv "$temp_file" "$file"
  echo "Wrote $line to $file."
fi

# cargo: the registry itself, in config.toml next to credentials.toml.
if [ "$ecosystem" = cargo ] && is_true "${INPUT_CARGO_CONFIG:-true}"; then
  config="$(dirname "$file")/config.toml"
  header="[registries.$registry_name]"
  if [ -f "$config" ] && grep -q -F -x -e "$header" "$config"; then
    echo "$config already declares $header; left unchanged."
  else
    separator=""
    if [ -s "$config" ]; then separator=$'\n'; fi
    {
      printf '%s' "$separator"
      echo "$header"
      echo "index = \"sparse+$base/cargo/index/\""
    } >> "$config"
    echo "Declared $header in $config."
  fi
fi

# swift: the registry for the scope, in SwiftPM's global configuration.
if [ -n "${INPUT_SWIFT_SCOPE:-}" ]; then
  command -v swift > /dev/null 2>&1 ||
    fail "swift: 'swift-scope' needs swift on PATH; install it in an earlier step"
  set_cmd=(swift package-registry set --global "$base/swift" --scope "$(trim "$INPUT_SWIFT_SCOPE")")
  print_command "${set_cmd[@]}"
  "${set_cmd[@]}"
fi

set_output file "$(native_path "$file")"
