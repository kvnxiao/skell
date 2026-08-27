# skell's store codec, shared by the preview renderers and the atuin importer.
# Load it ahead of the script that calls it: gawk -f codec.awk -f caller.awk
#
# skell_unescape splits on the encoded backslash pair before decoding anything
# else, so a byte the store holds literally can never be mistaken for an escape
# introducer. A decoder that substituted a placeholder byte instead would
# rewrite that byte when it restored the backslashes.

function skell_escape(s) {
  gsub(/\\/, "\\\\", s)
  gsub(/\n/, "\\n", s)
  gsub(/\t/, "\\t", s)
  gsub(/\r/, "\\r", s)
  return s
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

# A record holding a code point above U+007F is capped at a quarter of the
# budget, since four bytes is the widest UTF-8 encoding and a byte count would
# need a second pass in every writer. The test is on the code point, not on
# whether the character is printable: a control byte is one byte in UTF-8 and
# must not lower the budget, or this writer would cut where no shell does.
#
# gawk and fish count code points, while bash, zsh, and PowerShell count UTF-16
# units. Either count stays inside 1000 bytes, so a command outside the BMP is
# cut at a different point depending on which writer recorded it.
function skell_limit(record) {
  return (record ~ /[^\000-\177]/) ? 250 : 1000
}

# An even run is whole encoded backslashes; an odd run means the cut landed
# inside an escape pair.
function skell_trim_dangling(s,   run, i) {
  run = 0
  for (i = length(s); i >= 1 && substr(s, i, 1) == "\\"; i--) run++
  return (run % 2) ? substr(s, 1, length(s) - 1) : s
}

# Fit an encoded record from its four leading fields and its encoded command.
# A directory that leaves no room for a command is replaced by "unknown" to
# keep the record parseable rather than over budget.
function skell_fit(stamp, dir, code, shell, cmd,   head, limit, keep, record) {
  head = stamp "\t" dir "\t" code "\t" shell
  record = head "\t" cmd
  limit = skell_limit(record)
  if (length(record) <= limit) return record

  keep = limit - length(head) - 3
  if (keep < 1) {
    head = stamp "\tunknown\t" code "\t" shell
    record = head "\t" cmd
    limit = skell_limit(record)
    # Dropping the directory can be enough on its own, and a record that now
    # fits is whole: marking it elided would claim a cut that never happened.
    if (length(record) <= limit) return record
    keep = limit - length(head) - 3
    if (keep < 0) keep = 0
  }
  cmd = skell_trim_dangling(substr(cmd, 1, keep))
  return head "\t" cmd "\\+"
}
