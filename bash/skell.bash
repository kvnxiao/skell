# skell -- one command history for bash, fish, powershell, and zsh.
# https://github.com/kvnxiao/skell

case $- in
  *i*) ;;
  *) return 0 ;;
esac

if [ -z "${SKELL_ROOT:-}" ]; then
  SKELL_ROOT=${BASH_SOURCE[0]%/*}
  SKELL_ROOT=${SKELL_ROOT%/*}
fi
: "${SKELL_DATA_DIR:=${XDG_DATA_HOME:-$HOME/.local/share}/skell}"
: "${SKELL_HISTORY:=$SKELL_DATA_DIR/history.tsv}"
export SKELL_ROOT SKELL_DATA_DIR SKELL_HISTORY

# The store contains the user's command history. Create new data directories
# and stores under a private umask.
if [ ! -d "$SKELL_DATA_DIR" ]; then
  (umask 077; mkdir -p "$SKELL_DATA_DIR") || return 0
fi
[ -e "$SKELL_HISTORY" ] || (umask 077; : > "$SKELL_HISTORY")

# Preserve the user's HISTCONTROL and HISTIGNORE settings while adding
# ignorespace. With ignoredups, repeated commands do not advance HISTCMD and
# cannot be recorded.
case :${HISTCONTROL-}: in
  *:ignorespace:* | *:ignoreboth:*) ;;
  *) HISTCONTROL=${HISTCONTROL:+$HISTCONTROL:}ignorespace ;;
esac

_skell_scratch="$SKELL_DATA_DIR/scratch-bash-$$.hist"
_skell_rank="$SKELL_DATA_DIR/rank-bash-$$.tsv"
(umask 077; : > "$_skell_scratch")
_skell_histnum=

_skell_cleanup() { command rm -f -- "$_skell_scratch" "$_skell_rank"; }
trap _skell_cleanup EXIT

_skell_escape() {
  local s=${1//\\/\\\\}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  _skell_reply=${s//$'\r'/\\r}
}

# On NTFS, the tested Cygwin and MSYS2 runtimes append up to 1024 bytes without
# interleaving. Records use a 1000-byte budget. Because each UTF-8 code point
# may use four bytes, records with non-ASCII text use a 250-character limit
# without another counting pass. Cygwin bash counts UTF-16 units, while gawk
# and fish count code points. Both stay within the budget, but they may trim an
# astral command at different positions.
_skell_fit() {
  local head=$1 cmd=$2 limit=1000 record
  record="$head"$'\t'"$cmd"
  case $record in
    *[![:ascii:]]*) limit=250 ;;
  esac
  if [ ${#record} -le $limit ]; then
    _skell_reply=$record
    return 0
  fi

  local keep=$(( limit - ${#head} - 3 ))
  if [ $keep -lt 1 ]; then
    head="${head%%$'\t'*}"$'\tunknown\t'"${head#*$'\t'*$'\t'}"
    record="$head"$'\t'"$cmd"
    limit=1000
    case $record in
      *[![:ascii:]]*) limit=250 ;;
    esac
    # If replacing the directory makes the whole command fit, return the
    # record without an elision marker.
    if [ ${#record} -le $limit ]; then
      _skell_reply=$record
      return 0
    fi
    keep=$(( limit - ${#head} - 3 ))
    [ $keep -lt 0 ] && keep=0
  fi
  cmd=${cmd:0:keep}
  # If the cut leaves an odd run of backslashes, drop the incomplete escape.
  local run=0 i=${#cmd}
  # shellcheck disable=SC1003  # the pattern is one literal backslash
  while [ "$i" -gt 0 ] && [ "${cmd:i-1:1}" = '\' ]; do run=$((run + 1)); i=$((i - 1)); done
  [ $((run % 2)) -eq 1 ] && cmd=${cmd%?}
  _skell_reply="$head"$'\t'"$cmd"'\+'
}

# HISTCMD advances only when bash adds a command to its history. If it does not
# change, reading `history 1` would record the previous command again.
# Under Cygwin, command substitution would fork. Write `history 1` to a scratch
# file. Starship reads $? from the previous PROMPT_COMMAND entry.
# Every exit path returns the user's command status.
_skell_record() {
  local code=$?
  [ "$HISTCMD" = "$_skell_histnum" ] && return "$code"
  if [ -z "$_skell_histnum" ]; then
    _skell_histnum=$HISTCMD
    return "$code"
  fi
  _skell_histnum=$HISTCMD

  local HISTTIMEFORMAT whole num cmd dir _skell_reply
  history 1 > "$_skell_scratch" || return "$code"
  # A multiline history entry spans several lines. Read to EOF.
  # `read -d ''` returns non-zero at EOF after assigning the value.
  IFS= read -r -d '' whole < "$_skell_scratch"
  whole=${whole%$'\n'}
  whole=${whole#"${whole%%[![:space:]]*}"}
  num=${whole%%[![:digit:]]*}
  [ -z "$num" ] && return "$code"

  # `history` separates its right-aligned number from the line with two spaces,
  # so a leading space the user typed survives the slice.
  cmd=${whole#"$num"}
  cmd=${cmd:2}
  case $cmd in
    ' '*|'') return "$code" ;;
  esac

  _skell_escape "$cmd"
  cmd=$_skell_reply
  # Escape tabs and newlines in the directory before writing the TSV fields.
  _skell_escape "$PWD"
  dir=$_skell_reply

  _skell_fit "$EPOCHSECONDS"$'\t'"$dir"$'\t'"$code"$'\t'bash "$cmd"
  printf '%s\n' "$_skell_reply" >> "$SKELL_HISTORY"
  return "$code"
}

case ";${PROMPT_COMMAND:-};" in
  *";_skell_record;"*) ;;
  *) PROMPT_COMMAND="_skell_record${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac

# Decode doubled backslashes before other escapes. A placeholder byte could
# collide with literal store content.
_skell_unescape() {
  local s=$1 out='' raw dec
  while :; do
    # shellcheck disable=SC1003  # the pattern is the two-character escape pair
    raw=${s%%'\\'*}
    dec=${raw//'\n'/$'\n'}
    dec=${dec//'\t'/$'\t'}
    dec=${dec//'\r'/$'\r'}
    dec=${dec//'\+'/ […]}
    out+=$dec
    [ "$raw" = "$s" ] && break
    # shellcheck disable=SC1003  # one literal backslash rejoins the segments
    out+='\'
    s=${s:${#raw}+2}
  done
  _skell_reply=$out
}

_skell_history_widget() {
  [ -s "$SKELL_HISTORY" ] || return 0
  (umask 077; : > "$_skell_rank")
  gawk -f "$SKELL_ROOT/share/rank.awk" "$SKELL_HISTORY" > "$_skell_rank" || return 0
  [ -s "$_skell_rank" ] || return 0

  local _skell_reply chosen
  chosen=$(sk \
    --height 60% --min-height 15 --layout=reverse --border rounded \
    --prompt 'history > ' --info inline --ansi \
    --delimiter $'\t' --with-nth '6..' \
    --tiebreak score,index \
    --query "$READLINE_LINE" \
    --preview "gawk -f \"$SKELL_ROOT/share/codec.awk\" -f \"$SKELL_ROOT/share/preview-history.awk\" -v n={1} \"$_skell_rank\"" \
    --preview-window 'right:55%:wrap' \
    --bind 'enter:accept(edit),alt-enter:accept(run)' < "$_skell_rank")
  case $chosen in
    *$'\n'*) ;;
    *) return 0 ;;
  esac

  local key=${chosen%%$'\n'*} record=${chosen#*$'\n'}
  _skell_unescape "${record#*$'\t'*$'\t'*$'\t'*$'\t'*$'\t'}"
  READLINE_LINE=$_skell_reply
  READLINE_POINT=${#READLINE_LINE}

  # A `bind -x` handler cannot submit the line. Bind the terminal's DSR reply to
  # accept-line; terminals without DSR support leave the command for Enter.
  if [ "$key" = run ]; then
    bind '"\e[0n": accept-line' 2>/dev/null
    printf '\e[5n'
  fi
}

bind -m emacs-standard -x '"\C-r": _skell_history_widget' 2>/dev/null
bind -m vi-insert -x '"\C-r": _skell_history_widget' 2>/dev/null
