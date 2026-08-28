#!/usr/bin/env bash
# MSYS2 fish cannot redirect to a `C:/...` store path. A generated prelude sets
# the fixture paths in MSYS2 form before the probe runs. The probe skips when
# MSYS2 is unavailable.
# shellcheck source=tests/lib/harness.sh disable=SC2016
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

out="$SKELL_SANDBOX/out"
mkdir -p "$out"

{
  # The inherited PATH makes coreutils operate on Git-for-Windows' `/tmp`.
  # Prepend `/usr/bin:/bin` to use MSYS2 tools.
  printf 'set -gx PATH /usr/bin /bin $PATH\n'
  printf 'set -p fish_function_path %s/fish/functions\n' "$SKELL_REPO_WIN"
  printf 'set -gx SKELL_OUT_DIR %s/out\n' "$SKELL_SANDBOX_MSYS"
  printf 'set -gx SKELL_SANDBOX_WIN %s\n' "$SKELL_SANDBOX_WIN"
  printf 'set -gx SKELL_SANDBOX_MSYS %s\n' "$SKELL_SANDBOX_MSYS"
  printf 'set -gx SKELL_REPO_WIN %s\n' "$SKELL_REPO_WIN"
  printf 'source %s/tests/lib/probe-path-fish.fish\n' "$SKELL_REPO_WIN"
} > "$SKELL_SANDBOX/probe.fish"

# Because `fish/conf.d/skell.fish` returns in a non-interactive shell, run the
# probe interactively.
printf 'source %s/probe.fish\nexit\n' "$SKELL_SANDBOX_MSYS" |
  fish --no-config -i >"$SKELL_SANDBOX/probe.log" 2>&1

state=$(cat -- "$out/COMPLETE" 2>/dev/null)
if [ "$state" = 'skip' ]; then
  printf '%s: skipped (no MSYS2 runtime)\n' "$skell_name"
  exit 0
fi
if [ "$state" != 'done' ]; then
  cat -- "$SKELL_SANDBOX/probe.log" >&2
  skell_not_ok 'fish probe ran to completion'
  skell_report
  exit 1
fi
skell_ok 'fish probe ran to completion'

slash=$(cat -- "$out/from-slash")
skell_eq 'a Windows path rewrites to the sandbox' "$SKELL_SANDBOX/data" "$slash"
skell_eq 'a backslash path rewrites the same way' "$slash" \
  "$(cat -- "$out/from-backslash")"
skell_eq 'an MSYS2 path is preserved' "$SKELL_SANDBOX_MSYS/data" \
  "$(cat -- "$out/from-posix")"

# If Z:, Y:, X:, and W: are mounted, the test has no unmounted drive to compare.
if [ -f "$out/unmounted" ]; then
  skell_eq 'an unmounted drive letter is preserved' \
    "$(cat -- "$out/unmounted-want")" "$(cat -- "$out/unmounted")"
fi

skell_eq 'the hook rewrites the data directory' yes \
  "$(cat -- "$out/data-rewritten" 2>/dev/null)"
skell_eq 'the hook rewrites the store path' yes \
  "$(cat -- "$out/history-rewritten" 2>/dev/null)"
skell_eq 'the rewritten store accepts a record' 0 "$(cat -- "$out/store-append")"
skell_eq 'the store lands in the sandbox' yes \
  "$(cat -- "$out/store-landed" 2>/dev/null)"

skell_report
