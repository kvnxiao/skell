# Store codec for previews and atuin imports.
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

function skell_visible(s,   out, i, c) {
  out = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    out = out ((c in skell_control) ? sprintf("<0x%02X>", skell_control[c]) : c)
  }
  return out
}

# Records use a 1000-byte budget. Because each UTF-8 code point may use four
# bytes, records with code points above U+007F use a 250-character limit
# without another counting pass. Control bytes use one UTF-8 byte and stay on
# the full budget.
#
# gawk and fish count code points, while bash, zsh, and PowerShell count UTF-16
# units. Both stay within the budget, but they may trim an astral command at
# different positions.
function skell_limit(record) {
  return (record ~ /[^\000-\177]/) ? 250 : 1000
}

# If a cut leaves an odd run of backslashes, drop the incomplete escape.
function skell_trim_dangling(s,   run, i) {
  run = 0
  for (i = length(s); i >= 1 && substr(s, i, 1) == "\\"; i--) run++
  return (run % 2) ? substr(s, 1, length(s) - 1) : s
}

# If a directory leaves no room for the command, replace it with "unknown" to
# keep all five fields within the byte budget.
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
    # If replacing the directory makes the whole command fit, return the
    # record without an elision marker.
    if (length(record) <= limit) return record
    keep = limit - length(head) - 3
    if (keep < 0) keep = 0
  }
  cmd = skell_trim_dangling(substr(cmd, 1, keep))
  return head "\t" cmd "\\+"
}
