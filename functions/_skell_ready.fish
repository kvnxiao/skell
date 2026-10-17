function _skell_ready --description "Check once per session that sk and gawk are on PATH"
    if not set -q _skell_ready
        set -g _skell_ready 1
        set -l missing
        for tool in sk gawk
            command -q $tool; or set -a missing $tool
        end
        if set -q missing[1]
            set -g _skell_ready 0
            __fish_echo printf 'skell: requires %s on PATH; Ctrl+R and Tab use fish defaults\n' \
                (string join ' and ' -- $missing)
        end
    end
    test $_skell_ready = 1
end
