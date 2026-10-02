#!/usr/bin/env bash
# shellcheck source=tests/lib/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

codec="$SKELL_REPO_ROOT/share/codec.awk"

out="$SKELL_SANDBOX/out"
mkdir -p "$out"

# Command substitution would strip a trailing newline. Write results to files.
while read -r name; do
  [ -n "$name" ] || continue
  gawk -v BINMODE=3 -f "$codec" -v RS='\0' \
    -e '{printf("%s", skell_unescape($0))}' < "$SKELL_VECTORS/$name.enc" > "$out/$name.dec.out"
  skell_eq_file "unescape $name" "$SKELL_VECTORS/$name.raw" "$out/$name.dec.out"
done < "$SKELL_VECTORS/INDEX"

skell_report
