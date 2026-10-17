function _skell_visible --description "Render C0 and C1 controls as <0xNN>, one argument per line"
    set -q argv[1]; or return 0
    set -l out $argv
    set -l seen
    for c in (string match -ar '[\x01-\x1f\x7f-\x{9f}]' -- $argv)
        contains -- $c $seen; and continue
        set -a seen $c
        set out (string replace -a -- $c "<0x$(printf '%02X' "'$c")>" $out)
    end
    printf '%s\n' $out
end
