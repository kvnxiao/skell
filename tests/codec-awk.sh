#!/usr/bin/env bash
# shellcheck source=tests/lib/harness.sh disable=SC2016
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

codec="$SKELL_REPO_ROOT/share/codec.awk"

out="$SKELL_SANDBOX/out"
mkdir -p "$out"

# Command substitution would strip a trailing newline. Write results to files.
while read -r name; do
  [ -n "$name" ] || continue
  gawk -v BINMODE=3 -f "$codec" -v RS='\0' \
    -e '{printf("%s", skell_escape($0))}' < "$SKELL_VECTORS/$name.raw" > "$out/$name.enc.out"
  gawk -v BINMODE=3 -f "$codec" -v RS='\0' \
    -e '{printf("%s", skell_unescape($0))}' < "$SKELL_VECTORS/$name.enc" > "$out/$name.dec.out"
  skell_eq_file "escape $name"   "$SKELL_VECTORS/$name.enc" "$out/$name.enc.out"
  skell_eq_file "unescape $name" "$SKELL_VECTORS/$name.raw" "$out/$name.dec.out"
done < "$SKELL_VECTORS/INDEX"

fit() {
  gawk -f "$codec" -v d="$1" -v c="$2" -e \
    'BEGIN { printf("%s", skell_fit("1787700487", d, "0", "awk", c)) }'
}

for pad in 0 1 2 3; do
  fit /d "$(printf 'x%.0s' $(seq 1 $((980 + pad))))$(printf '\%.0s' $(seq 1 8))" > "$out/fit-cut-$pad"
done
fit /d 'git status' > "$out/fit-short"
fit "/$(printf 'd%.0s' $(seq 1 1200))" 'git status' > "$out/fit-longdir"
fit /d "$(printf '世%.0s' $(seq 1 400))" > "$out/fit-wide"
skell_assert_fit_outputs awk "$out"
skell_report
