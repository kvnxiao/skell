function _skell_complete_put --description "Replace the token before the cursor" -a token text rest
    set -l start (math (commandline -C) - (string length -- "$token"))
    commandline -rt -- "$text$rest"
    commandline -C (math $start + (string length -- "$text"))
    commandline -f repaint
end
