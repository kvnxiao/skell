# Store decoder for the awk scripts.
# Load it ahead of the script that calls it: gawk -f codec.awk -f caller.awk
#
# skell_unescape decodes doubled backslashes before other escapes. A placeholder
# byte could collide with literal store content.

BEGIN {
  for (skell_code = 1; skell_code < 32; skell_code++) {
    skell_control[sprintf("%c", skell_code)] = skell_code
  }
  for (skell_code = 127; skell_code < 160; skell_code++) {
    skell_control[sprintf("%c", skell_code)] = skell_code
  }
}

function skell_unescape(s,   parts, n, i, seg, out) {
  n = split(s, parts, /\\\\/)
  out = ""
  for (i = 1; i <= n; i++) {
    seg = parts[i]
    gsub(/\\n/, "\n", seg)
    gsub(/\\t/, "\t", seg)
    gsub(/\\r/, "\r", seg)
    gsub(/\\\+/, " […]", seg)
    out = out (i > 1 ? "\\" : "") seg
  }
  return out
}

function skell_visible(s,   out, i, c) {
  out = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    out = out ((c in skell_control) ? sprintf("<0x%02X>", skell_control[c]) : c)
  }
  return out
}
