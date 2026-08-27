# Exercise zsh's codec against the vector specs. A generated prelude exports
# SKELL_ROOT, SKELL_VECTORS_TSV and SKELL_OUT_DIR in MSYS2's own spelling and
# sources this file, because the environment an agent's bash sets does not
# reach an MSYS2 zsh.
#
# Each vector is rebuilt here from the %XX spec rather than carried in, because
# neither transport across the runtime boundary is lossless: MSYS2 zsh rewrites
# a CRLF byte pair as a bare newline on every file read, and the MSYS2 runtime
# re-parses backslashes out of a command line that a Git-for-Windows bash built.
# The spec holds nothing above 0x7F, so ${(#)} reconstructs it without needing
# the file's encoding. Nothing on the recording path reads a command from a
# file, so this constrains the harness alone.

source $SKELL_ROOT/zsh/init.zsh

unhex() {
  local spec=$1 out= c
  local -i i=1 n=${#spec} v
  while (( i <= n )); do
    c=$spec[i]
    if [[ $c == '%' ]]; then
      v=$(( 16#$spec[i+1,i+2] ))
      out+=${(#)v}
      (( i += 3 ))
    else
      out+=$c
      (( i++ ))
    fi
  done
  REPLY_SPEC=$out
}

local name rawspec encspec raw enc
while IFS=$'\t' read -r name rawspec encspec; do
  [[ -n $name && $name != '#'* ]] || continue
  unhex $rawspec; raw=$REPLY_SPEC
  unhex $encspec; enc=$REPLY_SPEC

  REPLY=
  _skell_escape "$raw"
  printf '%s' $REPLY > $SKELL_OUT_DIR/$name.enc.out

  REPLY=
  _skell_unescape "$enc"
  printf '%s' $REPLY > $SKELL_OUT_DIR/$name.dec.out
done < $SKELL_VECTORS_TSV

_skell_fit "1787700487"$'\t'"/d"$'\t'"0"$'\t'zsh 'git status'
printf '%s' $REPLY > $SKELL_OUT_DIR/fit-short

_skell_fit "1787700487"$'\t'"/${(l:1200::d:)}"$'\t'"0"$'\t'zsh 'git status'
printf '%s' $REPLY > $SKELL_OUT_DIR/fit-longdir

local -i pad
for pad in 0 1 2 3; do
  _skell_fit "1787700487"$'\t'"/d"$'\t'"0"$'\t'zsh "${(l:$((980 + pad))::x:)}${(l:8::\\:)}"
  printf '%s' $REPLY > $SKELL_OUT_DIR/fit-cut-$pad
done

_skell_fit "1787700487"$'\t'"/d"$'\t'"0"$'\t'zsh "${(l:400::世:)}"
printf '%s' $REPLY > $SKELL_OUT_DIR/fit-wide

printf 'done' > $SKELL_OUT_DIR/COMPLETE
