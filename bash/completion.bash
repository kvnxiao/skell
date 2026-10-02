# skell -- skim-powered completion menu for bash.
# https://github.com/kvnxiao/skell
#
# Readline gives a key handler no access to its matches. Tab therefore runs a
# macro: _skell_tab_begin saves the line, readline's own `complete` runs the
# command's compspec through _skell_cw, and _skell_tab_finish restores the line
# and offers the recorded matches. Readline still splits the words, finds the
# compspec, and runs the completion function, so the matches equal native Tab's.
# _skell_cw answers readline with the current word unchanged so that the
# `complete` step inserts nothing.
#
# bash/skell.bash sets _skell_scratch and the helpers before sourcing this file.
# shellcheck disable=SC2154

# Re-sourcing keeps the maps; the compspecs already wrapped still point at them.
declare -p _skell_cw_func >/dev/null 2>&1 ||
  declare -gA _skell_cw_func=() _skell_cw_gen=() _skell_cw_cmd=() \
    _skell_cw_filter=() _skell_cw_prefix=() _skell_cw_suffix=()
_skell_specs=
_skell_tab_active=0
_skell_cap_done=0
_skell_complete_rec="$SKELL_DATA_DIR/complete-bash-$$.tsv"
_skell_complete_candidates="$SKELL_DATA_DIR/complete-bash-$$.candidates.tsv"
_skell_empty "$_skell_complete_rec" "$_skell_complete_candidates"

# Replace each compspec with one that runs _skell_cw and records the original
# function and actions. `complete -p` goes through the scratch file because
# command substitution would fork.
_skell_wrap_specs() {
  local all line
  complete -p >| "$_skell_scratch" 2>/dev/null
  IFS= read -r -d '' all < "$_skell_scratch"
  [ "$all" = "$_skell_specs" ] && { : >| "$_skell_scratch"; return 0; }
  while IFS= read -r line; do
    case $line in
      *' -F _skell_cw'*) ;;
      complete\ *) _skell_wrap_spec "$line" ;;
    esac
  done < "$_skell_scratch"
  complete -p >| "$_skell_scratch" 2>/dev/null
  IFS= read -r -d '' _skell_specs < "$_skell_scratch"
  : >| "$_skell_scratch"
}

_skell_wrap_spec() {
  local -a spec opts=() acts=()
  eval "spec=(${1#complete })" 2>/dev/null || return 0
  local func='' cmd='' filter='' prefix='' suffix='' key='' i=0 n=${#spec[@]} q=''
  while [ "$i" -lt "$n" ]; do
    case ${spec[i]} in
      -o) opts+=(-o "${spec[i+1]}"); i=$((i + 2)) ;;
      -F) func=${spec[i+1]}; i=$((i + 2)) ;;
      -C) cmd=${spec[i+1]}; i=$((i + 2)) ;;
      -X) filter=${spec[i+1]}; i=$((i + 2)) ;;
      -P) prefix=${spec[i+1]}; i=$((i + 2)) ;;
      -S) suffix=${spec[i+1]}; i=$((i + 2)) ;;
      -A|-G|-W) acts+=("${spec[i]}" "${spec[i+1]}"); i=$((i + 2)) ;;
      -D|-E|-I) key=${spec[i]}; i=$((i + 1)) ;;
      --) key=${spec[i+1]}; i=$((i + 2)) ;;
      -*) acts+=("${spec[i]}"); i=$((i + 1)) ;;
      *) key=${spec[i]}; i=$((i + 1)) ;;
    esac
  done
  [ -n "$key" ] || return 0
  [ "${#acts[@]}" -gt 0 ] && printf -v q ' %q' "${acts[@]}"
  _skell_cw_func[$key]=$func
  _skell_cw_gen[$key]=$q
  _skell_cw_cmd[$key]=$cmd
  _skell_cw_filter[$key]=$filter
  _skell_cw_prefix[$key]=$prefix
  _skell_cw_suffix[$key]=$suffix
  case $key in
    -D) complete "${opts[@]}" -F _skell_cw_D -D ;;
    -E) complete "${opts[@]}" -F _skell_cw_E -E ;;
    -I) complete "${opts[@]}" -F _skell_cw_I -I ;;
    *) complete "${opts[@]}" -F _skell_cw -- "$key" ;;
  esac
}

