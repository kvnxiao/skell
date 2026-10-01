# Render one completion candidate for skim. Pass the records file on the
# command line and use -v n=<id> to select its row.
#
# On Windows, skim sends raw placeholder text through cmd.exe. Only the numeric
# ID crosses that boundary.

function shquote(s,   out, i, c, esc) {
  esc = SQ "\\" SQ SQ
  out = SQ
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    out = out (c == SQ ? esc : c)
  }
  return out SQ
}

BEGIN { FS = "\t"; SQ = "'" }

$1 != n { next }

{
  if ($2 == "") {
    text = $4
    for (f = 5; f <= NF; f++) text = text FS $f
    print skell_visible(text)
    exit
  }
  q = shquote($2)
  args["eza"] = " -1 --color=never --no-quotes -- " q
  args["lsd"] = " -1 --color=never -- " q
  args["ls"] = " -1 -- " q
  lister = ENVIRON["SKELL_COMPLETE_LS"]
  if (lister != "" && !(lister in args)) {
    print skell_visible("skell: SKELL_COMPLETE_LS must be eza, lsd, or ls, not " \
                        lister)
    exit
  }
  if (lister != "") cmd = lister args[lister]
  else cmd = "if command -v eza >/dev/null 2>&1; then eza" args["eza"] \
             "; elif command -v lsd >/dev/null 2>&1; then lsd" args["lsd"] \
             "; else ls" args["ls"] "; fi"
  cmd = cmd " 2>&1"
  while ((cmd | getline line) > 0) print skell_visible(line)
  close(cmd)
  exit
}
