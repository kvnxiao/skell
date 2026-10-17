function _skell_skim --description "Run skim below the prompt with skell's shared layout"
    # skim draws from the cursor row, so step below the prompt to keep it
    # visible, then step back up so fish repaints the prompt on its own row.
    printf '\n' >/dev/tty
    sk --layout=reverse --border rounded --info inline $argv
    set -l code $status
    printf '\e[A' >/dev/tty
    return $code
end
