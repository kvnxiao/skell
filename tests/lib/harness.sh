# shellcheck shell=bash disable=SC2034
# Shared assertions and store isolation for skell's test scripts. Source it;
# do not execute it.
#
# Sourcing creates a private SKELL_DATA_DIR and exports SKELL_HISTORY into it.
# skell_cleanup removes that directory, so a test must never point
# SKELL_HISTORY at a path it did not create here.
#
# The sandbox lives under MSYS2's own tmp because the runtimes on Windows do
# not share a path namespace: Git-for-Windows mounts /tmp at %LOCALAPPDATA%,
# MSYS2 roots at C:/msys64 and has no /tmp entry, and MSYS2 fish refuses to
# redirect to the mixed C:/... form even where it stats the directory.
# C:/msys64/tmp is the one location that bash, zsh, fish, and PowerShell all
# read and write, each under its own spelling.

set -uo pipefail

SKELL_TEST_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SKELL_REPO_ROOT=$(dirname -- "$SKELL_TEST_ROOT")

skell_pass=0
skell_fail=0
skell_name=$(basename -- "${0%.sh}")

skell_slot=skell-test-$$-${RANDOM:-0}
if [ -d /c/msys64/tmp ]; then
  SKELL_SANDBOX=/c/msys64/tmp/$skell_slot   # this bash
  SKELL_SANDBOX_MSYS=/tmp/$skell_slot       # MSYS2 zsh and fish
else
  SKELL_SANDBOX=$(mktemp -d)
  SKELL_SANDBOX_MSYS=$SKELL_SANDBOX
fi
mkdir -p "$SKELL_SANDBOX"

# PowerShell and the repository are reachable from every runtime only in the
# mixed form, which a Windows runner without MSYS2 also needs.
if command -v cygpath >/dev/null 2>&1; then
  SKELL_SANDBOX_WIN=$(cygpath -m -- "$SKELL_SANDBOX")
  SKELL_REPO_WIN=$(cygpath -m -- "$SKELL_REPO_ROOT")
else
  SKELL_SANDBOX_WIN=$SKELL_SANDBOX
  SKELL_REPO_WIN=$SKELL_REPO_ROOT
fi

export SKELL_DATA_DIR="$SKELL_SANDBOX/data"
export SKELL_HISTORY="$SKELL_DATA_DIR/history.tsv"
export SKELL_ROOT="$SKELL_REPO_ROOT"
mkdir -p "$SKELL_DATA_DIR"

SKELL_VECTORS="$SKELL_SANDBOX/vectors"
bash "$SKELL_TEST_ROOT/lib/vectors.sh" "$SKELL_VECTORS"

skell_cleanup() { rm -rf -- "$SKELL_SANDBOX"; }
trap skell_cleanup EXIT

# Command substitution strips trailing newlines, so an X marks the end and is
# removed. Assigning the result through a second substitution strips it again,
# so any comparison of bytes that may end in a newline goes through
# skell_eq_file instead.
skell_slurp() { local s; s=$(cat -- "$1"; printf X); printf '%s' "${s%X}"; }

skell_eq_file() {
  local label=$1 want=$2 got=$3
  if [ ! -e "$got" ]; then
    skell_not_ok "$label: no output produced"
    return 0
  fi
  if cmp -s -- "$want" "$got"; then
    skell_ok "$label"
  else
    skell_not_ok "$label"
    printf '       want %s\n' "$(od -An -c -- "$want" | tr -s ' ' | tr -d '\n')" >&2
    printf '       got  %s\n' "$(od -An -c -- "$got" | tr -s ' ' | tr -d '\n')" >&2
  fi
}

# Render bytes so a failure names the differing byte rather than showing two
# visually identical control characters.
skell_dump() { printf '%s' "$1" | od -An -c | tr -s ' ' | tr -d '\n'; }

skell_ok() { skell_pass=$((skell_pass + 1)); }

skell_not_ok() {
  skell_fail=$((skell_fail + 1))
  printf '  FAIL %s\n' "$1" >&2
  return 0
}

skell_eq() {
  local label=$1 want=$2 got=$3
  if [ "$want" = "$got" ]; then
    skell_ok "$label"
  else
    skell_not_ok "$label"
    printf '       want %s\n' "$(skell_dump "$want")" >&2
    printf '       got  %s\n' "$(skell_dump "$got")" >&2
  fi
}

skell_true() {
  local label=$1; shift
  if "$@"; then skell_ok "$label"; else skell_not_ok "$label"; fi
}

skell_false() {
  local label=$1; shift
  if "$@"; then skell_not_ok "$label"; else skell_ok "$label"; fi
}

# Callers pass one encoded record without its newline.
skell_assert_record() {
  local label=$1 record=$2 fields bytes
  fields=$(printf '%s' "$record" | gawk -F'\t' -e '{print NF} END {if (NR == 0) print 0}')
  skell_eq "$label: five fields" 5 "$fields"
  case $record in
    *$'\n'*) skell_not_ok "$label: one line" ;;
    *) skell_ok "$label: one line" ;;
  esac
  bytes=$(printf '%s' "$record" | wc -c)
  if [ "$bytes" -le 1000 ]; then
    skell_ok "$label: within 1000 bytes"
  else
    skell_not_ok "$label: within 1000 bytes (got $bytes)"
  fi
}

# An encoded field must not end on an odd run of backslashes: the final escape
# would have no character to introduce.
skell_assert_no_dangling() {
  local label=$1 field=$2 run
  run=$(printf '%s' "$field" | gawk -e '{n=0; for (i=length($0); i>=1; i--) { if (substr($0,i,1)=="\\") n++; else break } print n%2} END {if (NR==0) print 0}')
  skell_eq "$label: no dangling escape" 0 "$run"
}

# Assert every codec suite's shared fitter boundaries against the files a probe
# wrote. $1 names the shell for the short-record expectation, $2 the output
# directory.
skell_assert_fit_outputs() {
  local shell=$1 dir=$2 fitted field pad
  skell_eq "short record is preserved" \
    "1787700487	/d	0	$shell	git status" "$(skell_slurp "$dir/fit-short")"

  fitted=$(skell_slurp "$dir/fit-longdir")
  skell_assert_record "oversized directory" "$fitted"
  skell_eq "oversized directory reads unknown" unknown \
    "$(printf '%s' "$fitted" | gawk -F'\t' -e '{print $2}')"
  # Dropping the directory leaves room for the whole command, so the record
  # carries no elision marker.
  skell_eq "oversized directory keeps the command whole" 'git status' \
    "$(printf '%s' "$fitted" | gawk -F'\t' -e '{print $5}')"

  # Each offset lands the cut on a different side of the final escape pair.
  for pad in 0 1 2 3; do
    fitted=$(skell_slurp "$dir/fit-cut-$pad")
    skell_assert_record "cut at offset $pad" "$fitted"
    field=$(printf '%s' "$fitted" | gawk -F'\t' -e '{print $5}')
    skell_assert_no_dangling "cut at offset $pad" "${field%'\+'}"
  done

  skell_assert_record "non-ASCII record" "$(skell_slurp "$dir/fit-wide")"
}

skell_report() {
  printf '%s: %d passed, %d failed\n' "$skell_name" "$skell_pass" "$skell_fail"
  [ "$skell_fail" -eq 0 ]
}
