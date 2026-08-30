# skell -- one command history for bash, fish, powershell, and zsh.
# https://github.com/kvnxiao/skell

[[ -o interactive ]] || return 0

: ${SKELL_ROOT:=${0:A:h:h}}
: ${SKELL_DATA_DIR:=${XDG_DATA_HOME:-$HOME/.local/share}/skell}
: ${SKELL_HISTORY:=$SKELL_DATA_DIR/history.tsv}
export SKELL_ROOT SKELL_DATA_DIR SKELL_HISTORY

# The store contains the user's command history. Create new data directories
# and stores under a private umask.
if [[ ! -d $SKELL_DATA_DIR ]]; then
  (umask 077; mkdir -p $SKELL_DATA_DIR) || return 0
fi
[[ -e $SKELL_HISTORY ]] || (umask 077; : >> $SKELL_HISTORY)

zmodload zsh/datetime
autoload -Uz add-zsh-hook

# Add HIST_IGNORE_SPACE without changing other history options. _skell_precmd
# also checks the raw line in case the option changes later.
setopt HIST_IGNORE_SPACE

_skell_rank=$SKELL_DATA_DIR/rank-zsh-$$.tsv
_skell_rank_raw=$SKELL_DATA_DIR/rank-zsh-$$.raw.tsv
_skell_complete_rec=$SKELL_DATA_DIR/complete-zsh-$$.tsv
_skell_complete_candidates=$SKELL_DATA_DIR/complete-zsh-$$.candidates.tsv

_skell_exit() {
  command rm -f -- $_skell_rank $_skell_rank_raw \
    $_skell_complete_rec $_skell_complete_candidates
}
add-zsh-hook zshexit _skell_exit

_skell_escape() {
  local s=${1//\\/\\\\}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  REPLY=${s//$'\r'/\\r}
}

# On NTFS, the tested Cygwin and MSYS2 runtimes append up to 1024 bytes without
# interleaving. Records use a 1000-byte budget. Because each UTF-8 code point
# may use four bytes, records with non-ASCII text use a 250-character limit
# without another counting pass. Cygwin zsh counts UTF-16 units, while gawk
# and fish count code points. Both stay within the budget, but they may trim an
# astral command at different positions.
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
    # If replacing the directory makes the whole command fit, return the
    # record without an elision marker.
    if (( ${#record} <= limit )); then
      REPLY=$record
      return 0
    fi
    keep=$(( limit - ${#head} - 3 ))
    (( keep < 0 )) && keep=0
  fi
  cmd=${cmd[1,keep]}
  # If the cut leaves an odd run of backslashes, drop the incomplete escape.
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
  # User-set SH_WORD_SPLIT would split the command, and NO_UNSET would abort on
  # _skell_pending. Run the hook under zsh defaults.
  emulate -L zsh
  [[ -n ${_skell_pending-} ]] || return 0
  local raw=$_skell_pending
  unset _skell_pending
  [[ $raw == ' '* ]] && return 0

  local REPLY cmd dir
  _skell_escape "$raw"
  cmd=$REPLY
  # Escape tabs and newlines in the directory before writing the TSV fields.
  _skell_escape "$PWD"
  dir=$REPLY

  _skell_fit "$EPOCHSECONDS"$'\t'"$dir"$'\t'"$code"$'\t'zsh "$cmd"
  print -r -- "$REPLY" >> $SKELL_HISTORY
}

add-zsh-hook preexec _skell_preexec
add-zsh-hook precmd _skell_precmd

# Decode doubled backslashes before other escapes. A placeholder byte could
# collide with literal store content.
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
  (umask 077; : > $_skell_rank; : > $_skell_rank_raw)
  if ! gawk -f $SKELL_ROOT/share/codec.awk -f $SKELL_ROOT/share/rank.awk \
    -v out=$_skell_rank -v raw=$_skell_rank_raw $SKELL_HISTORY; then
    command rm -f -- $_skell_rank $_skell_rank_raw
    return 0
  fi
  if [[ ! -s $_skell_rank ]]; then
    command rm -f -- $_skell_rank $_skell_rank_raw
    return 0
  fi

  local REPLY id encoded
  local -a chosen
  chosen=("${(@f)$(sk \
    --height 60% --min-height 15 --layout=reverse --border rounded \
    --prompt 'history ❯ ' --info inline \
    --delimiter $'\t' --with-nth '6..' \
    --tiebreak score,index \
    --query "$BUFFER" \
    --preview "gawk -f \"$SKELL_ROOT/share/codec.awk\" -f \"$SKELL_ROOT/share/preview-history.awk\" -v n={1} \"$_skell_rank_raw\"" \
    --preview-window 'right:55%:wrap' \
    --bind 'enter:accept(edit),alt-enter:accept(run)' < $_skell_rank)}")

  if (( ${#chosen} < 2 )); then
    command rm -f -- $_skell_rank $_skell_rank_raw
    zle reset-prompt
    return 0
  fi

  id=${chosen[2]%%$'\t'*}
  encoded=$(gawk -f $SKELL_ROOT/share/select-history.awk \
    -v n=$id $_skell_rank_raw)
  local -i select_status=$?
  command rm -f -- $_skell_rank $_skell_rank_raw
  (( select_status == 0 )) || return 0
  _skell_unescape "$encoded"
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

# Load the Tab binding after compinit and before widget-wrapping plugins.
source $SKELL_ROOT/zsh/completion.zsh
