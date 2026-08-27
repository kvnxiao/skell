# Render one completion candidate for skim's preview pane. The records file is
# named on the command line; -v n=<id> picks the row whose first field is id.
#
# skim substitutes its placeholders raw and on Windows runs the preview through
# cmd.exe, so only the numeric id crosses that boundary.

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
    print $4
    exit
  }
  q = shquote($2)
  cmd = "if command -v lsd >/dev/null 2>&1; then lsd -1 --color=always -- " q \
        "; else ls -1 -- " q "; fi 2>&1"
  while ((cmd | getline line) > 0) print line
  close(cmd)
  exit
}
