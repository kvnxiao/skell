function _skell_msys_path -a raw
    set -l bs \x5c
    set -l drive (string match -gr "^([A-Za-z]):[$bs$bs/]" -- $raw)
    if test -z "$drive"
        printf '%s' $raw
        return
    end

    # When a console is attached, `path resolve` and `test -d` on a
    # drive-letter path add 10-30ms to interactive startup. Build the path from
    # MSYS2's default `/` cygdrive prefix instead.
    printf '%s' /(string lower -- $drive)(string sub -s 3 -- $raw | string replace -a $bs /)
end
