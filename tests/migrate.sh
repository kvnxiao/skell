#!/usr/bin/env bash
# Exercise the atuin importer against a stub atuin, including the paths where
# it must leave the target untouched.
# shellcheck source=tests/lib/harness.sh disable=SC2016
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

migrate="$SKELL_REPO_ROOT/share/migrate-atuin.sh"
stub_dir="$SKELL_SANDBOX/bin"
mkdir -p "$stub_dir"

# The stub stands in for atuin so the developer's own history is never read.
cat > "$stub_dir/atuin" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SKELL_STUB_LOG"
case ${SKELL_STUB_MODE:-ok} in
  ok)
    printf '2026-08-01 10:00:00\t/home/u\t0\techo one\0'
    printf '2026-08-02 11:00:00\tC:/Users/u/dev\t1\techo two\0'
    ;;
  midstream)
    printf '2026-08-01 10:00:00\t/home/u\t0\techo one\0'
    exit 1
    ;;
  empty) ;;
  badtime)
    printf 'not-a-timestamp\t/home/u\t0\techo one\0'
    ;;
  isotime)
    printf '2026-08-01T10:00:00\t/home/u\t0\techo one\0'
    printf '2026-08-02T11:00:00\t/home/u\t0\techo two\0'
    ;;
  offsettime)
    printf '2026-01-15 10:00:00 -05:00\t/home/u\t0\techo one\0'
    printf '2026-01-16 11:00:00 -05:00\t/home/u\t0\techo two\0'
    ;;
  outoforder)
    printf '2026-08-09 10:00:00\t/home/u\t0\techo late\0'
    printf '2026-08-01 10:00:00\t/home/u\t0\techo early\0'
    ;;
esac
STUB
chmod +x "$stub_dir/atuin"
export SKELL_STUB_LOG="$SKELL_SANDBOX/stub.log"

run_migrate() {
  : > "$SKELL_STUB_LOG"
  PATH="$stub_dir:$PATH" bash "$migrate" --force "$@" \
    >"$SKELL_SANDBOX/migrate.out" 2>"$SKELL_SANDBOX/migrate.err"
}

target="$SKELL_SANDBOX/store.tsv"

rm -f "$target"
skell_true 'fresh import succeeds' run_migrate --output "$target"
skell_eq 'fresh import writes both records' 2 "$(wc -l < "$target" | tr -d ' ')"
skell_eq 'oldest record is first' 'echo one' "$(gawk -F'\t' -e 'NR==1 {print $5}' "$target")"
skell_eq 'drive letter is folded' '/c/Users/u/dev' "$(gawk -F'\t' -e 'NR==2 {print $2}' "$target")"
skell_eq 'shell field names the importer' atuin "$(gawk -F'\t' -e 'NR==1 {print $4}' "$target")"
skell_eq 'exit status is preserved' 1 "$(gawk -F'\t' -e 'NR==2 {print $3}' "$target")"

skell_true 'reverse order is requested explicitly' \
  grep -q -- '--reverse=true' "$SKELL_STUB_LOG"

skell_false 'second import without --append is refused' run_migrate --output "$target"
skell_eq 'refused import leaves the store alone' 2 "$(wc -l < "$target" | tr -d ' ')"

skell_true 'append succeeds' run_migrate --append --output "$target"
skell_eq 'append adds to the existing records' 4 "$(wc -l < "$target" | tr -d ' ')"

before=$(md5sum < "$target")
SKELL_STUB_MODE=midstream
export SKELL_STUB_MODE
skell_false 'midstream failure is reported' run_migrate --append --output "$target"
skell_eq 'midstream failure leaves the target byte for byte' "$before" "$(md5sum < "$target")"
skell_eq 'midstream failure leaves no staged file' 0 \
  "$(find "$(dirname "$target")" -name 'store.tsv.*' | wc -l | tr -d ' ')"

SKELL_STUB_MODE=ok
skell_true 'retry after failure succeeds' run_migrate --append --output "$target"
skell_eq 'retry does not duplicate a partial prefix' 6 "$(wc -l < "$target" | tr -d ' ')"

SKELL_STUB_MODE=badtime
rm -f "$target.bad"
skell_false 'wholly undateable import is refused' run_migrate --output "$target.bad"
skell_false 'refused undateable import writes no store' test -e "$target.bad"
skell_true 'refused undateable import says why' \
  grep -q 'did not parse' "$SKELL_SANDBOX/migrate.err"

# atuin renders {time} with an ISO separator on some versions and a UTC offset
# on others; both have to convert rather than being skipped.
for mode in isotime offsettime; do
  SKELL_STUB_MODE=$mode
  rm -f "$target.$mode"
  skell_true "$mode import succeeds" run_migrate --output "$target.$mode"
  skell_eq "$mode import writes both records" 2 \
    "$(wc -l < "$target.$mode" | tr -d ' ')"
done

SKELL_STUB_MODE=outoforder
rm -f "$target.ooo"
skell_false 'out-of-order import is refused' run_migrate --output "$target.ooo"
skell_false 'refused import leaves no file behind' test -e "$target.ooo"

unset SKELL_STUB_MODE

skell_false '--output with no path is refused' run_migrate --output
skell_true '--output with no path explains itself' \
  grep -q 'needs a path' "$SKELL_SANDBOX/migrate.err"

skell_eq 'dry run leaves the store alone' 6 "$(wc -l < "$target" | tr -d ' ')"
skell_true 'dry run succeeds' run_migrate --dry-run --output "$target"
skell_eq 'dry run still leaves the store alone' 6 "$(wc -l < "$target" | tr -d ' ')"
skell_true 'dry run reports what it would write' \
  grep -q 'records would be written' "$SKELL_SANDBOX/migrate.out"

skell_true '--help succeeds' env PATH="$stub_dir:$PATH" bash "$migrate" --help >/dev/null
skell_report
