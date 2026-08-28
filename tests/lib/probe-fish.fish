# A generated MSYS2 prelude sets fish_function_path, SKELL_VECTORS_TSV, and
# SKELL_OUT_DIR before sourcing this file.
#
# MSYS2 converts CRLF during file reads and reparses backslashes in command
# lines built by Git Bash. Rebuild vectors from %XX specs. The specs contain
# only ASCII bytes; reconstruction does not depend on file encoding.
# Recording hooks do not read commands from files; this constraint applies only
# to the test harness.

# Per-byte command substitutions would discard a lone newline. Decode the whole
# spec at once. Keep guard bytes to preserve trailing newlines for the function
# under test.
function _probe_unhex -a spec
    set -l bs \x5c
    printf '%b' (string replace -a '%' $bs"x" "X$spec"X | string collect --allow-empty)
end

# Keep guards through both functions. Escaping and decoding preserve `X`, and
# the driver brackets expected values the same way. Removing the guards in fish
# would expose trailing newlines to trimming.

for line in (cat $SKELL_VECTORS_TSV)
    string match -q '#*' -- $line; and continue
    set -l f (string split -m 2 \t -- $line)
    test (count $f) -ge 3; or continue
    set -l name $f[1]
    set -l raw (_probe_unhex "$f[2]" | string collect --allow-empty --no-trim-newlines)
    set -l enc (_probe_unhex "$f[3]" | string collect --allow-empty --no-trim-newlines)

    # Both functions print a trailing newline that `string collect` strips.
    # Re-emit the collected value with printf.
    set -l got_enc (_skell_escape "$raw" | string collect --allow-empty)
    set -l got_dec (_skell_unescape "$enc" | string collect --allow-empty)
    printf '%s' "$got_enc" >$SKELL_OUT_DIR/$name.enc.out
    printf '%s' "$got_dec" >$SKELL_OUT_DIR/$name.dec.out
end

_skell_fit "1787700487"\t"/d"\t"0"\tfish 'git status' >$SKELL_OUT_DIR/fit-short

set -l longdir /(string repeat -n 1200 d)
_skell_fit "1787700487"\t"$longdir"\t"0"\tfish 'git status' >$SKELL_OUT_DIR/fit-longdir

for pad in 0 1 2 3
    set -l cmd (string repeat -n (math 980 + $pad) x)(string repeat -n 8 \x5c)
    _skell_fit "1787700487"\t"/d"\t"0"\tfish "$cmd" >$SKELL_OUT_DIR/fit-cut-$pad
end

_skell_fit "1787700487"\t"/d"\t"0"\tfish (string repeat -n 400 世) >$SKELL_OUT_DIR/fit-wide

printf done >$SKELL_OUT_DIR/COMPLETE
