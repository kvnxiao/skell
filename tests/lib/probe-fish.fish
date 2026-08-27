# Exercise fish's codec against the vector specs. A generated prelude sets
# fish_function_path, SKELL_VECTORS_TSV, and SKELL_OUT_DIR in MSYS2's own
# spelling and sources this file, because the environment that an agent's bash
# sets does not reach an MSYS2 fish.
#
# Each vector is rebuilt here from the %XX spec rather than carried in, because
# neither transport across the runtime boundary is lossless: MSYS2 rewrites a
# CRLF byte pair on a file read and re-parses backslashes out of a command line
# that a Git-for-Windows bash built. The spec holds nothing above 0x7F, so the
# bytes are reconstructed without needing the file's encoding. Nothing on the
# recording path reads a command from a file, so this constrains the harness
# alone.

# The whole spec is converted at once rather than byte by byte: `string collect`
# strips a lone newline, so a per-byte loop loses the 0x0A vector entirely. The
# guard bytes stay on the returned value, or a vector ending in a newline would
# reach the function under test already truncated.
function _probe_unhex -a spec
    set -l bs \x5c
    printf '%b' (string replace -a '%' $bs"x" "X$spec"X | string collect --allow-empty)
end

# The guards are never removed here. Escaping and decoding both leave an `X`
# alone, so the guarded value round-trips to the guarded expectation, and the
# driver compares against expectations it bracketed the same way. Stripping
# inside fish would mean emitting an unguarded trailing newline, which every
# `string` call and command substitution trims.

for line in (cat $SKELL_VECTORS_TSV)
    string match -q '#*' -- $line; and continue
    set -l f (string split -m 2 \t -- $line)
    test (count $f) -ge 3; or continue
    set -l name $f[1]
    set -l raw (_probe_unhex "$f[2]" | string collect --allow-empty --no-trim-newlines)
    set -l enc (_probe_unhex "$f[3]" | string collect --allow-empty --no-trim-newlines)

    # Both functions print a trailing newline that `string collect` strips, so
    # the result is re-emitted with printf rather than redirected straight out.
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
