#!/usr/bin/env bash
# Expand tests/lib/vectors.tsv into file pairs under $1: <name>.raw holds the
# bytes a line editor passes the recording hook, <name>.enc holds the field
# every writer must produce from those bytes.
set -euo pipefail

out=${1:?usage: vectors.sh DIR}
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
rm -rf -- "$out"
mkdir -p "$out"

# gawk's %c emits a character in the current locale, so the C locale turns a
# hex escape into the single byte the vector names.
LC_ALL=C gawk -v out="$out" '
function unhex(s,   r, i, c, n) {
  r = ""
  n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "%") {
      r = r sprintf("%c", strtonum("0x" substr(s, i + 1, 2)))
      i += 2
    } else r = r c
  }
  return r
}
BEGIN { FS = "\t" }
/^#/ || NF < 3 { next }
{
  printf("%s", unhex($2)) > (out "/" $1 ".raw")
  printf("%s", unhex($3)) > (out "/" $1 ".enc")
  print $1 >> (out "/INDEX")
}
' "$here/vectors.tsv"
