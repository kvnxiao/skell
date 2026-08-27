# skell -- one command history for bash, fish, powershell, and zsh.
# https://github.com/kvnxiao/skell

[[ -o interactive ]] || return 0

: ${SKELL_ROOT:=${0:A:h:h}}
: ${SKELL_DATA_DIR:=${XDG_DATA_HOME:-$HOME/.local/share}/skell}
: ${SKELL_HISTORY:=$SKELL_DATA_DIR/history.tsv}
export SKELL_ROOT SKELL_DATA_DIR SKELL_HISTORY

# The store holds every command the user runs. Creating the directory and the
# file here under a private umask keeps the first append from creating the store
# at the caller's.
if [[ ! -d $SKELL_DATA_DIR ]]; then
  (umask 077; mkdir -p $SKELL_DATA_DIR) || return 0
fi
[[ -e $SKELL_HISTORY ]] || (umask 077; : > $SKELL_HISTORY)

zmodload zsh/datetime
autoload -Uz add-zsh-hook

# Each zsh history option stands on its own, so this one leaves the user's
# other exclusions in place. _skell_precmd checks the leading space again, so
# unsetting the option later cannot put the command in the store.
setopt HIST_IGNORE_SPACE

_skell_rank=$SKELL_DATA_DIR/rank-zsh-$$.tsv
_skell_complete_rec=$SKELL_DATA_DIR/complete-zsh-$$.tsv

_skell_exit() { command rm -f -- $_skell_rank $_skell_complete_rec }
add-zsh-hook zshexit _skell_exit

_skell_escape() {
  local s=${1//\\/\\\\}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  REPLY=${s//$'\r'/\\r}
}

# Concurrent appenders interleave without tearing up to 1024 bytes on NTFS
# through the Cygwin and MSYS2 runtimes, which is where skell is tested. A
# record holding any non-ASCII code point is capped at a quarter of the budget,
# since four bytes is the widest UTF-8 encoding and a byte count would need a
# second pass. ${#var} counts UTF-16 units under Cygwin's 16-bit wchar_t, as
# bash and PowerShell do, while gawk and fish count code points; either count
# stays inside 1000 bytes, so a command outside the BMP is cut at a different
# point depending on which shell recorded it.
_skell_fit() {
  local head=$1 cmd=$2 record
  local -i limit=1000
  record="$head"$'\t'"$cmd"
  [[ $record == *[^[:ascii:]]* ]] && limit=250
  if (( ${#record} <= limit )); then
    REPLY=$record
    return 0
  fi

  local -i keep=$(( limit - ${#head} - 3 ))
  if (( keep < 1 )); then
    head="${head%%$'\t'*}"$'\tunknown\t'"${head#*$'\t'*$'\t'}"
    record="$head"$'\t'"$cmd"
    limit=1000
    [[ $record == *[^[:ascii:]]* ]] && limit=250
    # Dropping the directory can be enough on its own, and a record that now
    # fits is whole: marking it elided would claim a cut that never happened.
    if (( ${#record} <= limit )); then
      REPLY=$record
      return 0
    fi
    keep=$(( limit - ${#head} - 3 ))
    (( keep < 0 )) && keep=0
  fi
  cmd=${cmd[1,keep]}
  # An even run of trailing backslashes is whole escape pairs; an odd run means
  # the cut landed inside one, so the last backslash goes.
  local -i run=0 i=${#cmd}
  while (( i > 0 )) && [[ ${cmd[i]} == '\' ]]; do (( run++, i-- )); done
  (( run % 2 )) && cmd=${cmd[1,-2]}
  REPLY="$head"$'\t'"$cmd"'\+'
}

# preexec's first argument is the line as typed; the second and third are
# normalized and lose the leading space that excludes a command.
_skell_preexec() { _skell_pending=$1 }

_skell_precmd() {
  local -i code=$?
  # The user's options reach this hook: SH_WORD_SPLIT would split the command
  # across the arguments below and NO_UNSET would abort on _skell_pending, so
  # the hook runs under zsh's own defaults.
  emulate -L zsh
  [[ -n ${_skell_pending-} ]] || return 0
  local raw=$_skell_pending
  unset _skell_pending
  [[ $raw == ' '* ]] && return 0

  local REPLY cmd dir
  _skell_escape "$raw"
  cmd=$REPLY
  # A directory holding a tab or a newline would shift every field that follows
  # it, so it is escaped on the same terms as the command.
  _skell_escape "$PWD"
  dir=$REPLY

  _skell_fit "$EPOCHSECONDS"$'\t'"$dir"$'\t'"$code"$'\t'zsh "$cmd"
  print -r -- "$REPLY" >> $SKELL_HISTORY
}

add-zsh-hook preexec _skell_preexec
add-zsh-hook precmd _skell_precmd

# The encoded backslash pair is consumed before any other escape is decoded, so
# a byte the store holds literally can never be read as an escape introducer. A
# decoder that swapped in a placeholder byte would rewrite that byte when it
# restored the backslashes.
_skell_unescape() {
  local s=$1 out= raw dec
  while :; do
    raw=${s%%'\\'*}
    dec=${raw//'\n'/$'\n'}
    dec=${dec//'\t'/$'\t'}
    dec=${dec//'\r'/$'\r'}
    dec=${dec//'\+'/ […]}
    out+=$dec
    [[ $raw == $s ]] && break
    out+='\'
    s=${s[${#raw}+3,-1]}
  done
  REPLY=$out
}

_skell_history_widget() {
  if [[ ! -s $SKELL_HISTORY ]]; then
    zle reset-prompt
    return 0
  fi
  (umask 077; : > $_skell_rank)
  gawk -f $SKELL_ROOT/share/rank.awk $SKELL_HISTORY > $_skell_rank || return 0
  [[ -s $_skell_rank ]] || return 0

  local REPLY
  local -a chosen
  chosen=("${(@f)$(sk \
    --height 60% --min-height 15 --layout=reverse --border rounded \
    --prompt 'history ❯ ' --info inline --ansi \
    --delimiter $'\t' --with-nth '6..' \
    --tiebreak score,index \
    --query "$BUFFER" \
    --preview "gawk -f \"$SKELL_ROOT/share/codec.awk\" -f \"$SKELL_ROOT/share/preview-history.awk\" -v n={1} \"$_skell_rank\"" \
    --preview-window 'right:55%:wrap' \
    --bind 'enter:accept(edit),alt-enter:accept(run)' < $_skell_rank)}")

  if (( ${#chosen} < 2 )); then
    zle reset-prompt
    return 0
  fi

  # The `p` flag expands \t in the separator to a tab. Fields past the sixth
  # are rejoined: a hand-edited store can hold a literal tab there.
  _skell_unescape "${(pj:\t:)${(@ps:\t:)chosen[2]}[6,-1]}"
  BUFFER=$REPLY
  CURSOR=${#BUFFER}
  if [[ ${chosen[1]} == run ]]; then
    zle accept-line
  else
    zle reset-prompt
  fi
}

zle -N _skell_history_widget
bindkey '^R' _skell_history_widget

# The completion menu binds Tab, so it must load after compinit and before any
# widget-wrapping plugin.
source $SKELL_ROOT/zsh/completion.zsh
