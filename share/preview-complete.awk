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
  lister = ENVIRON["SKELL_COMPLETE_LS"]
  if (lister == "") lister = "eza"
  if (lister != "eza" && lister != "lsd" && lister != "ls") {
    print skell_visible("skell: SKELL_COMPLETE_LS must be eza, lsd, or ls, not " \
                        lister)
    exit
  }
  q = shquote($2)
  cmd = "ls -1 -- " q
  if (lister != "ls") {
    other = lister == "eza" ? "lsd" : "eza"
    args["eza"] = " -1 --color=never --no-quotes -- " q
    args["lsd"] = " -1 --color=never -- " q
    cmd = "if command -v " lister " >/dev/null 2>&1; then " lister args[lister] \
          "; elif command -v " other " >/dev/null 2>&1; then " other args[other] \
          "; else " cmd "; fi"
  }
  cmd = cmd " 2>&1"
  while ((cmd | getline line) > 0) print skell_visible(line)
  close(cmd)
  exit
}
