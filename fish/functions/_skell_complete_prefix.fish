function _skell_complete_prefix --description "Print the unambiguous extension of a token" -a token
    set -l floor (string length -- "$token")
    set -l prefix $argv[2]
    test (string length -- "$prefix") -gt $floor; or return 1
    for word in $argv[3..]
        while test "$(string sub -l (string length -- "$prefix") -- "$word")" != "$prefix"
            set prefix (string sub -e -1 -- "$prefix")
            test (string length -- "$prefix") -gt $floor; or return 1
        end
    end

    # fish ranks case-insensitive and fuzzy matches below prefix matches, so the
    # shared prefix may not extend the typed token.
    test "$(string lower -- (string sub -l $floor -- "$prefix"))" = "$(string lower -- "$token")"; or return 1

    # Cutting between a backslash and the character it escapes would escape the
    # next typed character.
    set -l run (string match -gr '(\\\\+)$' -- "$prefix")
    if test (math (string length -- "$run") % 2) -eq 1
        set prefix (string sub -e -1 -- "$prefix")
    end
    test (string length -- "$prefix") -gt $floor; or return 1
    printf '%s' $prefix
end
