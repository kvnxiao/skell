#!/usr/bin/env bash
# bash records through real interactive history. A PTY is not available on
# every platform. The zsh and fish fixtures call hook boundaries. Test key
# bindings by hand.
# shellcheck source=tests/lib/harness.sh disable=SC2016
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

col() { gawk -F'\t' -v r="$1" -v c="$2" -e 'NR == r { print $c }' "$3"; }

assert_store() {
  local label=$1 store=$2 want=$3 lines
  lines=$(wc -l < "$store" | tr -d ' ')
  skell_eq "$label: record count" "$want" "$lines"
  local bad
  bad=$(gawk -F'\t' -e 'NF != 5 { n++ } END { print n + 0 }' "$store")
  skell_eq "$label: every record holds five fields" 0 "$bad"
  bad=$(LC_ALL=C gawk -e 'length($0) > 1000 { n++ } END { print n + 0 }' "$store")
  skell_eq "$label: every record fits the budget" 0 "$bad"
}

bash_store="$SKELL_SANDBOX/bash.tsv"
bash_data="$SKELL_SANDBOX/bash-data"
bash_exit_marker="$SKELL_SANDBOX/bash-exit-trap"
mkdir -p "$bash_data"
cat > "$SKELL_SANDBOX/rc.bash" <<RCEOF
SKELL_ROOT=$SKELL_REPO_ROOT
SKELL_DATA_DIR=$bash_data
SKELL_HISTORY=$bash_store
trap 'printf preserved > "$bash_exit_marker"' EXIT
. "\$SKELL_ROOT/bash/skell.bash"
RCEOF

# skell needs bash 5.0 for EPOCHSECONDS; macOS ships 3.2.
bash_major=$(bash -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null)
if [ "${bash_major:-0}" -lt 5 ]; then
  printf '%s: bash %s predates EPOCHSECONDS; bash assertions skipped\n' \
    "$skell_name" "$(bash -c 'echo "$BASH_VERSION"' 2>/dev/null)"
else
  # Isolate HISTFILE to start the shell with an empty history list.
  printf '%s\n' \
    'true' \
    ' echo excluded' \
    '(exit 7)' \
    'printf %s hello' \
    | HISTFILE="$SKELL_SANDBOX/bash.hist" \
      bash --noprofile --rcfile "$SKELL_SANDBOX/rc.bash" -i >/dev/null 2>&1

  assert_store 'bash' "$bash_store" 3
  skell_eq 'bash records the shell name' bash "$(col 1 4 "$bash_store")"
  skell_eq 'bash records the first command' 'true' "$(col 1 5 "$bash_store")"
  skell_eq 'bash preserves a failing exit status' 7 "$(col 2 3 "$bash_store")"
  skell_eq 'bash records the command after the failure' 'printf %s hello' \
    "$(col 3 5 "$bash_store")"
  skell_false 'bash excludes the leading-space command' grep -q 'excluded' "$bash_store"
  skell_eq 'bash records an absolute directory' 1 \
    "$(gawk -F'\t' -e 'NR == 1 && $2 ~ /^(\/|[A-Za-z]:)/ { print 1 }' "$bash_store")"
  skell_eq 'bash preserves an existing EXIT trap' preserved "$(skell_slurp "$bash_exit_marker")"
  skell_false 'bash clears command text from its scratch file' \
    gawk 'length($0) { found=1 } END { exit !found }' "$bash_data"/scratch-bash-*.hist
fi

zsh_store="$SKELL_SANDBOX/zsh.tsv"
{
  printf 'export PATH=/usr/bin:/bin:$PATH\n'
  printf 'export SKELL_ROOT=%s\n' "$SKELL_REPO_WIN"
  printf 'export SKELL_DATA_DIR=%s/zsh-data\n' "$SKELL_SANDBOX_MSYS"
  printf 'export SKELL_HISTORY=%s/zsh.tsv\n' "$SKELL_SANDBOX_MSYS"
  printf 'source %s/zsh/init.zsh\n' "$SKELL_REPO_WIN"
  # preexec receives the line as typed; precmd reads $? from the command.
  printf '_skell_preexec "true"\n(exit 0)\n_skell_precmd\n'
  printf '_skell_preexec " echo excluded"\n(exit 0)\n_skell_precmd\n'
  printf '_skell_preexec "false"\n(exit 7)\n_skell_precmd\n'
  printf 'exit 0\n'
} > "$SKELL_SANDBOX/rec.zsh"
printf 'source %s/rec.zsh\n' "$SKELL_SANDBOX_MSYS" | zsh -f -i >/dev/null 2>&1

