#!/usr/bin/env bash
# Helpers shared by publish.sh, auth.sh and get.sh; sourced, not run.

fail() {
  echo "::error::$*" >&2
  exit 1
}

# Splits a string into words with shell-like quoting (no expansion, no command
# substitution) and appends them to the array named by $1.
split_words() {
  local __name="$1" __input="$2" __word
  case "$__input" in
    *[![:space:]]*) ;;
    *) return 0 ;;
  esac
  while IFS= read -r -d '' __word; do
    eval "$__name+=(\"\$__word\")"
  done < <(printf '%s\n' "$__input" | xargs printf '%s\0')
}

is_true() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    true | yes | 1 | on) return 0 ;;
    false | no | 0 | off | "") return 1 ;;
    *) fail "expected true or false, got '$1'" ;;
  esac
}

# Trims leading and trailing white space.
trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  printf '%s' "${value%"${value##*[![:space:]]}"}"
}

# A registry URL with userinfo (https://<login>:<password>@host/) carries the token.
url_has_credentials() {
  [[ "${REGISTRY_URL:-}" =~ ^[A-Za-z][A-Za-z0-9+.-]*://[^/?#]*@ ]]
}

# Chooses how sreg authenticates and appends the flags to the array named by $1: the
# `token` input (REGISTRY_TOKEN), the credentials of the registry URL, or, without either,
# the job's OIDC token (`--oidc`, plus the project flag named by $2 with
# INPUT_OIDC_PROJECT). Unsets an empty REGISTRY_TOKEN so that sreg does not see it.
auth_flags() {
  local __name="$1" __project_flag="$2"
  if [ -z "${REGISTRY_TOKEN:-}" ] && url_has_credentials; then
    unset REGISTRY_TOKEN
    [ -z "${INPUT_OIDC_PROJECT:-}" ] || fail "'oidc-project' applies only to OIDC, not to credentials in 'registry'"
  elif [ -z "${REGISTRY_TOKEN:-}" ]; then
    unset REGISTRY_TOKEN
    [ -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] ||
      fail "no token given and no OIDC token available: grant the job 'permissions: id-token: write' or pass 'token'"
    eval "$__name+=(--oidc)"
    if [ -n "${INPUT_OIDC_PROJECT:-}" ]; then
      eval "$__name+=(\"\$__project_flag\" \"\$INPUT_OIDC_PROJECT\")"
    fi
  else
    [ -z "${INPUT_OIDC_PROJECT:-}" ] || fail "'oidc-project' applies only without 'token'"
  fi
}

# Prints a path in the form the sreg binary takes: a Windows path on Windows runners.
native_path() {
  if command -v cygpath > /dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s' "$1"
  fi
}

# Writes `name=value` to $GITHUB_OUTPUT; a multi-line value as a heredoc.
set_output() {
  [ -n "${GITHUB_OUTPUT:-}" ] || return 0
  local name="$1" value="$2" delimiter
  case "$value" in
    *$'\n'*)
      delimiter="EOF_$RANDOM$RANDOM$RANDOM"
      printf '%s<<%s\n%s\n%s\n' "$name" "$delimiter" "$value" "$delimiter" >> "$GITHUB_OUTPUT"
      ;;
    *) printf '%s=%s\n' "$name" "$value" >> "$GITHUB_OUTPUT" ;;
  esac
}

# Prints the command about to run, quoted.
print_command() {
  printf 'Running:'
  printf ' %q' "$@"
  printf '\n'
}
