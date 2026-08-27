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
The target is replaced only after the whole conversion validates, so a failed
run leaves it byte for byte as it was. Close the shells that record to the
store first: this rewrites the file rather than appending to it, and a
concurrent append would be lost.
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
      # Consuming $1 blindly would report an unbound variable rather than the
      # missing argument.
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

# A `workspaces = true` config narrows `history list` to the git repository that
# the export runs in, so ATUIN_FILTER_MODE=global overrides it; running in a
# fresh repository would otherwise export nothing. --print0 keeps a multiline
# command in one record, and --reverse=true pins the oldest-first order rather
# than inheriting whatever the installed atuin defaults to. atuin prints {time}
# in the local zone and mktime() reads it back in the same zone. BINMODE=3 stops
# gawk from rewriting a CRLF pair in a command as a bare newline.
convert() {
  ATUIN_FILTER_MODE=global \
    atuin history list --reverse=true --print0 \
    -f '{time}\t{directory}\t{exit}\t{command}' \
    | gawk -v BINMODE=3 -v RS='\0' -f "$here/codec.awk" -f "$here/migrate-atuin.awk"
}

# gawk's length() and substr() are byte-based outside a UTF-8 locale, so the
# record cut would land mid-character and write invalid UTF-8 that
# validate_structure cannot see.
case ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} in
  *[Uu][Tt][Ff]8* | *[Uu][Tt][Ff]-8*) ;;
  *)
    printf 'migrate-atuin: locale is not UTF-8; a long non-ASCII command may be cut mid-character\n' >&2
    ;;
esac

# Every record must hold the five contract fields and stay inside the append
# budget, or the store would be unreadable in ways the shells cannot repair.
# LC_ALL=C makes gawk's length() count bytes, which is the budget the atomic
# append actually has; counting characters would pass a 1000-character record
# holding up to 4000 bytes.
validate_structure() {
  LC_ALL=C gawk -v BINMODE=3 -F'\t' -e '
    NF != 5 { printf("migrate-atuin: line %d holds %d fields\n", NR, NF) > "/dev/stderr"; bad = 1 }
    length($0) > 1000 { printf("migrate-atuin: line %d is %d bytes\n", NR, length($0)) > "/dev/stderr"; bad = 1 }
    $1 !~ /^[0-9]+$/ { printf("migrate-atuin: line %d has a non-numeric epoch\n", NR) > "/dev/stderr"; bad = 1 }
    END { if (bad) exit 1 }
  ' "$1"
}

# Validating the conversion alone pins the oldest-first order against a change
# in atuin's own default. An existing store is exempt: importing history that
# predates it is a legitimate reason for the epochs to step backwards at the
# join.
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

# Both temporary files sit beside the target so the replacement is a rename
# within one filesystem rather than a copy that can half-succeed.
converted=$(mktemp -- "$output.XXXXXX") || exit 1
staged=
trap 'rm -f -- "$converted" ${staged:+"$staged"}' EXIT
staged=$(mktemp -- "$output.XXXXXX") || exit 1
chmod 600 "$converted" "$staged"

convert > "$converted"
validate_order "$converted"

# In append mode the existing records are copied in first, so the rename
# publishes one consistent store rather than a file built up in place.
if [ "$append" -eq 1 ] && [ -e "$output" ]; then
  cat -- "$output" > "$staged"
  # A store whose last line lost its newline would splice into the first
  # imported record.
  if [ -s "$staged" ] && [ "$(tail -c 1 -- "$staged" | wc -l)" -eq 0 ]; then
    printf '\n' >> "$staged"
  fi
fi

cat -- "$converted" >> "$staged"
validate_structure "$staged"

# Where the target already exists, its own permissions win over the temporary
# file's, so an existing store keeps whatever the user set on it.
if [ -e "$output" ]; then
  chmod --reference="$output" -- "$staged" 2>/dev/null || true
fi
mv -f -- "$staged" "$output"
rm -f -- "$converted"
trap - EXIT
printf 'migrate-atuin: store now holds %s records\n' "$(wc -l < "$output")"
