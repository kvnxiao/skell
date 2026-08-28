function _skell_unescape --description "Decode a stored field back to its typed form" -a enc
    test -n "$enc"; or return 0
    set -l bs \x5c
    # Decode doubled backslashes before other escapes so literal store content
    # cannot become an escape introducer.
    #
    # Guard the field before splitting. Reading each guarded segment from stdin
    # preserves empty values, leading dashes, and decoded trailing newlines.
    set -l parts (string split -- $bs$bs "X$enc"X)
    set -l decoded
    for p in $parts
        set -l d (printf '%s' "$p" | string replace -a $bs"t" \t | string collect --allow-empty)
        set d (printf '%s' "$d" | string replace -a $bs"r" \r | string collect --allow-empty)
        set d (printf '%s' "$d" | string replace -a $bs"+" " […]" | string collect --allow-empty)
        set d (printf '%s' "$d" | string replace -a $bs"n" \n | string collect --allow-empty)
        set -a decoded "$d"
    end
    # `string collect` returns two arguments for empty input. The guards keep
    # the joined value non-empty.
    set -l joined (string join -- $bs $decoded | string collect --allow-empty)
    string sub -s 2 -e -1 "$joined"
end
