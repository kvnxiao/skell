#!/usr/bin/env bash
# Expand tests/lib/vectors.tsv under $1. Each .raw file contains line-editor
# input, and its .enc file contains the required store encoding.
set -euo pipefail

out=${1:?usage: vectors.sh DIR}
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
rm -rf -- "$out"
mkdir -p "$out"

# Use the C locale to make gawk's %c emit one byte for each hex escape.
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
