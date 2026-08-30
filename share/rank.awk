# Rank skell's store by frecency and emit one line per distinct command.
#
# Candidate fields: id, last epoch, run count, last exit, visible directory,
# visible command. Raw fields use the same layout in the file passed as
# -v raw=<path>. Lines are printed best first; on tied match scores, skim's
# index tiebreak falls back to that order.
#
# PowerShell decodes native stdout before redirecting it and would re-encode
# non-ASCII commands. Pass -v out=<path> and -v raw=<path> for direct output.
# Load share/codec.awk first.

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
  # Rejoin extra fields from a hand-edited store that contains literal tabs.
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
  raw_target = (raw == "") ? "/dev/null" : raw
  PROCINFO["sorted_in"] = "by_score"
  for (cmd in score) {
    id++
    printf("%d\t%d\t%d\t%s\t%s\t%s\n",
           id, last[cmd], count[cmd], code[cmd], dir[cmd], cmd) > raw_target
    printf("%d\t%d\t%d\t%s\t%s\t%s\n",
           id, last[cmd], count[cmd], skell_visible(code[cmd]),
           skell_visible(skell_unescape(dir[cmd])),
           skell_visible(skell_unescape(cmd))) > target
  }
}
