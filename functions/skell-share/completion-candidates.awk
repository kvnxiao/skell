# Load share/codec.awk first. With -v sorted=1, print rows in the order of
# their text instead of input order.

BEGIN { FS = OFS = "\t" }

{
  text = $4
  for (f = 5; f <= NF; f++) text = text FS $f
  group = skell_visible($3)
  if (group != "") group = "\033[2m" group "\033[0m"
  row = $1 OFS "" OFS group OFS skell_visible(text)
  if (!sorted) { print row; next }
  rows[NR] = row
  keys[NR] = text
}

END {
  if (!sorted) exit
  PROCINFO["sorted_in"] = "@val_str_asc"
  for (i in keys) print rows[i]
}
