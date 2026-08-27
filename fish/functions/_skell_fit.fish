function _skell_fit --description "Trim a history record to the atomic-append ceiling" -a head cmd
    # Concurrent appenders interleave without tearing up to 1024 bytes on NTFS
    # through the Cygwin and MSYS2 runtimes, which is where skell is tested. A
    # record holding any non-ASCII code point is capped at a quarter of the
    # budget, since four bytes is the widest UTF-8 encoding and a byte count
    # would cost a fork. `string length` counts code points, as gawk does,
    # while bash, zsh, and PowerShell count UTF-16 units; either count stays
    # inside 1000 bytes, so a command outside the BMP is cut at a different
    # point depending on which shell recorded it.
    set -l record $head\t$cmd
    set -l limit 1000
    if string match -qr '[^\x00-\x7F]' -- $record
        set limit 250
    end
    set -l width (string length -- $record)
    if test $width -le $limit
        printf '%s' $record
        return
    end

    set -l keep (math $limit - (string length -- $head) - 3)
    if test $keep -lt 1
        set -l fields (string split -m 3 \t -- $head)
        set head $fields[1]\tunknown\t$fields[3]\t$fields[4]
        set record $head\t$cmd
        set limit 1000
        if string match -qr '[^\x00-\x7F]' -- $record
            set limit 250
        end
        # Dropping the directory can be enough on its own, and a record that
        # now fits is whole: marking it elided would claim a cut that never
        # happened.
        if test (string length -- $record) -le $limit
            printf '%s' $record
            return
        end
        set keep (math $limit - (string length -- $head) - 3)
        test $keep -lt 0; and set keep 0
    end

    set -l bs \x5c
    set -l kept (string sub -l $keep -- $cmd | string collect --allow-empty)
    # An even run of trailing backslashes is whole escape pairs; an odd run
    # means the cut landed inside one, so the last backslash goes.
    set -l run (string match -gr "($bs$bs+)\$" -- $kept | string collect --allow-empty)
    if test (math (string length -- $run) % 2) -eq 1
        set kept (string sub -e -1 -- $kept | string collect --allow-empty)
    end
    printf '%s' $head\t$kept$bs"+"
end
