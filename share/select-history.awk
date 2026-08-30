BEGIN { FS = "\t" }

n != "" && $1 == n {
  cmd = $6
  for (f = 7; f <= NF; f++) cmd = cmd FS $f
  printf("%s", cmd)
  found = 1
  exit
}

END { if (n != "" && !found) exit 1 }
