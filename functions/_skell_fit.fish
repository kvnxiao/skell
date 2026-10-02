function _skell_fit --description "Trim a history record to the atomic-append ceiling" -a head cmd
    # On NTFS, the tested Cygwin and MSYS2 runtimes append up to 1024 bytes
    # without interleaving. Records use a 1000-byte budget. Because each UTF-8
    # code point may use four bytes, records with non-ASCII text use a
    # 250-character limit without a byte-counting fork. fish and gawk count code
    # points, while bash, zsh, and PowerShell count UTF-16 units. Both stay
    # within the budget, but they may trim an astral command at different
    # positions.
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
        # If replacing the directory makes the whole command fit, return the
        # record without an elision marker.
        if test (string length -- $record) -le $limit
            printf '%s' $record
            return
        end
        set keep (math $limit - (string length -- $head) - 3)
        test $keep -lt 0; and set keep 0
    end

    set -l bs \x5c
    set -l kept (string sub -l $keep -- $cmd | string collect --allow-empty)
    # If the cut leaves an odd run of backslashes, drop the incomplete escape.
    set -l run (string match -gr "($bs$bs+)\$" -- $kept | string collect --allow-empty)
    if test (math (string length -- $run) % 2) -eq 1
        set kept (string sub -e -1 -- $kept | string collect --allow-empty)
    end
    printf '%s' $head\t$kept$bs"+"
end
