#!/usr/bin/env bash
# Run suites for installed shells. Report missing shells as skipped, and use an
# isolated store in every suite.

set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$(dirname -- "$here")

# Use a path form that PowerShell and the POSIX shells both resolve.
winpath() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m -- "$1"
  else
    printf '%s' "$1"
  fi
}
repo_win=$(winpath "$repo")

failed=0
skipped=()

need() {
  if command -v "$1" >/dev/null 2>&1; then
    return 0
  fi
  skipped+=("$2 (no $1)")
  return 1
}

run() {
  local label=$1; shift
  if "$@"; then
    return 0
  fi
  printf '%s: FAILED\n' "$label" >&2
  failed=1
}

need gawk 'codec-awk'   && run codec-awk   bash "$here/codec-awk.sh"
need gawk 'codec-bash'  && run codec-bash  bash "$here/codec-bash.sh"
need zsh  'codec-zsh'   && run codec-zsh   bash "$here/codec-zsh.sh"
need fish 'codec-fish'  && run codec-fish  bash "$here/codec-fish.sh"
need fish 'plugin-fish' && run plugin-fish bash "$here/plugin-fish.sh"
need fish 'path-fish'   && run path-fish   bash "$here/path-fish.sh"
need gawk 'record'      && run record      bash "$here/record.sh"
need gawk 'migrate'     && run migrate     bash "$here/migrate.sh"
need gawk 'permissions' && run permissions bash "$here/permissions.sh"

if need pwsh 'codec-pwsh'; then
  sandbox=${TMPDIR:-/tmp}/skell-pwsh-$$
  mkdir -p "$sandbox"
  sandbox_win=$(winpath "$sandbox")
  run codec-pwsh env "SKELL_DATA_DIR=$sandbox_win" "SKELL_HISTORY=$sandbox_win/history.tsv" \
    pwsh -NoLogo -NoProfile -File "$repo_win/tests/codec-pwsh.ps1" \
    -VectorsTsv "$repo_win/tests/lib/vectors.tsv" \
    -ModulePath "$repo_win/powershell/Skell.psm1"
  run lifecycle-pwsh env "SKELL_DATA_DIR=$sandbox_win" "SKELL_HISTORY=$sandbox_win/history.tsv" \
    pwsh -NoLogo -NoProfile -File "$repo_win/tests/lifecycle-pwsh.ps1" \
    -ModulePath "$repo_win/powershell/Skell.psm1" -Sandbox "$sandbox_win"
  rm -rf -- "$sandbox"
fi

if [ ${#skipped[@]} -gt 0 ]; then
  printf 'skipped: %s\n' "$(IFS=', '; printf '%s' "${skipped[*]}")"
fi
if [ "$failed" -ne 0 ]; then
  printf 'run-all: one or more suites failed\n' >&2
  exit 1
fi
printf 'run-all: every available suite passed\n'
