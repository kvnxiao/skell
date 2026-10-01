function _skell_complete --description "Complete the current token with skim"
    # Shift+Tab opens fish's pager, where Tab moves between its entries.
    if commandline --paging-mode; or not _skell_ready
        commandline -f complete
        return
    end

    set -l token (_skell_commandline -ct | string collect -N --allow-empty)
    # `complete -C` returns a glob unexpanded. fish's completion expands it.
    if string match -q -- '*\**' "$token"
        commandline -f complete
        return
    end

    set -l rows (complete -C --escape -- (_skell_commandline -c | string collect -N --allow-empty))
    if not set -q rows[1]
        commandline -f repaint
        return
    end

    set -l cands (string replace -r '\t.*' '' -- $rows)
    set -l rest (string sub -s (math (string length -- "$token") + 1) -- \
        (_skell_commandline -t | string collect -N --allow-empty))
    set -l after (string sub -s (math (commandline -C) + 1) -- \
        (_skell_commandline | string collect -N --allow-empty))

    if not set -q cands[2]
        _skell_complete_put "$token" (_skell_complete_join "$rest" "$after" $cands) "$rest"
        return
    end

    set -l prefix (_skell_complete_prefix "$token" $cands)
    if test -n "$prefix"
        _skell_complete_put "$token" "$prefix" "$rest"
        return
    end

    # Completion scripts can return descriptions with terminal controls, which
    # skim would interpret.
    set -l descs (_skell_visible (string replace -r '^[^\t]*\t?' '' -- $rows))

    if not set -q _skell_msys
        set -g _skell_msys 0
        test -e /usr/bin/msys-2.0.dll; and set _skell_msys 1
    end

    set -l width (math "min(40, max($(string join , -- (string length --visible -- $cands))))")
    set -l padded (string pad -r -w $width -- $cands)
    set -l lines
    set -l records
    set -l hasdir 0
    set -l i 0
    for cand in $cands
        set i (math $i + 1)
        set -l path
        if test "$SKELL_COMPLETE_PREVIEW" != off; and string match -q -- '*/' $cand
            set path (string unescape -- $cand"$(_skell_unclosed_quote $cand)" | string replace -r -- '^~/' "$HOME/")
            if test -d "$path"; and not string match -qr '[\t\n]' -- "$path"
                set hasdir 1
                # The drive rewrite below needs an absolute path.
                string match -q -- '/*' $path; or set path (string trim -r -c / -- $PWD)/$path
                # The preview quotes this path. MSYS skips POSIX-to-Windows
                # argument conversion when an argument contains an apostrophe.
                if test $_skell_msys = 1
                    set -l drive (string match -gr '^/([a-zA-Z])/' -- $path)
                    and set path (string upper -- $drive):/(string sub -s 4 -- $path)
                end
            else
                set path
            end
        end
        set -l desc "$descs[$i]"
        test -n "$desc"; and set desc \e"[2m$desc"\e"[0m"
        set -a lines "$i"\t"$padded[$i]"\t"$desc"
        set -a records "$i"\t"$path"\t"$cand"\t"$descs[$i]"
    end

    set -l show 0
    switch "$SKELL_COMPLETE_PREVIEW"
        case off
        case directory
            set show $hasdir
        case '*'
            set show $hasdir
            string length -q -- $descs; and set show 1
    end

    set -l awk_dir (status dirname)/skell-share
    set -l rec $SKELL_DATA_DIR/complete-fish-$fish_pid.tsv
    set -l preview
    if test $show = 1
        _skell_scratch $rec
        printf '%s\n' $records >$rec
        set preview --preview "gawk -f \"$awk_dir/codec.awk\" -f \"$awk_dir/preview-complete.awk\" -v n={1} \"$rec\"" \
            --preview-window 'right:50%:wrap'
    end

    # The border, prompt, and info line use four of skim's rows.
    set -l height (math "min($(count $cands) + 4, max(6, floor($LINES * 2 / 3)))")
    set -l chosen (printf '%s\n' $lines | _skell_skim \
        --height $height --min-height $height --prompt '> ' --ansi --tabstop 1 \
        --multi --cycle \
        --delimiter \t --with-nth 2.. --nth 1 \
        --tiebreak score,begin,index \
        --bind 'tab:down,btab:up,ctrl-space:toggle' \
        $preview)
    test $show = 1; and _skell_scratch $rec

    set -l ids (string replace -r '\t.*' '' -- $chosen)
    if not set -q ids[1]
        commandline -f repaint
        return
    end
    _skell_complete_put "$token" (_skell_complete_join "$rest" "$after" $cands[$ids]) "$rest"
end
