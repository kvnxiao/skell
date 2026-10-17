function _skell_scratch --description "Create or empty private scratch files"
    # Truncate instead of spawning rm; the exit hook in conf.d deletes the files.
    set -l prior_umask (umask)
    umask 077
    for file in $argv
        printf '' >$file
    end
    umask $prior_umask
end
