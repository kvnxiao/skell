#!/usr/bin/env bash
# shellcheck source=tests/lib/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

store=$SKELL_SANDBOX/render-store.tsv
rank=$SKELL_SANDBOX/render-rank.tsv
raw=$SKELL_SANDBOX/render-rank.raw.tsv
selected=$SKELL_SANDBOX/render-selected
expected=$SKELL_SANDBOX/render-expected
preview=$SKELL_SANDBOX/render-preview
completion=$SKELL_SANDBOX/render-completion.tsv
completion_candidates=$SKELL_SANDBOX/render-completion-candidates.tsv
completion_preview=$SKELL_SANDBOX/render-completion-preview

escape=$'\033'
bell=$'\a'
# U+009D as UTF-8 bytes; bash 3.2 has no \u escape.
c1_osc=$'\302\235'
command="printf x${escape}]0;command${bell}${c1_osc}c1"
directory="/d${escape}]0;directory${bell}"
status="7${escape}]0;status${bell}"
printf '1787700487\t%s\t%s\tbash\t%s\n' "$directory" "$status" "$command" > "$store"

gawk -f "$SKELL_ROOT/share/codec.awk" -f "$SKELL_ROOT/share/rank.awk" \
  -v "out=$rank" -v "raw=$raw" "$store"

skell_true 'history candidates render command controls visibly' \
  gawk -v needle='<0x1B>]0;command<0x07>' -f "$SKELL_ROOT/tests/lib/contains.awk" "$rank"
skell_true 'history candidates render C1 controls visibly' \
  gawk -v needle='<0x9D>c1' -f "$SKELL_ROOT/tests/lib/contains.awk" "$rank"
skell_true 'history candidates render directory controls visibly' \
  gawk -v needle='<0x1B>]0;directory<0x07>' -f "$SKELL_ROOT/tests/lib/contains.awk" "$rank"
skell_true 'history candidates render status controls visibly' \
  gawk -v needle='<0x1B>]0;status<0x07>' -f "$SKELL_ROOT/tests/lib/contains.awk" "$rank"
skell_true 'history candidates contain no terminal control bytes' \
  gawk -f "$SKELL_ROOT/tests/lib/reject-terminal-controls.awk" "$rank"

printf '%s' "$command" > "$expected"
gawk -f "$SKELL_ROOT/share/select-history.awk" -v n=1 "$raw" > "$selected"
skell_eq_file 'history selection preserves exact command bytes' "$expected" "$selected"
skell_true 'history selector accepts an omitted selection' \
  gawk -f "$SKELL_ROOT/share/select-history.awk" "$raw"
skell_false 'history selector rejects an unknown selection' \
  gawk -f "$SKELL_ROOT/share/select-history.awk" -v n=2 "$raw"

gawk -f "$SKELL_ROOT/share/codec.awk" -f "$SKELL_ROOT/share/preview-history.awk" \
  -v n=1 "$raw" > "$preview"
skell_true 'history preview renders untrusted controls visibly' \
  gawk -v needle='<0x1B>]0;command<0x07>' -f "$SKELL_ROOT/tests/lib/contains.awk" "$preview"
skell_false 'history preview excludes OSC sequences from history' \
  gawk -v needle="${escape}]" -f "$SKELL_ROOT/tests/lib/contains.awk" "$preview"
skell_false 'history preview excludes bells from history' \
  gawk -v needle="$bell" -f "$SKELL_ROOT/tests/lib/contains.awk" "$preview"

printf '1\t\tgroup%s]0;group%s\tdescription%s]0;description%s\n' \
  "$escape" "$bell" "$escape" "$bell" > "$completion"
gawk -f "$SKELL_ROOT/share/codec.awk" \
  -f "$SKELL_ROOT/share/completion-candidates.awk" "$completion" > "$completion_candidates"
skell_true 'completion candidates render untrusted controls visibly' \
  gawk -v needle='<0x1B>]0;description<0x07>' \
    -f "$SKELL_ROOT/tests/lib/contains.awk" "$completion_candidates"
