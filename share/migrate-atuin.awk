# Convert `atuin history list --print0 -f '{time}\t{directory}\t{exit}\t{command}'`
# into skell records. Load share/codec.awk first and run with -v RS='\0'.

BEGIN { FS = "\t" }

NF < 4 { malformed++; next }

{
  stamp = $1; dir = $2; code = $3; cmd = $4
  # A command holding a literal tab is split across the trailing fields.
  for (f = 5; f <= NF; f++) cmd = cmd FS $f

  # Normalize ISO separators before mktime(), which accepts six
  # space-separated fields. Offset timestamps are parsed as UTC and adjusted
  # to preserve their absolute time.
  utc = 0
  offset = 0
  if (match(stamp, /([+-])([0-9][0-9]):?([0-9][0-9])$/, zone)) {
    offset = (zone[1] == "-" ? -1 : 1) * (zone[2] * 3600 + zone[3] * 60)
    stamp = substr(stamp, 1, RSTART - 1)
    utc = 1
  } else if (stamp ~ /[Zz]$/) {
    sub(/[Zz]$/, "", stamp)
    utc = 1
  }
  sub(/[[:space:]]+$/, "", stamp)
  sub(/[Tt]/, " ", stamp)
  sub(/\.[0-9]+$/, "", stamp)
  gsub(/[-:]/, " ", stamp)
  epoch = utc ? mktime(stamp, 1) - offset : mktime(stamp)
  if (epoch < 0) { skipped++; next }

  # Normalize Windows drive paths to the MSYS2 form used by shell writers.
  if (dir ~ /^[A-Za-z]:\//) {
    dir = "/" tolower(substr(dir, 1, 1)) substr(dir, 3)
  }

  # Use -1 for an invalid exit status; previews display -1 as unknown.
  if (code !~ /^-?[0-9]+$/) code = "-1"

  print skell_fit(epoch, skell_escape(dir), code, "atuin", skell_escape(cmd))
  written++
}

# Reject malformed fields or timestamps before the migration publishes a
# partial store.
END {
  printf("migrate-atuin: converted %d records, skipped %d, malformed %d\n",
         written, skipped, malformed) > "/dev/stderr"
  if (malformed > 0) {
    printf("migrate-atuin: malformed records do not contain all four export fields\n") > "/dev/stderr"
    exit 1
  }
  if (skipped > 0) {
    printf("migrate-atuin: %d timestamps did not parse\n", skipped) > "/dev/stderr"
    exit 1
  }
}
