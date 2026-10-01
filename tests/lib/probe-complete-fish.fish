# A generated MSYS2 prelude sets fish_function_path and SKELL_OUT_DIR before
# sourcing this file.

function _probe -a name
    $argv[2..] >$SKELL_OUT_DIR/$name.out
    printf '%s' $status >$SKELL_OUT_DIR/$name.status
end

set -l bs \x5c

_probe prefix-extends _skell_complete_prefix sub subdir-one subdir-two
_probe prefix-no-progress _skell_complete_prefix sr src/ srv/ sre.txt
_probe prefix-empty-token _skell_complete_prefix '' checkout cherry
_probe prefix-case _skell_complete_prefix fa Fancy.md Fancier
_probe prefix-fuzzy _skell_complete_prefix dto dirtwo/ dotfiles/
_probe prefix-dangling _skell_complete_prefix a a$bs'$b' a$bs' c'
_probe prefix-escaped-backslash _skell_complete_prefix x xa$bs$bs'b' xa$bs$bs'c'

_probe join-file _skell_complete_join '' '' file
_probe join-dir _skell_complete_join '' '' src/
_probe join-option-value _skell_complete_join '' '' --color=
_probe join-closes-quote _skell_complete_join '' '' '"file a.txt'
_probe join-closed-quote _skell_complete_join '' '' '"file a.txt"'
_probe join-open-dir-quote _skell_complete_join '' '' '"dir one/'
_probe join-many _skell_complete_join '' '' sre.txt src/
_probe join-many-quoted _skell_complete_join '' '' '"dir one/' x
_probe join-mid-token _skell_complete_join x x foo
_probe join-before-space _skell_complete_join '' ' bar' foo
_probe join-escaped-quote _skell_complete_join '' '' it$bs"'s"
_probe join-single-quoted _skell_complete_join '' '' "'it"$bs"'s"

_probe commandline-plain _skell_commandline --input 'ls fi' -c
_probe commandline-empty _skell_commandline --input '' -c
_probe commandline-newline _skell_commandline --input begin\n -c
_probe commandline-newlines _skell_commandline --input a\n'b c'\n\n -c

_probe visible-osc _skell_visible a\e']0;t'\a
_probe visible-c1 _skell_visible (printf 'x\u009dy')
_probe visible-tab _skell_visible a\tb
_probe visible-plain _skell_visible 'café — x' '' plain

printf done >$SKELL_OUT_DIR/COMPLETE
