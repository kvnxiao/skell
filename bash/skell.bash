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

# The store holds every command the user runs. Creating the directory and the
# file here under a private umask keeps the first append from creating the store
# at the caller's.
if [ ! -d "$SKELL_DATA_DIR" ]; then
  (umask 077; mkdir -p "$SKELL_DATA_DIR") || return 0
fi
[ -e "$SKELL_HISTORY" ] || (umask 077; : > "$SKELL_HISTORY")

# `ignoredups` leaves HISTCMD unchanged on a repeated command, which
# _skell_record reads as "nothing new ran"; frecency counts those repeats.
# HISTCONTROL is the user's, so ignorespace joins whatever is already set
# rather than replacing it, and HISTIGNORE is left alone.
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

# Concurrent appenders interleave without tearing up to 1024 bytes on NTFS
# through the Cygwin and MSYS2 runtimes, which is where skell is tested. A
# record holding any non-ASCII code point is capped at a quarter of the budget,
# since four bytes is the widest UTF-8 encoding and a byte count would need a
# second pass. ${#var} counts UTF-16 units under Cygwin's 16-bit wchar_t, as
# zsh and PowerShell do, while gawk and fish count code points; either count
# stays inside 1000 bytes, so a command outside the BMP is cut at a different
# point depending on which shell recorded it.
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
    # Dropping the directory can be enough on its own, and a record that now
    # fits is whole: marking it elided would claim a cut that never happened.
    if [ ${#record} -le $limit ]; then
      _skell_reply=$record
      return 0
    fi
    keep=$(( limit - ${#head} - 3 ))
    [ $keep -lt 0 ] && keep=0
  fi
  cmd=${cmd:0:keep}
  # An even run of trailing backslashes is whole escape pairs; an odd run means
  # the cut landed inside one, so the last backslash goes.
  local run=0 i=${#cmd}
  # shellcheck disable=SC1003  # the pattern is one literal backslash
  while [ "$i" -gt 0 ] && [ "${cmd:i-1:1}" = '\' ]; do run=$((run + 1)); i=$((i - 1)); done
  [ $((run % 2)) -eq 1 ] && cmd=${cmd%?}
  _skell_reply="$head"$'\t'"$cmd"'\+'
}

# HISTCMD advances only when a command enters the history list, so an empty
# line, a command the user's HISTCONTROL or HISTIGNORE excluded, and a shell
# whose HISTFILE was empty all leave it unchanged. `history 1` on its own would
# replay the previous command for each of those.
# A command substitution around `history 1` costs a Cygwin fork on every
# prompt, so the builtin writes to a scratch file and stays in this shell.
# starship reads $? from whatever PROMPT_COMMAND entry ran before it, so every
# exit path returns the status the user's command ended on.
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
  # A multiline command is one history entry spanning several output lines, so
  # the read has to reach EOF. -d '' returns non-zero there and still assigns.
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
  # A directory holding a tab or a newline would shift every field that follows
  # it, so it is escaped on the same terms as the command.
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

# The encoded backslash pair is consumed before any other escape is decoded, so
# a byte the store holds literally can never be read as an escape introducer. A
# decoder that swapped in a placeholder byte would rewrite that byte when it
# restored the backslashes.
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

  # A `bind -x` handler cannot submit the line, so the terminal is asked for a
  # status report and its reply is bound to accept-line. A terminal that does
  # not answer DSR leaves the line for Enter.
  if [ "$key" = run ]; then
    bind '"\e[0n": accept-line' 2>/dev/null
    printf '\e[5n'
  fi
}

bind -m emacs-standard -x '"\C-r": _skell_history_widget' 2>/dev/null
bind -m vi-insert -x '"\C-r": _skell_history_widget' 2>/dev/null