skell_false 'completion candidates exclude OSC sequences from descriptions' \
  gawk -v needle="${escape}]" -f "$SKELL_ROOT/tests/lib/contains.awk" "$completion_candidates"
skell_false 'completion candidates exclude bells from descriptions' \
  gawk -v needle="$bell" -f "$SKELL_ROOT/tests/lib/contains.awk" "$completion_candidates"

gawk -f "$SKELL_ROOT/share/codec.awk" -f "$SKELL_ROOT/share/preview-complete.awk" \
  -v n=1 "$completion" > "$completion_preview"
skell_true 'completion preview renders untrusted controls visibly' \
  gawk -v needle='<0x1B>]0;description<0x07>' \
    -f "$SKELL_ROOT/tests/lib/contains.awk" "$completion_preview"
skell_false 'completion preview excludes OSC sequences from descriptions' \
  gawk -v needle="${escape}]" -f "$SKELL_ROOT/tests/lib/contains.awk" "$completion_preview"
skell_false 'completion preview excludes bells from descriptions' \
  gawk -v needle="$bell" -f "$SKELL_ROOT/tests/lib/contains.awk" "$completion_preview"

listing=$SKELL_SANDBOX/render-listing.tsv
stubs=$SKELL_SANDBOX/stubs
gawk_bin=$(command -v gawk)
printf "1\t/d'x\td'x/\t\n" > "$listing"
for tool in eza lsd ls; do
  mkdir -p "$stubs/$tool"
  cat > "$stubs/$tool/$tool" <<'EOF'
#!/bin/sh
printf %s "${0##*/}"; printf ' %s' "$@"; echo
EOF
  chmod +x "$stubs/$tool/$tool"
done

listing_preview() {
  local lister=$1 path='' tool
  shift
  for tool; do path=${path:+$path:}$stubs/$tool; done
  if [ -n "$lister" ]; then
    set -- SKELL_COMPLETE_LS="$lister"
  else
    set -- -u SKELL_COMPLETE_LS
  fi
  env "$@" LC_ALL=C PATH="$path" "$gawk_bin" -f "$SKELL_ROOT/share/codec.awk" \
    -f "$SKELL_ROOT/share/preview-complete.awk" -v n=1 "$listing"
}

skell_eq 'directory preview defaults to eza' \
  "eza -1 --color=never --no-quotes -- /d'x" "$(listing_preview '' eza lsd ls)"
skell_eq 'directory preview uses eza when selected' \
  "eza -1 --color=never --no-quotes -- /d'x" "$(listing_preview eza eza lsd ls)"
skell_eq 'directory preview uses lsd when selected' \
  "lsd -1 --color=never -- /d'x" "$(listing_preview lsd eza lsd ls)"
skell_eq 'directory preview falls back to lsd without eza' \
  "lsd -1 --color=never -- /d'x" "$(listing_preview '' lsd ls)"
skell_eq 'directory preview falls back to ls without eza or lsd' \
  "ls -1 -- /d'x" "$(listing_preview '' ls)"
skell_eq 'directory preview uses ls when selected' \
  "ls -1 -- /d'x" "$(listing_preview ls eza lsd ls)"

skell_no_fallback() {
  local label="directory preview does not replace a missing $1"
  case $2 in
    *' -1 '*) skell_not_ok "$label"; printf '       got  %s\n' "$(skell_dump "$2")" >&2 ;;
    *"$1"*'not found'*) skell_ok "$label" ;;
    *) skell_not_ok "$label"; printf '       got  %s\n' "$(skell_dump "$2")" >&2 ;;
  esac
}
skell_no_fallback eza "$(listing_preview eza lsd ls)"
skell_no_fallback lsd "$(listing_preview lsd eza ls)"

skell_eq 'directory preview rejects an unknown lister' \
  'skell: SKELL_COMPLETE_LS must be eza, lsd, or ls, not exa' \
  "$(listing_preview exa eza lsd ls)"

skell_report
