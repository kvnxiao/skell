# Convert `atuin history list --print0 -f '{time}\t{directory}\t{exit}\t{command}'`
# into skell records. Load share/codec.awk first and run with -v RS='\0'.

BEGIN { FS = "\t" }

NF < 4 { next }

{
  stamp = $1; dir = $2; code = $3; cmd = $4
  # A command holding a literal tab is split across the trailing fields.
  for (f = 5; f <= NF; f++) cmd = cmd FS $f

  # atuin renders {time} with an ISO separator on some versions and appends a
  # UTC offset on others. mktime() reads neither: it takes six space-separated
  # numbers, and an offset's minutes would land in its DST slot.
  sub(/[Tt]/, " ", stamp)
  sub(/[+-][0-9][0-9]:?[0-9][0-9]$/, "", stamp)
  gsub(/[-:]/, " ", stamp)
  epoch = mktime(stamp)
  if (epoch < 0) { skipped++; next }

  # atuin records the drive-letter form on Windows and the shells record the
  # MSYS2 form; one store cannot hold both spellings.
  if (dir ~ /^[A-Za-z]:\//) {
    dir = "/" tolower(substr(dir, 1, 1)) substr(dir, 3)
  }

  # A non-numeric exit status would shift how a preview reads the field, so
  # anything unparseable is written as the unknown marker.
  if (code !~ /^-?[0-9]+$/) code = "-1"

  print skell_fit(epoch, skell_escape(dir), code, "atuin", skell_escape(cmd))
  written++
}

# A run that converts nothing while skipping records means the timestamps did
# not parse, so it exits non-zero rather than publishing an empty store.
END {
  printf("migrate-atuin: converted %d records, skipped %d\n", written, skipped) > "/dev/stderr"
  if (written == 0 && skipped > 0) {
    printf("migrate-atuin: every record was skipped; atuin's {time} format did not parse\n") > "/dev/stderr"
    exit 1
  }
}
