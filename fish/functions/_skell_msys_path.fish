function _skell_msys_path -a raw
    set -l bs \x5c
    set -l drive (string match -gr "^([A-Za-z]):[$bs$bs/]" -- $raw)
    # Guard unmounted drive letters because `path resolve` treats them as
    # relative paths.
    if test -z "$drive"; or not test -d $drive:/
        printf '%s' $raw
        return
    end

    printf '%s' (path resolve $drive:/)(string sub -s 3 -- $raw | string replace -a $bs /)
end
