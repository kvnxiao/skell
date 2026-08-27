#!/usr/bin/env bash
# Round-trip every codec vector through bash's own escape and decode, and check
# the fitter's boundaries. bash reads its recording hook only in an interactive
# shell, so the probe runs under `bash -i`.
# shellcheck source=tests/lib/harness.sh disable=SC2016
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

out="$SKELL_SANDBOX/out"
mkdir -p "$out"

SKELL_VECTORS_DIR="$SKELL_VECTORS" SKELL_OUT_DIR="$out" \
  HISTFILE="$SKELL_SANDBOX/histfile" \
  bash --noprofile --norc -i "$SKELL_TEST_ROOT/lib/probe-bash.sh" \
  >"$SKELL_SANDBOX/probe.log" 2>&1

if [ ! -f "$out/COMPLETE" ]; then
  cat -- "$SKELL_SANDBOX/probe.log" >&2
  skell_not_ok 'bash probe ran to completion'
  skell_report
  exit 1
fi
skell_ok 'bash probe ran to completion'

while read -r name; do
  [ -n "$name" ] || continue
  skell_eq_file "escape $name"   "$SKELL_VECTORS/$name.enc" "$out/$name.enc.out"
  skell_eq_file "unescape $name" "$SKELL_VECTORS/$name.raw" "$out/$name.dec.out"
done < "$SKELL_VECTORS/INDEX"

skell_assert_fit_outputs bash "$out"
skell_report
