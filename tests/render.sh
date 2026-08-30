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
c1_osc=$'\u009d'
command="printf x${escape}]0;command${bell}${c1_osc}c1"
directory="/d${escape}]0;directory${bell}"
status="7${escape}]0;status${bell}"
printf '1787700487\t%s\t%s\tbash\t%s\n' "$directory" "$status" "$command" > "$store"

gawk -f "$SKELL_ROOT/share/codec.awk" -f "$SKELL_ROOT/share/rank.awk" \
  -v "out=$rank" -v "raw=$raw" "$store"

skell_true 'history candidates render command controls visibly' \
  gawk -v needle='<0x1B>]0;command<0x07>' 'index($0, needle) { found=1 } END { exit !found }' "$rank"
skell_true 'history candidates render C1 controls visibly' \
  gawk -v needle='<0x9D>c1' 'index($0, needle) { found=1 } END { exit !found }' "$rank"
skell_true 'history candidates render directory controls visibly' \
  gawk -v needle='<0x1B>]0;directory<0x07>' 'index($0, needle) { found=1 } END { exit !found }' "$rank"
skell_true 'history candidates render status controls visibly' \
  gawk -v needle='<0x1B>]0;status<0x07>' 'index($0, needle) { found=1 } END { exit !found }' "$rank"
skell_true 'history candidates contain no terminal control bytes' \
  gawk '
    BEGIN {
      for (i = 1; i < 32; i++) if (i != 9) unsafe[sprintf("%c", i)] = 1
      for (i = 127; i < 160; i++) unsafe[sprintf("%c", i)] = 1
    }
    {
      for (i = 1; i <= length($0); i++) if (substr($0, i, 1) in unsafe) bad = 1
    }
    END { exit bad }
  ' "$rank"

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
  gawk -v needle='<0x1B>]0;command<0x07>' 'index($0, needle) { found=1 } END { exit !found }' "$preview"
skell_false 'history preview excludes OSC sequences from history' \
  gawk -v osc="${escape}]" 'index($0, osc) { found=1 } END { exit !found }' "$preview"
skell_false 'history preview excludes bells from history' \
  gawk -v bell="$bell" 'index($0, bell) { found=1 } END { exit !found }' "$preview"

printf '1\t\tgroup%s]0;group%s\tdescription%s]0;description%s\n' \
  "$escape" "$bell" "$escape" "$bell" > "$completion"
gawk -f "$SKELL_ROOT/share/codec.awk" \
  -f "$SKELL_ROOT/share/completion-candidates.awk" "$completion" > "$completion_candidates"
skell_true 'completion candidates render untrusted controls visibly' \
  gawk -v needle='<0x1B>]0;description<0x07>' \
    'index($0, needle) { found=1 } END { exit !found }' "$completion_candidates"
skell_false 'completion candidates exclude OSC sequences from descriptions' \
  gawk -v osc="${escape}]" 'index($0, osc) { found=1 } END { exit !found }' "$completion_candidates"
skell_false 'completion candidates exclude bells from descriptions' \
  gawk -v bell="$bell" 'index($0, bell) { found=1 } END { exit !found }' "$completion_candidates"

gawk -f "$SKELL_ROOT/share/codec.awk" -f "$SKELL_ROOT/share/preview-complete.awk" \
  -v n=1 "$completion" > "$completion_preview"
skell_true 'completion preview renders untrusted controls visibly' \
  gawk -v needle='<0x1B>]0;description<0x07>' \
    'index($0, needle) { found=1 } END { exit !found }' "$completion_preview"
skell_false 'completion preview excludes OSC sequences from descriptions' \
  gawk -v osc="${escape}]" 'index($0, osc) { found=1 } END { exit !found }' "$completion_preview"
skell_false 'completion preview excludes bells from descriptions' \
  gawk -v bell="$bell" 'index($0, bell) { found=1 } END { exit !found }' "$completion_preview"

skell_report
