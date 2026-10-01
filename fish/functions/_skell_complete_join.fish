function _skell_complete_join --description "Join chosen completions for insertion" -a rest after
    set -l words $argv[3..]
    set -l last $words[-1]
    set -e words[-1]
    set -l out
    for word in $words
        set -a out $word"$(_skell_unclosed_quote $word)"
    end
    # fish omits the trailing space after a completion that ends in one of these
    # characters, so the next Tab continues the same word.
    if test -z "$rest"
        and not string match -qr '^\s' -- "$after"
        and not string match -qr '[/=@:.,-]$' -- "$last"
        set last $last"$(_skell_unclosed_quote $last)"' '
    end
    string join ' ' -- $out $last
end
