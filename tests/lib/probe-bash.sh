# shellcheck shell=bash
# Exercise bash's codec against the vector files. Run under `bash -i` with
# SKELL_VECTORS_DIR and SKELL_OUT_DIR set; each result is written to a file so
# the driver compares bytes rather than terminal output.

. "$SKELL_ROOT/bash/skell.bash"
# This probe measures the codec alone, so the recording hook is unhooked to
# keep the driver's own commands out of the store.
PROMPT_COMMAND=

slurp() {
  _skell_slurped=
  IFS= read -r -d '' _skell_slurped < "$1"
  return 0
}

while IFS= read -r name; do
  [ -n "$name" ] || continue
  _skell_reply=
  slurp "$SKELL_VECTORS_DIR/$name.raw"
  _skell_escape "$_skell_slurped"
  printf '%s' "$_skell_reply" > "$SKELL_OUT_DIR/$name.enc.out"

  _skell_reply=
  slurp "$SKELL_VECTORS_DIR/$name.enc"
  _skell_unescape "$_skell_slurped"
  printf '%s' "$_skell_reply" > "$SKELL_OUT_DIR/$name.dec.out"
done < "$SKELL_VECTORS_DIR/INDEX"

_skell_fit "1787700487"$'\t'"/d"$'\t'"0"$'\t'bash 'git status'
printf '%s' "$_skell_reply" > "$SKELL_OUT_DIR/fit-short"

printf -v _skell_longdir '/%.0sd' {1..1200}
_skell_fit "1787700487"$'\t'"$_skell_longdir"$'\t'"0"$'\t'bash 'git status'
printf '%s' "$_skell_reply" > "$SKELL_OUT_DIR/fit-longdir"

for pad in 0 1 2 3; do
  _skell_cmd=
  for ((i = 0; i < 980 + pad; i++)); do _skell_cmd+=x; done
  # shellcheck disable=SC1003  # eight literal backslashes straddle the cut
  _skell_cmd+='\\\\\\\\\\\\\\\\'
  _skell_fit "1787700487"$'\t'"/d"$'\t'"0"$'\t'bash "$_skell_cmd"
  printf '%s' "$_skell_reply" > "$SKELL_OUT_DIR/fit-cut-$pad"
done

_skell_wide=
for ((i = 0; i < 400; i++)); do _skell_wide+=世; done
_skell_fit "1787700487"$'\t'"/d"$'\t'"0"$'\t'bash "$_skell_wide"
printf '%s' "$_skell_reply" > "$SKELL_OUT_DIR/fit-wide"

printf 'done' > "$SKELL_OUT_DIR/COMPLETE"
