#!/usr/bin/env bash
# The probe calls the completion menu's helpers without a line editor. Because
# this bash cannot export its environment to MSYS2 fish, a generated prelude
# sets paths in MSYS2 form.
# shellcheck source=tests/lib/harness.sh disable=SC2016
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

out="$SKELL_SANDBOX/out"
mkdir -p "$out"

{
  printf 'set -gx PATH /usr/bin /bin $PATH\n'
  printf 'set -p fish_function_path %s/fish/functions\n' "$SKELL_REPO_WIN"
  printf 'set -gx SKELL_OUT_DIR %s/out\n' "$SKELL_SANDBOX_MSYS"
  printf 'source %s/tests/lib/probe-complete-fish.fish\n' "$SKELL_REPO_WIN"
} > "$SKELL_SANDBOX/prelude.fish"

fish --no-config "$SKELL_SANDBOX_MSYS/prelude.fish" \
  >"$SKELL_SANDBOX/probe.log" 2>&1

if [ ! -f "$out/COMPLETE" ]; then
  cat -- "$SKELL_SANDBOX/probe.log" >&2
  skell_not_ok 'fish probe ran to completion'
  skell_report
  exit 1
fi
skell_ok 'fish probe ran to completion'

# Compare bytes from files; command substitution would strip trailing newlines.
expect() {
  local name=$1 want=$2
  printf '%s' "$want" > "$out/$name.want"
  skell_eq_file "$name" "$out/$name.want" "$out/$name.out"
  if [ $# -ge 3 ]; then
    skell_eq "$name status" "$3" "$(skell_slurp "$out/$name.status")"
  fi
}

expect prefix-extends 'subdir-' 0
expect prefix-no-progress '' 1
expect prefix-empty-token 'che' 0
expect prefix-case 'Fanc' 0
expect prefix-fuzzy '' 1
expect prefix-dangling '' 1
expect prefix-escaped-backslash "xa\\\\" 0

expect join-file 'file '$'\n'
expect join-dir 'src/'$'\n'
expect join-option-value '--color='$'\n'
expect join-closes-quote '"file a.txt" '$'\n'
expect join-closed-quote '"file a.txt" '$'\n'
expect join-open-dir-quote '"dir one/'$'\n'
expect join-many 'sre.txt src/'$'\n'
expect join-many-quoted '"dir one/" x '$'\n'
expect join-mid-token 'foo'$'\n'
expect join-before-space 'foo'$'\n'
expect join-escaped-quote "it\\'s "$'\n'
expect join-single-quoted "'it\\'s' "$'\n'

expect commandline-plain 'ls fi'
expect commandline-empty ''
expect commandline-newline $'begin\n'
expect commandline-newlines $'a\nb c\n\n'

expect visible-osc $'a<0x1B>]0;t<0x07>\n'
expect visible-c1 $'x<0x9D>y\n'
expect visible-tab $'a<0x09>b\n'
expect visible-plain $'café — x\n\nplain\n'

skell_report
