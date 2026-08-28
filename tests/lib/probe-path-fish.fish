# A generated MSYS2 prelude sets fish_function_path, SKELL_OUT_DIR,
# SKELL_SANDBOX_WIN, SKELL_SANDBOX_MSYS, and SKELL_REPO_WIN before sourcing this
# file.

if not test -e /usr/bin/msys-2.0.dll
    printf skip >$SKELL_OUT_DIR/COMPLETE
    return
end

set -l bs \x5c
set -l win_dir $SKELL_SANDBOX_WIN/data
printf '%s' (_skell_msys_path $win_dir) >$SKELL_OUT_DIR/from-slash
printf '%s' (_skell_msys_path (string replace -a / $bs -- $win_dir)) >$SKELL_OUT_DIR/from-backslash
printf '%s' (_skell_msys_path $SKELL_SANDBOX_MSYS/data) >$SKELL_OUT_DIR/from-posix

for letter in Z Y X W
    if not test -d $letter:/
        printf '%s' $letter:/nowhere >$SKELL_OUT_DIR/unmounted-want
        printf '%s' (_skell_msys_path $letter:/nowhere) >$SKELL_OUT_DIR/unmounted
        break
    end
end

# Set the Windows paths before sourcing `fish/conf.d/skell.fish`; the file
# rewrites them while sourcing.
set -gx SKELL_DATA_DIR $SKELL_SANDBOX_WIN/store
set -gx SKELL_HISTORY $SKELL_SANDBOX_WIN/store/history.tsv
source $SKELL_REPO_WIN/fish/conf.d/skell.fish
string match -qr '^[A-Za-z]:' -- $SKELL_DATA_DIR; or printf yes >$SKELL_OUT_DIR/data-rewritten
string match -qr '^[A-Za-z]:' -- $SKELL_HISTORY; or printf yes >$SKELL_OUT_DIR/history-rewritten

echo record >>$SKELL_HISTORY
set -l append_rc $status
printf '%s' $append_rc >$SKELL_OUT_DIR/store-append
test -s $SKELL_SANDBOX_MSYS/store/history.tsv; and printf yes >$SKELL_OUT_DIR/store-landed

printf done >$SKELL_OUT_DIR/COMPLETE
