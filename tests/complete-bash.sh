#!/usr/bin/env bash
# bash loads the completion menu only in interactive shells. Run the probe under
# `bash -i`; it calls the menu's helpers without a line editor.
# shellcheck source=tests/lib/harness.sh disable=SC2016,SC2088
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

out="$SKELL_SANDBOX/out"
fixture="$SKELL_SANDBOX/fixture"
mkdir -p "$out" "$fixture/d1" "$fixture/conf"
: > "$fixture/f1"
: > "$fixture/conf.toml"
: > "$fixture/conf.yaml"
printf '%s\n' '#!/bin/sh' 'for w in alpha alpine beta; do' \
  '  case $w in "${COMP_LINE##* }"*) [ "$2" = "${COMP_LINE##* }" ] && echo "$w" ;; esac' \
  'done' > "$fixture/ccomp"
chmod +x "$fixture/ccomp"
: > "$fixture/fa1"
: > "$fixture/fa2"
: > "$fixture/sp ace.txt"

(cd "$fixture" && SKELL_OUT_DIR="$out" HISTFILE="$SKELL_SANDBOX/histfile" \
  bash --noprofile --norc -i "$SKELL_TEST_ROOT/lib/probe-complete-bash.sh") \
  >"$SKELL_SANDBOX/probe.log" 2>&1

if [ ! -f "$out/COMPLETE" ]; then
  cat -- "$SKELL_SANDBOX/probe.log" >&2
  skell_not_ok 'bash completion probe ran to completion'
  skell_report
  exit 1
fi
skell_ok 'bash completion probe ran to completion'

expect() {
  printf '%s' "$2" > "$out/$1.want"
  skell_eq_file "$1" "$out/$1.want" "$out/$1.out"
}

expect quote-plain 'a\ b'
expect quote-specials 'x\$y\&z\(1\)'
expect quote-tilde '~/a\ b'
expect quote-double '"a\"\$b\`c'
expect quote-single "'it'\\''s"
expect quote-var-dir '$V/my\ dir'
expect quote-var-file 'a\$b'
expect quote-tilde-double "\"$HOME/a b"

expect open-double '"'
expect open-closed ''
expect open-single "'"
expect open-escaped ''

expect finish-file 'ls f1 |6'
expect finish-dir 'ls d1/|6'
expect finish-prefix 'ls fa|5'
expect finish-dedupe 'ls f1 |6'
expect finish-nospace 'ls --color=|11'
expect finish-word 'git checkout |13'
expect finish-quoted 'ls "sp ace.txt" |16'
expect finish-quoted-dir 'ls "d1/|7'
expect finish-escaped 'ls sp\ ace.txt |15'
expect finish-mid-word 'ls f1 x|6'
expect finish-before-space 'ls f1 bar|5'
expect finish-empty-cur 'ls f1 |6'
expect finish-prefix-dir 'ls conf|7'
expect finish-var-dir 'ls $V/d1/|9'
expect finish-open-noquote 'echo "$MYPDIR" |15'
expect finish-empty-open 'ls "a\$b" |10'
expect finish-escaped-prefix 'ls sp\ ace|10'

expect wrap-words $'complete -o nospace -F _skell_cw zz\n'
expect wrap-words-gen ' -W a\ b|!a'
expect wrap-func $'complete -o default -F _skell_cw yy\n'
expect wrap-func-name 'probe_func'

expect capture-filter 'a||1'
expect capture-func-filter 'p-w1 p-w2||1'
expect capture-func-empty '0'
expect capture-command 'alpha alpine|al|1'
expect capture-alias 'w2 x2||1'
expect capture-other-key 'w2 x2|0'
expect resource-keeps-wrap 'probe_func'

skell_report
