#!/usr/bin/env bash
# zsh loads hooks only in interactive shells and cannot inherit this bash's
# environment. Pipe the probe into `zsh -f -i` after a prelude sets MSYS2 paths.
# File reads and arguments can change bytes across the runtime boundary.
# Rebuild vectors from their %XX specs.
# shellcheck source=tests/lib/harness.sh disable=SC2016
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

out="$SKELL_SANDBOX/out"
mkdir -p "$out"

{
  # The inherited PATH resolves coreutils and /tmp through Git for Windows.
  # Prepend MSYS2 tools.
  printf 'export PATH=/usr/bin:/bin:$PATH\n'
  printf 'export SKELL_ROOT=%s\n' "$SKELL_REPO_WIN"
  printf 'export SKELL_DATA_DIR=%s/data\n' "$SKELL_SANDBOX_MSYS"
  printf 'export SKELL_HISTORY=%s/data/history.tsv\n' "$SKELL_SANDBOX_MSYS"
  printf 'export SKELL_OUT_DIR=%s/out\n' "$SKELL_SANDBOX_MSYS"
  printf 'export SKELL_VECTORS_TSV=%s/tests/lib/vectors.tsv\n' "$SKELL_REPO_WIN"
  printf 'source %s/tests/lib/probe-zsh.zsh\n' "$SKELL_REPO_WIN"
  printf 'exit 0\n'
} > "$SKELL_SANDBOX/prelude.zsh"

printf 'source %s/prelude.zsh\n' "$SKELL_SANDBOX_MSYS" \
  | zsh -f -i >"$SKELL_SANDBOX/probe.log" 2>&1

if [ ! -f "$out/COMPLETE" ]; then
  cat -- "$SKELL_SANDBOX/probe.log" >&2
  skell_not_ok 'zsh probe ran to completion'
  skell_report
  exit 1
fi
skell_ok 'zsh probe ran to completion'

while read -r name; do
  [ -n "$name" ] || continue
  skell_eq_file "escape $name"   "$SKELL_VECTORS/$name.enc" "$out/$name.enc.out"
  skell_eq_file "unescape $name" "$SKELL_VECTORS/$name.raw" "$out/$name.dec.out"
done < "$SKELL_VECTORS/INDEX"

skell_assert_fit_outputs zsh "$out"
skell_report
