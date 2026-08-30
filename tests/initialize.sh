#!/usr/bin/env bash
# shellcheck source=tests/lib/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

store=$SKELL_SANDBOX/initialize.tsv
expected=$SKELL_SANDBOX/initialize.expected
data=$SKELL_SANDBOX/initialize-data
fixture=$SKELL_SANDBOX/initialize.bash
mkdir -p "$data"

cat > "$fixture" <<'FIXTURE'
PS1=x
set -T
_skell_creation_barrier() {
  case $BASH_COMMAND in
    ': > "$SKELL_HISTORY"'|': >> "$SKELL_HISTORY"')
      printf ready > "$SKELL_READY"
      while [ ! -e "$SKELL_GO" ]; do :; done
      ;;
  esac
}
trap _skell_creation_barrier DEBUG
. "$SKELL_ROOT/bash/skell.bash"
trap - DEBUG
FIXTURE

SKELL_DATA_DIR=$data SKELL_HISTORY=$store SKELL_READY=$SKELL_SANDBOX/ready-1 \
  SKELL_GO=$SKELL_SANDBOX/go-1 bash --noprofile --norc -i "$fixture" \
  >/dev/null 2>&1 &
first_pid=$!
SKELL_DATA_DIR=$data SKELL_HISTORY=$store SKELL_READY=$SKELL_SANDBOX/ready-2 \
  SKELL_GO=$SKELL_SANDBOX/go-2 bash --noprofile --norc -i "$fixture" \
  >/dev/null 2>&1 &
second_pid=$!

ready=0
for _ in {1..500}; do
  if [ -e "$SKELL_SANDBOX/ready-1" ] && [ -e "$SKELL_SANDBOX/ready-2" ]; then
    ready=1
    break
  fi
  sleep 0.01
done

if [ "$ready" -eq 0 ]; then
  kill "$first_pid" "$second_pid" 2>/dev/null || true
  wait "$first_pid" "$second_pid" 2>/dev/null || true
  skell_not_ok 'concurrent Bash initializers reached the store creation boundary'
  skell_report
  exit
fi

printf 'preserved\n' > "$expected"
printf 'preserved\n' > "$store"
: > "$SKELL_SANDBOX/go-1"
: > "$SKELL_SANDBOX/go-2"
wait "$first_pid"
wait "$second_pid"

skell_eq_file 'concurrent Bash initialization does not truncate the store' \
  "$expected" "$store"
skell_report
