# skell -- one command history for bash, fish, powershell, and zsh.
# https://github.com/kvnxiao/skell

status is-interactive; or return

if not set -q SKELL_DATA_DIR
    if set -q XDG_DATA_HOME
        set -gx SKELL_DATA_DIR $XDG_DATA_HOME/skell
    else
        set -gx SKELL_DATA_DIR $HOME/.local/share/skell
    end
end
set -q SKELL_HISTORY; or set -gx SKELL_HISTORY $SKELL_DATA_DIR/history.tsv

# The store holds every command the user runs, so the directory and the file
# are created under a private umask rather than the caller's.
if not test -d $SKELL_DATA_DIR; or not test -e $SKELL_HISTORY
    set -l prior_umask (umask)
    umask 077
    test -d $SKELL_DATA_DIR; or mkdir -p $SKELL_DATA_DIR
    test -e $SKELL_HISTORY; or touch $SKELL_HISTORY
    umask $prior_umask
end

function _skell_exit --on-event fish_exit
    command rm -f -- $SKELL_DATA_DIR/rank-fish-$fish_pid.tsv
end

# A record is one `echo` into an O_APPEND file descriptor, which Cygwin
# compiles to a single NtWriteFile at FILE_WRITE_TO_END_OF_FILE. Concurrent
# appenders interleave without tearing up to 1024 bytes on NTFS through that
# runtime, which is where skell is tested; _skell_fit trims anything longer.
function _skell_record --on-event fish_postexec
    set -l code $status
    test -n "$argv[1]"; or return
    string match -q ' *' -- $argv[1]; and return

    # fish exposes no clock variable, and `date` would fork on every prompt.
    # `path mtime` prints $HOME's modification time as an absolute epoch and
    # `-R` prints its age in seconds, so the two sum to the current epoch
    # whatever that time was.
    set -l mtime
    set -l age
    set -l stamp
    path mtime $HOME | read mtime
    path mtime -R $HOME | read age
    # An unstat-able $HOME leaves both empty, which would make `math` report a
    # syntax error at every prompt.
    test -n "$mtime" -a -n "$age"; or return
    math -s0 $mtime + $age | read stamp

    set -l cmd (_skell_escape $argv[1] | string collect --allow-empty)

    # A directory holding a tab or a newline would shift every field that
    # follows it, so $PWD is escaped on the same terms as the command. The
    # escaped form is cached: it changes far more rarely than once per command.
    if test "$PWD" != "$_skell_dir_raw"
        set -g _skell_dir_raw $PWD
        set -g _skell_dir (_skell_escape $PWD | string collect --allow-empty)
    end

    # fish expands \t outside double quotes only, so each field is quoted on
    # its own. The record and its newline leave in one `echo`: a second write
    # would let another shell interleave between them.
    set -l record (_skell_fit "$stamp"\t"$_skell_dir"\t"$code"\tfish "$cmd" | string collect --allow-empty)
    echo -- $record >>$SKELL_HISTORY
end

bind ctrl-r _skell_history
bind -M insert ctrl-r _skell_history
