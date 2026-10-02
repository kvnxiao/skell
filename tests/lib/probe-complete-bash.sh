# shellcheck shell=bash disable=SC2016,SC2034,SC2088,SC2154
# Run under `bash -i` with SKELL_OUT_DIR set and the working directory at a
# fixture with d1/, conf/, f1, fa1, fa2, conf.toml, conf.yaml, "sp ace.txt", and
# the executable ccomp. Write each result to a file for bytewise comparison.

. "$SKELL_ROOT/bash/skell.bash"
PROMPT_COMMAND=

probe() {
  local name=$1
  shift
  _skell_reply=
  "$@"
  printf '%s' "$_skell_reply" > "$SKELL_OUT_DIR/$name.out"
}

# Call the finish step as readline's macro would after a capture.
finish() {
  local name=$1 line=$2 point=$3 cur=$4 word=$5 files=$6 nospace=$7
  shift 7
  _skell_tab_line=$line
  _skell_tab_point=$point
  _skell_cap_words=("$@")
  _skell_cap_cur=$cur
  _skell_cap_word=$word
  _skell_cap_files=$files
  _skell_cap_quote=$files
  _skell_cap_nospace=$nospace
  _skell_cap_sort=1
  _skell_cap_done=1
  _skell_tab_finish
  printf '%s|%s' "$READLINE_LINE" "$READLINE_POINT" > "$SKELL_OUT_DIR/$name.out"
}

probe quote-plain _skell_quote 'a b' ''
probe quote-specials _skell_quote 'x$y&z(1)' ''
probe quote-tilde _skell_quote '~/a b' ''
probe quote-double _skell_quote 'a"$b`c' '"'
probe quote-single _skell_quote "it's" "'"
probe quote-var-dir _skell_quote '$V/my dir' ''
probe quote-var-file _skell_quote 'a$b' ''
probe quote-tilde-double _skell_quote '~/a b' '"'

probe open-double _skell_open_quote '"ab'
probe open-closed _skell_open_quote '"a b"'
probe open-single _skell_open_quote "'it"
probe open-escaped _skell_open_quote 'a\"b'

finish finish-file 'ls f1' 5 f1 f1 1 0 f1
finish finish-dir 'ls d' 4 d d 1 0 d1
finish finish-prefix 'ls f' 4 f f 1 0 fa1 fa2
finish finish-dedupe 'ls f' 4 f f 1 0 f1 f1
finish finish-nospace 'ls --col' 8 --col --col 0 1 --color=
finish finish-word 'git che' 7 che che 0 0 checkout
finish finish-quoted 'ls "sp' 6 sp '"sp' 1 0 'sp ace.txt'
finish finish-quoted-dir 'ls "d' 5 d '"d' 1 0 d1
finish finish-escaped 'ls sp' 5 sp sp 1 0 'sp ace.txt'
finish finish-mid-word 'ls fx' 4 f fx 1 0 f1
finish finish-before-space 'ls f bar' 4 f f 1 0 f1
finish finish-empty-cur 'ls ' 3 '' '' 1 0 f1
finish finish-prefix-dir 'ls co' 5 co co 1 0 conf conf.toml conf.yaml
V=$PWD
finish finish-var-dir 'ls $V/d' 7 '$V/d' '$V/d' 1 0 '$V/d1'
finish finish-open-noquote 'echo "$MYP' 10 '$MYP' '"$MYP' 0 0 '$MYPDIR'
finish finish-empty-open 'ls "' 4 '' '"' 1 0 'a$b'
finish finish-escaped-prefix 'ls sp\ a' 8 'sp\ a' 'sp\ a' 1 0 'sp ace.txt' 'sp ace dir'

# Call the wrapped compspec as readline's macro would and record the capture.
capture() {
  local name=$1 line=$2
  shift 2
  COMP_LINE=$line COMP_POINT=${#line} COMP_KEY=126 COMP_TYPE=9
  COMP_WORDS=("$@")
  COMP_CWORD=$(( $# - 1 ))
  _skell_tab_active=1
  _skell_cap_done=0
  _skell_cw "$1" "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD-1]}" 2>/dev/null
  _skell_tab_active=0
  printf '%s|%s|%s' "${_skell_cap_words[*]}" "$_skell_cap_word" "$_skell_cap_done" \
    > "$SKELL_OUT_DIR/$name.out"
}

probe_func() {
  probe_func_seen=${#COMPREPLY[@]}
  COMPREPLY=(w2 x2)
}

complete -o nospace -W 'a b' -X '!a' zz
complete -o default -F probe_func yy
complete -F probe_func -W 'w1 x1' -X '!w*' -P p- yx
complete -C "$PWD/ccomp" tf
_skell_wrap_specs
complete -p zz > "$SKELL_OUT_DIR/wrap-words.out"
printf '%s|%s' "${_skell_cw_gen[zz]}" "${_skell_cw_filter[zz]}" > "$SKELL_OUT_DIR/wrap-words-gen.out"
complete -p yy > "$SKELL_OUT_DIR/wrap-func.out"
printf '%s' "${_skell_cw_func[yy]}" > "$SKELL_OUT_DIR/wrap-func-name.out"

capture capture-filter 'zz ' zz ''
capture capture-func-filter 'yx ' yx ''
printf '%s' "$probe_func_seen" > "$SKELL_OUT_DIR/capture-func-empty.out"
capture capture-command 'tf al' tf al
shopt -s progcomp_alias
alias mg=yy
capture capture-alias 'mg ' mg ''
COMP_KEY=90
_skell_tab_active=1
_skell_cap_done=0
_skell_cw yy '' yy
_skell_tab_active=0
printf '%s|%s' "${COMPREPLY[*]}" "$_skell_cap_done" > "$SKELL_OUT_DIR/capture-other-key.out"

. "$SKELL_ROOT/bash/completion.bash"
printf '%s' "${_skell_cw_func[yy]-unset}" > "$SKELL_OUT_DIR/resource-keeps-wrap.out"

printf 'done' > "$SKELL_OUT_DIR/COMPLETE"
