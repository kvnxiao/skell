# Convert `atuin history list --print0 -f '{time}\t{directory}\t{exit}\t{command}'`
# into skell records. Load share/codec.awk first and run with -v RS='\0'.

BEGIN { FS = "\t" }

NF < 4 { next }

{
  stamp = $1; dir = $2; code = $3; cmd = $4
  # A command holding a literal tab is split across the trailing fields.
  for (f = 5; f <= NF; f++) cmd = cmd FS $f

  # Normalize ISO separators and remove UTC offsets before mktime(), which
  # accepts six space-separated local-time fields.
  sub(/[Tt]/, " ", stamp)
  sub(/[+-][0-9][0-9]:?[0-9][0-9]$/, "", stamp)
  gsub(/[-:]/, " ", stamp)
  epoch = mktime(stamp)
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

# If every timestamp fails to parse, reject the conversion instead of
# publishing an empty store.
END {
  printf("migrate-atuin: converted %d records, skipped %d\n", written, skipped) > "/dev/stderr"
  if (written == 0 && skipped > 0) {
    printf("migrate-atuin: every record was skipped; atuin's {time} format did not parse\n") > "/dev/stderr"
    exit 1
  }
}
