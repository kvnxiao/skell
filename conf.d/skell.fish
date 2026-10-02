# skell -- one command history for bash, fish, powershell, and zsh.
# https://github.com/kvnxiao/skell

status is-interactive; or return

if test -z "$SKELL_DATA_DIR"
    if test -n "$XDG_DATA_HOME"
        set -gx SKELL_DATA_DIR $XDG_DATA_HOME/skell
    else
        set -gx SKELL_DATA_DIR $HOME/.local/share/skell
    end
end
test -n "$SKELL_HISTORY"; or set -gx SKELL_HISTORY $SKELL_DATA_DIR/history.tsv

# Fish can stat a drive-letter path such as `C:/...` but cannot redirect to it.
# Rewrite the path before opening the store. Match drive letters first:
# converting costs ~3ms under MSYS2.
if string match -qr '^[A-Za-z]:[\x5c/]' -- $SKELL_DATA_DIR $SKELL_HISTORY
    and test -e /usr/bin/msys-2.0.dll
    set -gx SKELL_DATA_DIR (_skell_msys_path $SKELL_DATA_DIR)
    set -gx SKELL_HISTORY (_skell_msys_path $SKELL_HISTORY)
end

# The store contains the user's command history. Create new data directories
# and stores under a private umask.
if not test -d $SKELL_DATA_DIR; or not test -e $SKELL_HISTORY
    set -l prior_umask (umask)
    umask 077
    test -d $SKELL_DATA_DIR; or mkdir -p $SKELL_DATA_DIR
    test -e $SKELL_HISTORY; or touch $SKELL_HISTORY
    umask $prior_umask
end

# Spawning rm costs ~25ms under MSYS2, so the exit hook runs it only when a
# search or completion left scratch files behind.
function _skell_exit --on-event fish_exit
    set -l stale (path filter -- $SKELL_DATA_DIR/rank-fish-$fish_pid.tsv \
        $SKELL_DATA_DIR/rank-fish-$fish_pid.raw.tsv \
        $SKELL_DATA_DIR/complete-fish-$fish_pid.tsv)
    if set -q stale[1]
        command rm -f -- $stale
    end
end

# Cygwin turns one `echo` to this O_APPEND descriptor into one NtWriteFile at
# FILE_WRITE_TO_END_OF_FILE. Tested NTFS writes stay intact through 1024 bytes;
# _skell_fit limits longer records.
function _skell_record --on-event fish_postexec
    set -l code $status
    test -n "$argv[1]"; or return
    string match -q ' *' -- $argv[1]; and return

    # fish has no clock variable, and `date` would fork on every prompt. Add
    # $HOME's modification time to its age to get the current epoch.
    set -l mtime
    set -l age
    set -l stamp
    path mtime $HOME | read mtime
    path mtime -R $HOME | read age
    # If fish cannot stat $HOME, skip the record instead of passing empty
    # values to `math`.
    test -n "$mtime" -a -n "$age"; or return
    math -s0 $mtime + $age | read stamp

    set -l cmd (_skell_escape $argv[1] | string collect --allow-empty)

    # Escape tabs and newlines in $PWD before writing the TSV fields. Cache the
    # encoded value until the directory changes.
    if test "$PWD" != "$_skell_dir_raw"
        set -g _skell_dir_raw $PWD
        set -g _skell_dir (_skell_escape $PWD | string collect --allow-empty)
    end

    # fish expands \t only outside double quotes. Quote each field separately,
    # then append the record and newline with one `echo` to prevent interleaving.
    set -l record (_skell_fit "$stamp"\t"$_skell_dir"\t"$code"\tfish "$cmd" | string collect --allow-empty)
    echo -- $record >>$SKELL_HISTORY
end

bind ctrl-r _skell_history
bind -M insert ctrl-r _skell_history
bind tab _skell_complete
bind -M insert tab _skell_complete
