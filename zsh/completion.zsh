# skell -- skim-powered completion menu for zsh.
# https://github.com/kvnxiao/skell

zmodload zsh/zutil

typeset -gi _skell_comp_active=0

# _skell_complete_apply replays each parsed flag. Keep the zparseopts spec
# aligned with compadd's option list.
_skell_compadd() {
  setopt localoptions extended_glob

  local -A apre hpre dscrs _oad _mesg
  local -a isfile _opts __ expl
  zparseopts -a _opts P:=apre p:=hpre d:=dscrs X+:=expl O:=_oad A:=_oad D:=_oad f=isfile \
             i: S: s: I: x:=_mesg r: R: W: F: M+: E: q e Q n U C \
             J:=__ V:=__ a=__ l=__ k=__ o::=__ 1=__ 2=__

  # With -O, -A, or -D, compadd fills an array instead of offering a match.
  if (( $#_oad != 0 || ! _skell_comp_active )); then
    builtin compadd "$@"
    return
  fi

  local -a __hits __dscr
  (( $#dscrs == 1 )) && __dscr=("${(@P)${(v)dscrs}}")
  builtin compadd -A __hits -D __dscr "$@"
  local -i ret=$?
  if (( $#__hits == 0 )); then
    (( $#_mesg )) && builtin compadd -x $_mesg
    return $ret
  fi

  expl=$expl[2]

  local PREFIX="$PREFIX"
  local PREFIX_ORIG="$PREFIX"

  # _approximate adds an (#a<n>) glob flag to PREFIX. Remove it before replay.
  # Add -U to skip compadd's prefix check after stripping the flag.
  if [[ $curcontext == (*approximate*|*correct*) ]]; then
    PREFIX=${PREFIX/#\(\#a[0-9]##\)/}
    PREFIX=${PREFIX/#\~\(\#a[0-9]##\)/~}
    if [[ $PREFIX_ORIG != $PREFIX ]] && (( ${_opts[(I)-U]} == 0 )); then
      _opts+=(-U)
    fi
  fi

  local key expanded ctx=$'<\0>'
  for key in PREFIX SUFFIX IPREFIX ISUFFIX; do
    expanded=${(P)key}
    [[ -n $expanded ]] && ctx+=$'\0'$key$'\0'$expanded
  done
  PREFIX="$PREFIX_ORIG"

  # For file matches, an empty prefix means the candidate is relative to the
  # working directory. A non-empty directory cannot replace the -f flag.
  local dir=
  local -i isf=0
  if [[ -n $isfile ]]; then
    isf=1
    dir=${${(Qe)~${:-$IPREFIX$hpre}}}
  fi

  local -i grp=0
  if [[ -n $expl ]]; then
    _skell_groups+=$expl
    grp=$_skell_groups[(ie)$expl]
  fi

  _opts+=("${(@kv)apre}" "${(@kv)hpre}" $isfile)
  ctx+=$'\0args\0'${(pj:\1:)_opts}

  local w d
  local -i i
  for (( i = 1; i <= $#__hits; i++ )); do
    w=$__hits[i] d=$__dscr[i]
    [[ -n $d ]] || d=$w
    # Replace tabs and newlines that would break the TSV row.
    d=${d//[$'\n\t']/ }
    _skell_words+=$w
    _skell_dscrs+=$d
    _skell_ctxs+=$ctx
    _skell_dirs+=$dir
    _skell_isfile+=$isf
    _skell_grps+=$grp
  done

  builtin compadd "$@"
}

_skell_complete() {
  local -aU _skell_groups
  local -i ret=0

  # Use a wide COLUMNS value to keep completer descriptions on one line.
  COLUMNS=500 _skell_main_complete "$@" || ret=$?

  local list_types=$options[list_types]
  emulate -L zsh -o extended_glob

  local -i n=$#_skell_words
  (( n == 0 )) && return 1

  local -i i same=1
  for (( i = 2; i <= n; i++ )); do
    [[ $_skell_words[i] == $_skell_words[1] ]] || { same=0; break }
  done

  local -a ids=() disp=() dirs=()
  local -A seen=()
  local d p key
  for (( i = 1; i <= n; i++ )); do
    (( same && i > 1 )) && break
    d=$_skell_dscrs[i]
    p=
    if (( $_skell_isfile[i] )); then
      p=$_skell_dirs[i]${(Q)_skell_words[i]}
      if [[ -d $p ]]; then
        [[ $list_types == off ]] || d+=/
        # The preview has its own working directory. Treat MSYS drive-letter
        # paths as absolute even though they have no leading slash.
        [[ $p == (/|[a-zA-Z]:/)* ]] || p=$PWD/$p
      else
        p=
      fi
    fi
    key=$_skell_grps[i]$'\0'$d
    (( $+seen[$key] )) && continue
    seen[$key]=1
    ids+=$i
    disp+=$d
    dirs+=$p
  done

  case $#ids in
    1) _skell_chosen=($ids[1]) ;;
    *)
      # _approximate sets compstate[list] to force when corrections must reach
      # the menu. Do not return early for an unambiguous prefix in that state.
      if [[ $compstate[insert] == *unambiguous ]] \
        && [[ -n $compstate[unambiguous] ]] \
        && [[ $compstate[unambiguous] != $compstate[quote]$IPREFIX$PREFIX$compstate[quote] ]] \
        && [[ $compstate[list] != *force* ]]; then
        compstate[list]=
        compstate[insert]=unambiguous
        _skell_finish=1
        return 0
      fi
      # Clear compstate even when the menu is canceled to stop zsh from
      # inserting or listing matches on its own.
      _skell_menu
      ;;
  esac

  compstate[list]=
  compstate[insert]=
  return $ret
}

# ids, disp, dirs, and the capture arrays are dynamically scoped from
# _skell_complete. The preview receives only a candidate index and reads the
# remaining fields from the record file.
_skell_menu() {
  local -i gw=0 i gi
  local g p

  # Cap verbose `format` values before they crowd out candidates.
  if (( $#_skell_groups > 1 )); then
    for g in $_skell_groups; do (( $#g > gw )) && gw=$#g; done
    (( gw > 20 )) && gw=20
    (( gw++ ))
  fi

  # The record may contain filesystem paths. Create it under a private umask;
  # the exit hook in zsh/init.zsh removes the same path.
  local rec=$_skell_complete_rec
  (umask 077; : > $rec)
  local -a lines=()
  local -i hasdir=0
  for (( i = 1; i <= $#ids; i++ )); do
    p=$dirs[i]
    # Drop paths with tabs or newlines that would break the TSV row.
    if [[ $p == *[$'\t\n']* ]]; then
      p=
    elif [[ -n $p ]]; then
      hasdir=1
      # The preview quotes this path. MSYS skips POSIX-to-Windows argument
      # conversion when an argument contains an apostrophe.
      [[ $OSTYPE == (cygwin|msys)* ]] && p=${p/#\/(#b)([a-zA-Z])\//${match[1]:u}:/}
    fi
    g=
    if (( gw )); then
      gi=$_skell_grps[$ids[i]]
      g=${${_skell_groups[gi]:-}//[$'\n\t']/ }
      (( $#g > gw - 1 )) && g=${g[1,gw-2]}$'…'
      g=$'\033[2m'${(r:$gw:)g}$'\033[0m'
    fi
    lines+=("$ids[i]"$'\t'"$p"$'\t'"$g"$'\t'"$disp[i]")
  done
  print -rl -- $lines > $rec || return 1

  local -i rows=$(( $#ids + 2 )) cap=$(( LINES * 2 / 3 ))
  (( rows > cap )) && rows=$cap
  (( rows < 3 )) && rows=3

  local -a nth=() prev=()
  local with=4
  if (( gw )); then
    with='3..'
    nth=(--nth 2)
  fi
  if (( hasdir )); then
    prev=(--preview "gawk -f \"$SKELL_ROOT/share/preview-complete.awk\" -v n={1} \"$rec\""
          --preview-window 'right:50%:wrap')
  fi

  local -a chosen
  chosen=("${(@f)$(sk \
    --height $rows --layout=reverse --border rounded \
    --prompt '> ' --info inline --ansi --tabstop 1 \
    --multi --cycle \
    --delimiter $'\t' --with-nth $with $nth \
    --tiebreak score,begin,index \
    --bind 'tab:down,btab:up,ctrl-space:toggle' \
    $prev < $rec)}")
  command rm -f $rec

  [[ -n $chosen[1] ]] || return 1

  _skell_chosen+=("${(@)chosen%%$'\t'*}")
  return 0
}

# Register a completion widget to make the chosen words the only matches in a
# new completion context.
_skell_complete_apply() {
  local -i id
  local -A v
  local -a args
  for id in $_skell_chosen; do
    v=("${(@0)${_skell_ctxs[id]}}")
    args=("${(@ps:\1:)v[args]}")
    [[ -z $args[1] ]] && args=()
    IPREFIX=${v[IPREFIX]-} PREFIX=${v[PREFIX]-} SUFFIX=${v[SUFFIX]-} ISUFFIX=${v[ISUFFIX]-}
    builtin compadd "${args[@]}" -Q -- "$_skell_words[id]"
  done

  compstate[list]=
  if (( $#_skell_chosen == 1 )); then
    compstate[insert]='1'
    [[ $RBUFFER == ' '* ]] || compstate[insert]+=' '
  elif (( $#_skell_chosen > 1 )); then
    compstate[insert]='all'
  fi
}

_skell_complete_widget() {
  local -a _skell_words=() _skell_dscrs=() _skell_ctxs=() _skell_dirs=() \
           _skell_isfile=() _skell_grps=() _skell_chosen=()
  local -i _skell_finish=0 ret=0
  local -i _skell_comp_active=1

  echoti civis >/dev/tty 2>/dev/null
  {
    zle .skell-orig-$_skell_orig_widget || ret=$?
    if (( ! _skell_finish )) && { (( $#_skell_chosen )) || (( ! ret )); }; then
      zle _skell_complete_apply || ret=$?
    fi
  } always {
    # Restore terminal state even when an interrupt exits the widget early.
    _skell_comp_active=0
    echoti cnorm >/dev/tty 2>/dev/null
  }
  zle .redisplay
  return $ret
}

() {
  emulate -L zsh -o extended_glob

  # On re-source, keep the original widget instead of wrapping skell's wrapper
  # and recursing.
  if (( ! $+_skell_orig_widget )); then
    typeset -g _skell_orig_widget="${${$(builtin bindkey '^I')##* }:-expand-or-complete}"
    local -a compinit_widgets=(
      complete-word delete-char-or-list expand-or-complete
      expand-or-complete-prefix list-choices menu-complete
      menu-expand-or-complete reverse-menu-complete
    )
    # Use a dot-prefixed name that widget-wrapping plugins skip.
    if [[ $widgets[$_skell_orig_widget] == builtin ]] \
      && (( $compinit_widgets[(Ie)$_skell_orig_widget] )); then
      zle -C .skell-orig-$_skell_orig_widget .$_skell_orig_widget _main_complete
    else
      zle -A $_skell_orig_widget .skell-orig-$_skell_orig_widget
    fi
  fi

  zle -N _skell_complete_widget
  zle -C _skell_complete_apply complete-word _skell_complete_apply

  # Grouping compadd entries merges distinct matches. Add one entry per row.
  zstyle ':completion:*' list-grouped false
  bindkey -M emacs '^I' _skell_complete_widget
  bindkey -M viins '^I' _skell_complete_widget

  autoload +X -Uz _main_complete _approximate

  if (( ! $+functions[_skell_main_complete] )); then
    functions[_skell_main_complete]=$functions[_main_complete]
    functions[_skell_approximate_orig]=$functions[_approximate]
    # Replace _approximate's `builtin compadd` call to let the wrapper capture
    # the uncorrected string.
    functions[_skell_approximate_inner]="${functions[_approximate]//builtin[[:space:]]##compadd/_skell_compadd}"
  fi

  functions[compadd]=$functions[_skell_compadd]
  function _main_complete() { _skell_complete "$@" }

  # Let _approximate add its (#a<n>) flag while no compadd wrapper exists.
  function _approximate() {
    unfunction compadd
    {
      if (( _skell_comp_active )); then
        _skell_approximate_inner "$@"
      else
        _skell_approximate_orig "$@"
      fi
    } always {
      functions[compadd]=$functions[_skell_compadd]
    }
  }
}
