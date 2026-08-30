# Render one ranked record for skim. Pass its first field as -v n=<id>, and
# load share/codec.awk first.
#
# On Windows, skim sends raw placeholder text through cmd.exe. Only the numeric
# ID crosses that boundary; all other values come from the rank file.

function ago(seconds) {
  if (seconds < 60) return "just now"
  if (seconds < 3600) return int(seconds / 60) " min ago"
  if (seconds < 86400) return int(seconds / 3600) " h ago"
  if (seconds < 2592000) return int(seconds / 86400) " d ago"
  return int(seconds / 2592000) " mo ago"
}

BEGIN { FS = "\t"; dim = "\033[2m"; accent = "\033[36m"; bad = "\033[31m"; off = "\033[0m" }

$1 != n { next }

{
  cmd = $6
  for (f = 7; f <= NF; f++) cmd = cmd FS $f

  safe_code = skell_visible($4)
  status = ($4 == "-1") ? dim "exit unknown" off : \
           (($4 == "0") ? dim "exit " off "0" : bad "exit " safe_code off)
  printf("%s%s%s  %s·%s  %s  %s·%s  %s\n", accent, strftime("%Y-%m-%d %H:%M", $2), off,
         dim, off, ago(systime() - $2), dim, off, status)
  printf("%sruns%s %d   %sin%s %s\n\n", dim, off, $3, dim, off,
         skell_visible(skell_unescape($5)))
  print skell_visible(skell_unescape(cmd))
  exit
}
