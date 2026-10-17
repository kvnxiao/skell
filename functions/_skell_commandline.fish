function _skell_commandline --description "Print commandline output without the newline it appends"
    # `string collect` without -N strips every trailing newline, including ones
    # the buffer contains.
    printf '%s' (string split -m1 -r \n -- (commandline $argv | string collect -N --allow-empty))[1]
end
