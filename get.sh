#!/usr/bin/env bash
# Downloads files of a generic package version with `sreg generic get`, using the get
# action's inputs (INPUT_* variables), and writes the `version`, `files` and `path`
# outputs to $GITHUB_OUTPUT. The version (`latest` or a constraint) is resolved first
# (`--json`), then exactly that version is downloaded, so the outputs always agree.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

name="$(trim "${INPUT_NAME:-}")"
[ -n "$name" ] || fail "the input 'name' is required"
[ -n "${REGISTRY_URL:-}" ] || fail "the input 'registry' is required"
requested="$(trim "${INPUT_VERSION:-}")"
requested="${requested:-latest}"
out="${INPUT_OUT:-.}"

filters=()
while IFS= read -r label || [ -n "$label" ]; do
  label="$(trim "$label")"
  [ -z "$label" ] && continue
  case "$label" in
    *=*) filters+=(--label "$label") ;;
    *) fail "the label '$label' is not key=value" ;;
  esac
done < <(printf '%s\n' "${INPUT_LABELS:-}" | tr ',' '\n')
if is_true "${INPUT_SOLE:-false}"; then filters+=(--sole); fi

auth=()
auth_flags auth --oidc-project

resolve=(sreg generic get "$name" "$requested" --json ${filters[@]+"${filters[@]}"})
if is_true "${INPUT_PRERELEASE:-false}"; then resolve+=(--prerelease); fi
resolve+=(${auth[@]+"${auth[@]}"})
print_command "${resolve[@]}"
entry="$("${resolve[@]}")"
# `tr` drops the carriage returns jq prints on Windows.
version="$(jq -r '.version // empty' <<< "$entry" | tr -d '\r')"
[ -n "$version" ] || fail "sreg printed no version for $name $requested"
echo "Resolved $name $requested to $version"

download=(sreg generic get "$name" "$version" ${filters[@]+"${filters[@]}"} --out "$out")
download+=(${auth[@]+"${auth[@]}"})
print_command "${download[@]}"
files="$("${download[@]}" | tr -d '\r')"
printf '%s\n' "$files"

set_output version "$version"
set_output files "$files"
case "$files" in
  *$'\n'*) set_output path "" ;;
  *) set_output path "$files" ;;
esac
