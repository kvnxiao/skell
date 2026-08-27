function _skell_escape --description "Encode a command or directory as one store field" -a raw
    test -n "$raw"; or return 0
    set -l bs \x5c
    # A guard byte brackets the value through every pass: `string replace` reads
    # an operand beginning with a dash as an option, and a command substitution
    # strips a trailing newline that the leading guard alone would not protect.
    # The operand form is also the only one that keeps that newline, and the
    # input still holds newlines until the second pass.
    set -l s (string replace -a $bs $bs$bs "X$raw"X | string collect --allow-empty)
    set s (string replace -a \n $bs"n" "$s" | string collect --allow-empty)
    set s (string replace -a \t $bs"t" "$s" | string collect --allow-empty)
    set s (string replace -a \r $bs"r" "$s" | string collect --allow-empty)
    string sub -s 2 -e -1 "$s"
end
