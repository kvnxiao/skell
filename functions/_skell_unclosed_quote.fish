function _skell_unclosed_quote --description "Print the quote a shell word leaves open" -a word
    set -l quote
    set -l escaped 0
    for c in (string split '' -- $word)
        if test $escaped = 1
            set escaped 0
            continue
        end
        switch $c
            case \\
                set escaped 1
            case '"' "'"
                if test -z "$quote"
                    set quote $c
                else if test "$quote" = $c
                    set quote
                end
        end
    end
    printf '%s' $quote
end
