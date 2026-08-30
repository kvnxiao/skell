# Load share/codec.awk first.

BEGIN { FS = OFS = "\t" }

{
  text = $4
  for (f = 5; f <= NF; f++) text = text FS $f
  group = skell_visible($3)
  if (group != "") group = "\033[2m" group "\033[0m"
  print $1, "", group, skell_visible(text)
}
