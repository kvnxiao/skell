#!/usr/bin/env bash
# Export atuin's history into skell's store.

set -euo pipefail

usage() {
  cat <<'EOF'
Export atuin's history into skell's store.

Usage: migrate-atuin.sh [--append] [--dry-run] [--force] [--output PATH]

  --append     Add to an existing store instead of requiring a new one.
  --dry-run    Convert and validate without touching the target.
  --force      Skip the prompt that asks for other shells to be closed.
  --output     Write somewhere other than $SKELL_HISTORY.

Records are written oldest first, matching the order the shells append in.
The target is replaced only after validation. If conversion fails, the target
stays byte for byte unchanged. A concurrent append would be lost. Close shells
that record to the store before running the migration.
EOF
}

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
output=${SKELL_HISTORY:-${XDG_DATA_HOME:-$HOME/.local/share}/skell/history.tsv}
append=0
dry_run=0
force=0

while [ $# -gt 0 ]; do
  case $1 in
    --append) append=1 ;;
    --dry-run) dry_run=1 ;;
    --force) force=1 ;;
    --output)
      if [ $# -lt 2 ]; then
        echo 'migrate-atuin: --output needs a path' >&2
        exit 2
      fi
      shift
      output=$1
      ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'migrate-atuin: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

command -v atuin >/dev/null 2>&1 || {
  echo 'migrate-atuin: atuin is not on PATH' >&2
  exit 1
}
command -v gawk >/dev/null 2>&1 || {
  echo 'migrate-atuin: gawk is required for mktime()' >&2
  exit 1
}

if [ "$dry_run" -eq 0 ] && [ "$append" -eq 0 ] && [ -e "$output" ]; then
  printf 'migrate-atuin: %s already exists; pass --append to add to it\n' "$output" >&2
  exit 1
fi

if [ "$dry_run" -eq 0 ] && [ "$force" -eq 0 ]; then
  printf 'migrate-atuin: close the shells that record to %s first.\n' "$output" >&2
  printf 'This replaces the file; an append from another shell would be lost.\n' >&2
  printf 'Continue? [y/N] ' >&2
  read -r reply </dev/tty || reply=
  case $reply in
    [yY]|[yY][eE][sS]) ;;
    *) echo 'migrate-atuin: cancelled' >&2; exit 1 ;;
  esac
fi

# atuin's workspace setting can filter history to the current Git repository.
# Force a global export. NUL separators keep multiline commands in one
# record, and --reverse=true fixes oldest-first order. atuin and mktime() use
# the local time zone. BINMODE=3 preserves CRLF in commands.
convert() {
  ATUIN_FILTER_MODE=global \
    atuin history list --reverse=true --print0 \
    -f '{time}\t{directory}\t{exit}\t{command}' \
    | gawk -v BINMODE=3 -v RS='\0' -f "$here/codec.awk" -f "$here/migrate-atuin.awk"
}

# Outside a UTF-8 locale, gawk may cut a record inside a multibyte character.
# The structure check cannot detect invalid UTF-8.
case ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} in
  *[Uu][Tt][Ff]8* | *[Uu][Tt][Ff]-8*) ;;
  *)
    printf 'migrate-atuin: locale is not UTF-8; a long non-ASCII command may be cut mid-character\n' >&2
    ;;
esac

# Validate the five-field format and 1000-byte record budget. LC_ALL=C makes
# gawk count bytes instead of characters.
validate_structure() {
  LC_ALL=C gawk -v BINMODE=3 -F'\t' -e '
    NF != 5 { printf("migrate-atuin: line %d holds %d fields\n", NR, NF) > "/dev/stderr"; bad = 1 }
    length($0) > 1000 { printf("migrate-atuin: line %d is %d bytes\n", NR, length($0)) > "/dev/stderr"; bad = 1 }
    $1 !~ /^[0-9]+$/ { printf("migrate-atuin: line %d has a non-numeric epoch\n", NR) > "/dev/stderr"; bad = 1 }
    END { if (bad) exit 1 }
  ' "$1"
}

# Validate oldest-first order only in converted records. When appending,
# imported history may predate the existing store.
validate_order() {
  gawk -v BINMODE=3 -F'\t' -e '
    $1 < last { printf("migrate-atuin: converted line %d goes back in time\n", NR) > "/dev/stderr"; bad = 1 }
    { last = $1 }
    END { if (bad) exit 1 }
  ' "$1"
}

if [ "$dry_run" -eq 1 ]; then
  scratch=$(mktemp) || exit 1
  trap 'rm -f -- "$scratch"' EXIT
  convert > "$scratch"
  validate_order "$scratch"
  validate_structure "$scratch"
  printf 'migrate-atuin: %s records would be written\n' "$(wc -l < "$scratch")"
  exit 0
fi

mkdir -p "$(dirname "$output")"

# Create temporary files beside the store to publish the result with one
# filesystem rename.
converted=$(mktemp -- "$output.XXXXXX") || exit 1
staged=
trap 'rm -f -- "$converted" ${staged:+"$staged"}' EXIT
staged=$(mktemp -- "$output.XXXXXX") || exit 1
chmod 600 "$converted" "$staged"

convert > "$converted"
validate_order "$converted"

# Build append mode in the staged file and publish it with one rename.
if [ "$append" -eq 1 ] && [ -e "$output" ]; then
  cat -- "$output" > "$staged"
  # If the store lacks a final newline, add one before the imported records.
  if [ -s "$staged" ] && [ "$(tail -c 1 -- "$staged" | wc -l)" -eq 0 ]; then
    printf '\n' >> "$staged"
  fi
fi

cat -- "$converted" >> "$staged"
validate_structure "$staged"

# Preserve permissions the user set on an existing store.
if [ -e "$output" ]; then
  chmod --reference="$output" -- "$staged" 2>/dev/null || true
fi
mv -f -- "$staged" "$output"
rm -f -- "$converted"
trap - EXIT
printf 'migrate-atuin: store now holds %s records\n' "$(wc -l < "$output")"
