function _skell_history --description "Search skell's history with skim"
    if not test -s $SKELL_HISTORY
        commandline -f repaint
        return
    end

    # fisher does not install share/, so the plugin build copies the awk
    # scripts into a directory beside these functions.
    set -l awk_dir (status dirname)/skell-share

    # The ranked file is a plaintext dump of the whole history, so it stays in
    # skell's own directory rather than a temp directory shared with every
    # other user of the machine. MSYS2 and Windows number processes
    # separately, so the filename includes the shell's name.
    set -l rank $SKELL_DATA_DIR/rank-fish-$fish_pid.tsv
    gawk -f $awk_dir/rank.awk $SKELL_HISTORY >$rank; or return

    set -l query (commandline -b)[1]

    # skim moves onto the alternate screen, so this newline keeps the invoking
    # prompt visible.
    printf '\n' >/dev/tty
    set -l chosen (sk \
        --height 60% --min-height 15 --layout=reverse --border rounded \
        --prompt 'history ❯ ' --info inline --ansi \
        --delimiter \t --with-nth 6.. \
        --tiebreak score,index \
        --query "$query" \
        --preview "gawk -f \"$awk_dir/codec.awk\" -f \"$awk_dir/preview-history.awk\" -v n={1} \"$rank\"" \
        --preview-window 'right:55%:wrap' \
        --bind 'enter:accept(edit),alt-enter:accept(run)' <$rank)

    if test (count $chosen) -lt 2
        commandline -f repaint
        return
    end

    # A bare command substitution would split a decoded multiline command across
    # elements and drop its last line's newline.
    set -l command (_skell_unescape (string split -m 5 \t -- $chosen[2])[6] | string collect --allow-empty)
    commandline --replace -- $command
    if test "$chosen[1]" = run
        commandline -f execute
    else
        commandline -f repaint
    end
end
