#!/usr/bin/env bash
# Round-trip every codec vector through fish's own escape and decode, and check
# the fitter's boundaries.
#
# fish autoloads the codec from fish/functions/, so the probe does not need an
# interactive shell; it does need its paths in MSYS2's own spelling, since the
# environment that this bash exports does not reach an MSYS2 fish.
# shellcheck source=tests/lib/harness.sh disable=SC2016
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

out="$SKELL_SANDBOX/out"
mkdir -p "$out"

{
  # An MSYS2 fish that an agent starts inherits the agent's PATH, which resolves
  # coreutils to Git-for-Windows and its own /tmp.
  printf 'set -gx PATH /usr/bin /bin $PATH\n'
  printf 'set -p fish_function_path %s/fish/functions\n' "$SKELL_REPO_WIN"
  printf 'set -gx SKELL_DATA_DIR %s/data\n' "$SKELL_SANDBOX_MSYS"
  printf 'set -gx SKELL_HISTORY %s/data/history.tsv\n' "$SKELL_SANDBOX_MSYS"
  printf 'set -gx SKELL_OUT_DIR %s/out\n' "$SKELL_SANDBOX_MSYS"
  printf 'set -gx SKELL_VECTORS_TSV %s/tests/lib/vectors.tsv\n' "$SKELL_REPO_WIN"
  printf 'source %s/tests/lib/probe-fish.fish\n' "$SKELL_REPO_WIN"
} > "$SKELL_SANDBOX/prelude.fish"

fish --no-config "$SKELL_SANDBOX_MSYS/prelude.fish" \
  >"$SKELL_SANDBOX/probe.log" 2>&1

if [ ! -f "$out/COMPLETE" ]; then
  cat -- "$SKELL_SANDBOX/probe.log" >&2
  skell_not_ok 'fish probe ran to completion'
  skell_report
  exit 1
fi
skell_ok 'fish probe ran to completion'

while read -r name; do
  [ -n "$name" ] || continue
  # The probe keeps the guard bytes on both ends, so the expectations are
  # bracketed to match rather than the results being unguarded inside fish.
  { printf X; cat -- "$SKELL_VECTORS/$name.enc"; printf X; } > "$out/$name.enc.want"
  { printf X; cat -- "$SKELL_VECTORS/$name.raw"; printf X; } > "$out/$name.dec.want"
  skell_eq_file "escape $name"   "$out/$name.enc.want" "$out/$name.enc.out"
  skell_eq_file "unescape $name" "$out/$name.dec.want" "$out/$name.dec.out"
done < "$SKELL_VECTORS/INDEX"

skell_assert_fit_outputs fish "$out"
skell_report