# With progcomp_alias, bash passes the alias name and uses the compspec of the
# alias's first word.
_skell_cw() {
  local key=$1
  [ -n "${_skell_cw_func[$key]+x}" ] || key=${1##*/}
  if [ -z "${_skell_cw_func[$key]+x}" ] && [ -n "${BASH_ALIASES[$1]+x}" ]; then
    key=${BASH_ALIASES[$1]%%[[:space:]]*}
    [ -n "${_skell_cw_func[$key]+x}" ] || key=${key##*/}
  fi
  _skell_cw_run "$key" "$@"
}
_skell_cw_D() { _skell_cw_run -D "$@"; }
_skell_cw_E() { _skell_cw_run -E "$@"; }
_skell_cw_I() { _skell_cw_run -I "$@"; }

# Completion functions such as sudo's call the compspec of another command, and
# reach _skell_cw again. Only the outermost call records matches.
# Bash generates a compspec's matches in this order: actions and -W, the -F
# function, the -C command, then the -X filter and the -P and -S affixes. The
# menu's macro runs `complete` from a key sequence ending in `~` (COMP_KEY 126);
# Shift+Tab and other bindings complete natively.
_skell_cw_run() {
  local key=$1 status=0 capture=0 m
  shift
  local func=${_skell_cw_func[$key]-} gen=${_skell_cw_gen[$key]-} cmd=${_skell_cw_cmd[$key]-}
  local filter=${_skell_cw_filter[$key]-} prefix=${_skell_cw_prefix[$key]-} suffix=${_skell_cw_suffix[$key]-}
  if [ "$_skell_tab_active" = 1 ] && [ -z "${_skell_cw_nested-}" ] && [ "${COMP_KEY-}" = 126 ]; then
    capture=1
    # compgen -C and nested completion functions can unset COMP_WORDS.
    _skell_cap_word=''
    if [ "${COMP_CWORD:-0}" -ge 0 ] && [ "${COMP_CWORD:-0}" -lt "${#COMP_WORDS[@]}" ]; then
      _skell_cap_word=${COMP_WORDS[COMP_CWORD]}
    fi
  fi
  local _skell_cw_nested=1
  local -a found=()
  if [ -n "$gen" ]; then
    eval "compgen $gen -- \"\$2\"" >| "$_skell_scratch" 2>/dev/null
    mapfile -t found < "$_skell_scratch"
    : >| "$_skell_scratch"
  fi
  if [ -n "$func" ]; then
    COMPREPLY=()
    "$func" "$@"
    status=$?
    # A lazy loader returns 124 after installing the command's compspec.
    # Wrap the new compspec before readline retries the lookup.
    if [ "$status" -eq 124 ]; then
      _skell_wrap_specs
      return 124
    fi
    found+=("${COMPREPLY[@]}")
  fi
  if [ -n "$cmd" ]; then
    # Bash exports these variables to a -C command and passes it the same
    # three arguments as a -F function.
    COMP_LINE=$COMP_LINE COMP_POINT=$COMP_POINT COMP_KEY=$COMP_KEY COMP_TYPE=$COMP_TYPE \
      eval "$cmd"' "$1" "$2" "$3"' >| "$_skell_scratch" 2>/dev/null
    mapfile -t -O "${#found[@]}" found < "$_skell_scratch"
    : >| "$_skell_scratch"
  fi
  if [ -n "$filter" ]; then
    local -a kept=()
    local negate=0
    case $filter in '!'*) negate=1; filter=${filter:1} ;; esac
    filter=${filter//\\&/$'\1'}
    filter=${filter//&/"$2"}
    filter=${filter//$'\1'/\&}
    for m in "${found[@]}"; do
      # shellcheck disable=SC2053
      if [[ $m == $filter ]]; then
        [ "$negate" = 1 ] && kept+=("$m")
      else
        [ "$negate" = 1 ] || kept+=("$m")
      fi
    done
    found=("${kept[@]}")
  fi
  if [ -n "$prefix$suffix" ]; then
    for m in "${!found[@]}"; do found[m]=$prefix${found[m]}$suffix; done
  fi
  COMPREPLY=("${found[@]}")
  [ "$capture" = 1 ] || return "$status"
  _skell_capture "$2" "$gen"
  COMPREPLY=("$2")
  compopt -o noquote -o nospace +o filenames +o default +o bashdefault \
    +o dirnames +o plusdirs 2>/dev/null
  return 0
}

# Record COMPREPLY and the options that decide how readline inserts it. Run the
# fallbacks that readline applies after a compspec.
_skell_capture() {
  local cur=$1 gen=$2 opts
  builtin compopt >| "$_skell_scratch" 2>/dev/null
  IFS= read -r opts < "$_skell_scratch"
  : >| "$_skell_scratch"
  opts=" $opts "
  local -i files=0
  case $gen in
    *' -f'*|*' -d'*|*' -G '*|*' -A file'*|*' -A directory'*) files=1 ;;
  esac
  case $opts in *' -o filenames '*) files=1 ;; esac
  case $opts in
    *' -o plusdirs '*)
      compgen -d -- "$cur" >| "$_skell_scratch"
      mapfile -t -O "${#COMPREPLY[@]}" COMPREPLY < "$_skell_scratch"
      files=1
      ;;
  esac
  if [ "${#COMPREPLY[@]}" -eq 0 ]; then
    case $opts in
      *' -o dirnames '*) compgen -d -- "$cur" >| "$_skell_scratch"; files=1 ;;
    esac
    [ -s "$_skell_scratch" ] || case $opts in
      *' -o bashdefault '*) compgen -o bashdefault -- "$cur" >| "$_skell_scratch" ;;
    esac
    [ -s "$_skell_scratch" ] || case $opts in
      *' -o default '*) compgen -o default -- "$cur" >| "$_skell_scratch"; files=1 ;;
    esac
    mapfile -t COMPREPLY < "$_skell_scratch"
    : >| "$_skell_scratch"
  fi
  _skell_cap_words=("${COMPREPLY[@]}")
  _skell_cap_cur=$cur
  _skell_cap_files=$files
  _skell_cap_quote=$files
  case $opts in *' -o noquote '*) _skell_cap_quote=0 ;; esac
  _skell_cap_nospace=0
  case $opts in *' -o nospace '*) _skell_cap_nospace=1 ;; esac
  _skell_cap_sort=1
  case $opts in *' -o nosort '*) _skell_cap_sort=0 ;; esac
  _skell_cap_done=1
}

