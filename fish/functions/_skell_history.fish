function _skell_history --description "Search skell's history with skim"
    if not test -s $SKELL_HISTORY
        commandline -f repaint
        return
    end

    # fisher does not install share/. The plugin build copies the awk scripts
    # beside these functions.
    set -l awk_dir (status dirname)/skell-share

    # The ranked file contains the full history. Keep it in skell's private
    # data directory. Because MSYS2 and Windows use separate process ID spaces,
    # include the shell name to avoid collisions.
    set -l rank $SKELL_DATA_DIR/rank-fish-$fish_pid.tsv
    gawk -f $awk_dir/rank.awk $SKELL_HISTORY >$rank; or return

    set -l query (commandline -b)[1]

    # Print a newline before skim switches screens to keep the prompt visible.
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

    # A bare command substitution would split a multiline command and drop its
    # final newline.
    set -l command (_skell_unescape (string split -m 5 \t -- $chosen[2])[6] | string collect --allow-empty)
    commandline --replace -- $command
    if test "$chosen[1]" = run
        commandline -f execute
    else
        commandline -f repaint
    end
end