if command -v zsh >/dev/null 2>&1; then
  assert_store 'zsh' "$zsh_store" 2
  skell_eq 'zsh records the shell name' zsh "$(col 1 4 "$zsh_store")"
  skell_eq 'zsh records the first command' 'true' "$(col 1 5 "$zsh_store")"
  skell_eq 'zsh preserves a failing exit status' 7 "$(col 2 3 "$zsh_store")"
  skell_false 'zsh excludes the leading-space command' grep -q 'excluded' "$zsh_store"
fi

fish_store="$SKELL_SANDBOX/fish.tsv"
{
  printf 'set -gx PATH /usr/bin /bin $PATH\n'
  printf 'set -gx SKELL_DATA_DIR %s/fish-data\n' "$SKELL_SANDBOX_MSYS"
  printf 'set -gx SKELL_HISTORY %s/fish.tsv\n' "$SKELL_SANDBOX_MSYS"
  printf 'set -p fish_function_path %s/fish/functions\n' "$SKELL_REPO_WIN"
  printf 'source %s/fish/conf.d/skell.fish\n' "$SKELL_REPO_WIN"
  # fish_postexec passes the hook the line as typed; $status carries the result.
  printf 'true\n_skell_record "true"\n'
  printf 'true\n_skell_record " echo excluded"\n'
  printf 'true\n_skell_record ""\n'
  printf 'sh -c "exit 7"\n_skell_record "sh -c false"\n'
} > "$SKELL_SANDBOX/rec.fish"
printf 'source %s/rec.fish\nexit\n' "$SKELL_SANDBOX_MSYS" | fish --no-config -i >/dev/null 2>&1

if command -v fish >/dev/null 2>&1; then
  assert_store 'fish' "$fish_store" 2
  skell_eq 'fish records the shell name' fish "$(col 1 4 "$fish_store")"
  skell_eq 'fish records the first command' 'true' "$(col 1 5 "$fish_store")"
  skell_eq 'fish preserves a failing exit status' 7 "$(col 2 3 "$fish_store")"
  skell_false 'fish excludes the leading-space command' grep -q 'excluded' "$fish_store"
  now=$(date +%s)
  stamp=$(col 1 1 "$fish_store")
  if [ -n "$stamp" ] && [ "$stamp" -gt $((now - 120)) ] && [ "$stamp" -le $((now + 120)) ]; then
    skell_ok 'fish stamps the current epoch'
  else
    skell_not_ok "fish stamps the current epoch (got $stamp, now $now)"
  fi
fi

if command -v pwsh >/dev/null 2>&1; then
  pwsh_store="$SKELL_SANDBOX_WIN/pwsh.tsv"
  # Get-History is empty under -Command. Write through the store opener to test
  # append and field layout; this does not test history-entry reads.
  pwsh -NoLogo -NoProfile -Command "
    \$env:SKELL_DATA_DIR = '$SKELL_SANDBOX_WIN/pwsh-data'
    \$env:SKELL_HISTORY = '$pwsh_store'
    Import-Module '$SKELL_REPO_WIN/powershell/Skell.psm1' -Force
    \$record = Get-SkellFittedRecord ('1787700487' + [char]9 + '/d' + [char]9 + '0' + [char]9 + 'pwsh') 'git status'
    \$stream = & (Get-Module Skell) { \${function:Open-SkellStore} }
    \$s = & \$stream
    try {
      \$bytes = [System.Text.Encoding]::UTF8.GetBytes(\$record + \"\`n\")
      \$s.Write(\$bytes, 0, \$bytes.Length)
    } finally { \$s.Dispose() }
  " >/dev/null 2>&1
  pwsh_local="$SKELL_SANDBOX/pwsh.tsv"
  if [ -s "$pwsh_local" ]; then
    assert_store 'pwsh' "$pwsh_local" 1
    skell_eq 'pwsh appends through the store opener' 'git status' "$(col 1 5 "$pwsh_local")"
  else
    skell_not_ok 'pwsh appends through the store opener'
  fi
fi

skell_report
