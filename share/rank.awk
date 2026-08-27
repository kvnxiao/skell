# Rank skell's store by frecency and emit one line per distinct command.
#
# Output fields: id, last epoch, run count, last exit, last directory, command.
# Lines are printed best first; on tied match scores, skim's index tiebreak
# falls back to that order.
#
# Pass -v out=<path> to write the file directly. PowerShell's `>` decodes a
# native command's stdout before writing it, which would re-encode every
# non-ASCII command in the store.

function weight(age) {
  if (age < 3600) return 4
  if (age < 86400) return 2
  if (age < 604800) return 0.5
  return 0.25
}

function by_score(i1, v1, i2, v2) {
  if (v1 != v2) return (v1 > v2) ? -1 : 1
  if (last[i1] != last[i2]) return (last[i1] > last[i2]) ? -1 : 1
  return 0
}

BEGIN { FS = "\t"; now = systime() }

NF < 5 { next }

{
  cmd = $5
  # A recorded command contains no literal tab, but a hand-edited store might.
  for (i = 6; i <= NF; i++) cmd = cmd FS $i
  if (cmd == "") next

  score[cmd] += weight(now - $1)
  count[cmd]++
  if ($1 >= last[cmd]) {
    last[cmd] = $1
    dir[cmd] = $2
    code[cmd] = $3
  }
}

END {
  target = (out == "") ? "/dev/stdout" : out
  PROCINFO["sorted_in"] = "by_score"
  for (cmd in score) {
    id++
    printf("%d\t%d\t%d\t%s\t%s\t%s\n", id, last[cmd], count[cmd], code[cmd], dir[cmd], cmd) > target
  }
}