_skell_open_quote() {
  local s=$1 q='' c i
  for (( i = 0; i < ${#s}; i++ )); do
    c=${s:i:1}
    if [ -z "$q" ] && [ "$c" = "\\" ]; then
      i=$((i + 1))
    elif [ -z "$q" ] && { [ "$c" = '"' ] || [ "$c" = "'" ]; }; then
      q=$c
    elif [ "$c" = "$q" ]; then
      q=''
    elif [ "$q" = '"' ] && [ "$c" = "\\" ]; then
      i=$((i + 1))
    fi
  done
  _skell_reply=$q
}

# Quote a match as readline quotes filenames: inside the user's open quote, or
# with backslashes. An unquoted leading tilde stays unquoted so it still
# expands; a quoted one cannot expand, so it becomes $HOME. A directory part
# with a variable keeps its `$` unescaped, as bash does.
_skell_quote() {
  local s=$1 q=$2 c lead='' dollar='$'
  case $s in */*) case ${s%/*} in *'$'*) dollar='' ;; esac ;; esac
  if [ -n "$q" ]; then
    case $s in \~|\~/*) s=$HOME${s:1} ;; esac
  fi
  if [ "$q" = "'" ]; then
    _skell_reply="'${s//\'/\'\\\'\'}"
    return 0
  fi
  if [ "$q" = '"' ]; then
    s=${s//\\/\\\\}
    for c in '"' $dollar '`'; do s=${s//"$c"/\\$c}; done
    _skell_reply="\"$s"
    return 0
  fi
  case $s in '~'*) lead='~'; s=${s:1} ;; esac
  s=${s//\\/\\\\}
  for c in ' ' $'\t' $'\n' '"' "'" '@' '<' '>' '=' ';' '|' '&' '(' ')' '#' $dollar '`' \
    '?' '*' '[' '!' ':' '{' '~'; do
    s=${s//"$c"/\\$c}
  done
  _skell_reply=$lead$s
}

_skell_dir_of() {
  local p=$1 name
  _skell_reply=''
  case $p in
    \~) p=$HOME ;;
    \~/*) p=$HOME/${p:2} ;;
    \~*) return 1 ;;
  esac
  if [[ $p =~ ^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?(/.*)?$ ]]; then
    name=${BASH_REMATCH[1]}
    p=${!name-}${BASH_REMATCH[2]}
  fi
  [ -d "$p" ] || return 1
  _skell_reply=$p
}

# Build the text that replaces the word before the cursor. The last match gets
# the closing quote and trailing space that readline adds to a finished word.
_skell_insertion() {
  local q=$1 finish=$2
  shift 2
  local out='' word last=$#
  local -i i=0
  for word; do
    i+=1
    local dir=0 text=$word
    if [ "$finish" = 1 ] && [ "$_skell_cap_files" = 1 ] && _skell_dir_of "$word"; then
      dir=1
      case $text in */) ;; *) text+=/ ;; esac
    fi
    if [ "$_skell_cap_quote" = 1 ]; then
      _skell_quote "$text" "$q"
      text=$_skell_reply
    else
      text=$q$text
    fi
    if [ "$i" -lt "$last" ]; then
      [ -n "$q" ] && text+=$q
      out+="$text "
      continue
    fi
    if [ "$finish" = 1 ] && [ "$dir" = 0 ]; then
      [ -n "$q" ] && text+=$q
      [ "$_skell_cap_nospace" = 1 ] || text+=' '
    fi
    out+=$text
  done
  _skell_reply=$out
}

_skell_replace() {
  local raw=$1 text=$2
  local before=${READLINE_LINE:0:READLINE_POINT} after=${READLINE_LINE:READLINE_POINT}
  before=${before:0:${#before}-${#raw}}
  case $text in *' ') case $after in ' '*) text=${text% } ;; esac ;; esac
  READLINE_LINE=$before$text$after
  READLINE_POINT=$(( ${#before} + ${#text} ))
}

_skell_tab_begin() {
  _skell_cap_done=0
  if ! _skell_ready; then
    bind -m emacs-standard '"\t": complete'
    bind -m vi-insert '"\t": complete'
    return 0
  fi
  _skell_tab_line=$READLINE_LINE
  _skell_tab_point=$READLINE_POINT
  _skell_wrap_specs
  _skell_tab_active=1
}

_skell_tab_finish() {
  _skell_tab_active=0
  [ "$_skell_cap_done" = 1 ] || return 0
  _skell_cap_done=0
  READLINE_LINE=$_skell_tab_line
  READLINE_POINT=$_skell_tab_point

  local -a words=()
  local -A seen=()
  local w
  # The x prefix keeps a match of `@` or `*` from subscripting the whole map.
  for w in "${_skell_cap_words[@]}"; do
    [ -n "$w" ] && [ -z "${seen[x$w]+x}" ] || continue
    seen[x$w]=1
    words+=("$w")
  done
  [ "${#words[@]}" -gt 0 ] || return 0

  # The raw word is the typed text that readline replaces: the end of the
  # current COMP_WORDS entry that precedes the cursor, with its quotes. With an
  # empty current word, only an opening quote can precede the cursor.
  local raw='' cur=$_skell_cap_cur before=${READLINE_LINE:0:READLINE_POINT} _skell_reply
  local -i k
  if [ -n "$cur" ]; then
    for (( k = ${#_skell_cap_word}; k > 0; k-- )); do
      [[ $before == *"${_skell_cap_word:0:k}" ]] && break
    done
    raw=${_skell_cap_word:0:k}
  else
    case ${_skell_cap_word:0:1} in
      \"|\') [[ $before == *"${_skell_cap_word:0:1}" ]] && raw=${_skell_cap_word:0:1} ;;
    esac
  fi
  _skell_open_quote "$raw"
  local q=$_skell_reply

  # Bash passes the current word with its backslashes; the matches have none.
  if [ -z "$q" ]; then
    local plain=''
    for (( k = 0; k < ${#cur}; k++ )); do
      [ "${cur:k:1}" = "\\" ] && k+=1
      plain+=${cur:k:1}
    done
    cur=$plain
  fi

  if [ "${#words[@]}" -eq 1 ]; then
    _skell_insertion "$q" 1 "${words[0]}"
    _skell_replace "$raw" "$_skell_reply"
    return 0
  fi

  local prefix=${words[0]}
  for w in "${words[@]}"; do
    while [ "${w:0:${#prefix}}" != "$prefix" ]; do prefix=${prefix%?}; done
  done
  if [ "${#prefix}" -gt "${#cur}" ] && [ "${prefix:0:${#cur}}" = "$cur" ]; then
    _skell_insertion "$q" 0 "$prefix"
    _skell_replace "$raw" "$_skell_reply"
    return 0
  fi

  local -a _skell_chosen=() picked=()
  _skell_menu "${words[@]}" || return 0
  local id
  for id in "${_skell_chosen[@]}"; do picked+=("${words[id-1]}"); done
  _skell_insertion "$q" 1 "${picked[@]}"
  _skell_replace "$raw" "$_skell_reply"
}

# Bash has no match descriptions, so the preview shows only directory listings.
# The preview receives a row ID and reads the row's path from the record file.
_skell_menu() {
  local rec=$_skell_complete_rec candidates=$_skell_complete_candidates
  local p w _skell_reply
  local -i i=0 hasdir=0
  _skell_empty "$rec" "$candidates"
  {
    for w; do
      i+=1
      p=''
      if [ "$_skell_cap_files" = 1 ] && _skell_dir_of "$w"; then
        p=$_skell_reply
        w=${w%/}/
        case $p in /*) ;; *) p=$PWD/$p ;; esac
        # The preview quotes this path. MSYS skips POSIX-to-Windows argument
        # conversion when an argument contains an apostrophe.
        case $OSTYPE in
          cygwin*|msys*) [[ $p =~ ^/([a-zA-Z])/ ]] && p=${BASH_REMATCH[1]^}:/${p:3} ;;
        esac
        case $p in *[$'\t\n']*) p='' ;; *) hasdir=1 ;; esac
      fi
      printf '%s\t%s\t\t%s\n' "$i" "$p" "${w//[$'\t\n']/ }"
    done
  } >| "$rec"
  if ! gawk -v sorted="$_skell_cap_sort" -f "$SKELL_ROOT/share/codec.awk" \
    -f "$SKELL_ROOT/share/completion-candidates.awk" "$rec" >| "$candidates"; then
    _skell_empty "$rec" "$candidates"
    return 1
  fi

  local -a prev=()
  if [ "$hasdir" = 1 ] && [ "${SKELL_COMPLETE_PREVIEW-}" != off ]; then
    prev=(--preview "gawk -f \"$SKELL_ROOT/share/codec.awk\" -f \"$SKELL_ROOT/share/preview-complete.awk\" -v n={1} \"$rec\""
          --preview-window 'right:50%:wrap')
  fi
  local -i rows=$(( $# + 4 )) cap=$(( ${LINES:-24} * 2 / 3 ))
  [ "$cap" -lt 6 ] && cap=6
  [ "$rows" -gt "$cap" ] && rows=$cap

  local chosen
  chosen=$(sk \
    --height "$rows" --min-height "$rows" --layout=reverse --border rounded \
    --prompt '> ' --info inline --ansi --tabstop 1 \
    --multi --cycle \
    --delimiter $'\t' --with-nth 4 \
    --tiebreak score,begin,index \
    --bind 'tab:down,btab:up,ctrl-space:toggle' \
    "${prev[@]}" < "$candidates")
  _skell_empty "$rec" "$candidates"
  [ -n "$chosen" ] || return 1
  local line
  while IFS= read -r line; do
    _skell_chosen+=("${line%%$'\t'*}")
  done <<< "$chosen"
}

# Command-position completion as bash does it natively: a word with a slash
# completes as a path, and no_empty_cmd_completion leaves an empty word alone.
_skell_commands() {
  if [ -z "$2" ] && shopt -q no_empty_cmd_completion; then
    compopt +o bashdefault +o default 2>/dev/null
    return 0
  fi
  compgen -c -- "$2" >| "$_skell_scratch" 2>/dev/null
  mapfile -t COMPREPLY < "$_skell_scratch"
  : >| "$_skell_scratch"
  case $2 in */*) compopt -o filenames 2>/dev/null ;; esac
}

_skell_wrap_specs
# Without these compspecs readline completes commands, filenames, and variables
# itself, and the menu would never see the matches. -o bashdefault and
# -o default keep that native completion when the menu is not running.
[ -n "${_skell_cw_func[-D]+x}" ] || complete -o bashdefault -o default -F _skell_cw_D -D
[ -n "${_skell_cw_func[-E]+x}" ] || complete -F _skell_commands -E
[ -n "${_skell_cw_func[-I]+x}" ] || complete -o bashdefault -o default -F _skell_commands -I
_skell_wrap_specs

for _skell_keymap in emacs-standard vi-insert; do
  bind -m "$_skell_keymap" -x '"\e[9301~": _skell_tab_begin' 2>/dev/null
  bind -m "$_skell_keymap" '"\e[9302~": complete' 2>/dev/null
  bind -m "$_skell_keymap" -x '"\e[9303~": _skell_tab_finish' 2>/dev/null
  bind -m "$_skell_keymap" '"\t": "\e[9301~\e[9302~\e[9303~"' 2>/dev/null

  # Shift+Tab runs readline's own completion unless the user bound it to a
  # function, a macro, or a shell command already.
  {
    bind -m "$_skell_keymap" -p
    bind -m "$_skell_keymap" -s
    bind -m "$_skell_keymap" -X
  } >| "$_skell_scratch" 2>/dev/null
  _skell_bound=0
  while IFS= read -r _skell_line; do
    case $_skell_line in '"\e[Z":'*) _skell_bound=1; break ;; esac
  done < "$_skell_scratch"
  [ "$_skell_bound" = 1 ] || bind -m "$_skell_keymap" '"\e[Z": complete' 2>/dev/null
done
: >| "$_skell_scratch"
unset _skell_keymap _skell_bound _skell_line
