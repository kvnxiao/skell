BEGIN {
  for (i = 1; i < 32; i++) if (i != 9) unsafe[sprintf("%c", i)] = 1
  for (i = 127; i < 160; i++) unsafe[sprintf("%c", i)] = 1
}

{
  for (i = 1; i <= length($0); i++) {
    if (substr($0, i, 1) in unsafe) exit 1
  }
}
