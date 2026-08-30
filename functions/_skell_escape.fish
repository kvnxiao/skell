function _skell_escape --description "Encode a command or directory as one store field" -a raw
    test -n "$raw"; or return 0
    set -l bs \x5c
    # Guard both ends before replacement. The guards keep a leading dash from
    # becoming an option and preserve a trailing newline through command
    # substitution. The operand form preserves newlines until the newline pass.
    set -l s (string replace -a $bs $bs$bs "X$raw"X | string collect --allow-empty)
    set s (string replace -a \n $bs"n" "$s" | string collect --allow-empty)
    set s (string replace -a \t $bs"t" "$s" | string collect --allow-empty)
    set s (string replace -a \r $bs"r" "$s" | string collect --allow-empty)
    string sub -s 2 -e -1 "$s"
end
