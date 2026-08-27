function _skell_unescape --description "Decode a stored field back to its typed form" -a enc
    test -n "$enc"; or return 0
    set -l bs \x5c
    # The encoded backslash pair is consumed before any other escape is
    # decoded, so a byte the store holds literally can never be read as an
    # escape introducer.
    #
    # A guard byte brackets the whole field before it is split, which leaves the
    # first segment starting with the guard and the last ending with it. Each
    # pass then reads its segment from stdin, which carries an empty segment and
    # a segment beginning with a dash that an operand would not, and no decoded
    # newline is ever trailing for the stdin form to drop.
    set -l parts (string split -- $bs$bs "X$enc"X)
    set -l decoded
    for p in $parts
        set -l d (printf '%s' "$p" | string replace -a $bs"t" \t | string collect --allow-empty)
        set d (printf '%s' "$d" | string replace -a $bs"r" \r | string collect --allow-empty)
        set d (printf '%s' "$d" | string replace -a $bs"+" " […]" | string collect --allow-empty)
        set d (printf '%s' "$d" | string replace -a $bs"n" \n | string collect --allow-empty)
        set -a decoded "$d"
    end
    # The guards keep the joined value at two characters or more, so `string
    # collect` never faces the empty input it answers with two arguments.
    set -l joined (string join -- $bs $decoded | string collect --allow-empty)
    string sub -s 2 -e -1 "$joined"
end
