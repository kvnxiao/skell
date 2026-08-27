#!/usr/bin/env bash
# Check that each shell creates the store where only its owner can read it.
#
# A POSIX mode is only meaningful where the filesystem honours it. Cygwin and
# MSYS2 mount NTFS with `noacl`, which discards the umask entirely: a probe
# created under `umask 077` is 755. The mode assertions therefore run only where
# a probe proves they apply, and the Windows store is covered by the ACL the
# PowerShell module sets instead.
# shellcheck source=tests/lib/harness.sh disable=SC2016
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

probe_dir="$SKELL_SANDBOX/probe"
(umask 077; mkdir -p "$probe_dir"; : > "$probe_dir/file")
honours_umask=0
if [ "$(stat -c '%a' "$probe_dir" 2>/dev/null)" = 700 ] \
  && [ "$(stat -c '%a' "$probe_dir/file" 2>/dev/null)" = 600 ]; then
  honours_umask=1
fi

if [ "$honours_umask" -eq 0 ]; then
  printf '%s: filesystem discards the umask; mode assertions skipped\n' "$skell_name"
fi

assert_private() {
  local label=$1 dir=$2 file=$3
  if [ "$honours_umask" -eq 0 ]; then
    return 0
  fi
  skell_eq "$label: directory is 700" 700 "$(stat -c '%a' "$dir")"
  skell_eq "$label: store is 600" 600 "$(stat -c '%a' "$file")"
}

# Each shell is started against a store directory that does not exist yet, so
# the assertions cover the path that creates it.
run_shell() {
  local name=$1 data="$SKELL_SANDBOX/$1"
  rm -rf -- "$data"
  case $name in
    bash)
      SKELL_DATA_DIR="$data" SKELL_HISTORY="$data/history.tsv" \
        HISTFILE="$SKELL_SANDBOX/histfile" SKELL_ROOT="$SKELL_REPO_ROOT" \
        bash --noprofile --norc -i -c ". \"\$SKELL_ROOT/bash/skell.bash\"" >/dev/null 2>&1
      ;;
    zsh)
      {
        # An MSYS2 shell that an agent starts inherits the agent's PATH, which
        # resolves mkdir to Git-for-Windows and its own /tmp.
        printf 'export PATH=/usr/bin:/bin:$PATH\n'
        printf 'export SKELL_ROOT=%s\n' "$SKELL_REPO_WIN"
        printf 'export SKELL_DATA_DIR=%s/zsh\n' "$SKELL_SANDBOX_MSYS"
        printf 'export SKELL_HISTORY=%s/zsh/history.tsv\n' "$SKELL_SANDBOX_MSYS"
        printf 'source %s/zsh/init.zsh\n' "$SKELL_REPO_WIN"
        printf 'exit 0\n'
      } > "$SKELL_SANDBOX/perm.zsh"
      printf 'source %s/perm.zsh\n' "$SKELL_SANDBOX_MSYS" | zsh -f -i >/dev/null 2>&1
      ;;
    fish)
      {
        printf 'set -gx PATH /usr/bin /bin $PATH\n'
        printf 'set -gx SKELL_DATA_DIR %s/fish\n' "$SKELL_SANDBOX_MSYS"
        printf 'set -gx SKELL_HISTORY %s/fish/history.tsv\n' "$SKELL_SANDBOX_MSYS"
        printf 'set -p fish_function_path %s/fish/functions\n' "$SKELL_REPO_WIN"
        printf 'source %s/fish/conf.d/skell.fish\n' "$SKELL_REPO_WIN"
      } > "$SKELL_SANDBOX/perm.fish"
      # fish/conf.d/skell.fish returns early in a non-interactive shell, so an
      # interactive fish sources the fixture to reach the store-creation block.
      printf 'source %s/perm.fish\nexit\n' "$SKELL_SANDBOX_MSYS" | fish --no-config -i >/dev/null 2>&1
      ;;
  esac
}

for shell in bash zsh fish; do
  if ! command -v "$shell" >/dev/null 2>&1; then
    printf '%s: no %s on this machine; skipped\n' "$skell_name" "$shell"
    continue
  fi
  run_shell "$shell"
  data="$SKELL_SANDBOX/$shell"
  skell_true "$shell creates the data directory" test -d "$data"
  skell_true "$shell creates the store" test -e "$data/history.tsv"
  assert_private "$shell" "$data" "$data/history.tsv"
done

# On Windows the module replaces the inherited descriptor with a single entry
# for the current account, a protection the umask cannot provide. On Linux and
# macOS it sets the mode the POSIX shells set; README promises that branch, so
# it is measured rather than skipped.
if command -v pwsh >/dev/null 2>&1; then
  rm -rf -- "$SKELL_SANDBOX/pwsh"
  result=$(SKELL_DATA_DIR="$SKELL_SANDBOX_WIN/pwsh" \
    SKELL_HISTORY="$SKELL_SANDBOX_WIN/pwsh/history.tsv" \
    pwsh -NoLogo -NoProfile -Command "
      Import-Module '$SKELL_REPO_WIN/powershell/Skell.psm1' -Force
      if (\$IsWindows) {
        \$acl = Get-Acl \$env:SKELL_HISTORY
        'acl:{0}/{1}' -f @(\$acl.Access).Count, @(\$acl.Access | Where-Object IsInherited).Count
      } else {
        # UnixFileMode is a flags enum, and its name order is not contract.
        \$octal = { param(\$p) [Convert]::ToString([int](Get-Item \$p).UnixFileMode, 8) }
        'mode:{0}/{1}' -f (& \$octal \$env:SKELL_DATA_DIR), (& \$octal \$env:SKELL_HISTORY)
      }
    " 2>/dev/null | tr -d '\r')
  case $result in
    'acl:1/0')
      skell_ok 'pwsh store carries one uninherited entry' ;;
    'mode:700/600')
      skell_ok 'pwsh store is 0700 over 0600' ;;
    acl:*)
      skell_not_ok "pwsh store carries one uninherited entry (got $result)" ;;
    mode:*)
      skell_not_ok "pwsh store is 0700 over 0600 (got $result)" ;;
    *)
      skell_not_ok "pwsh permission check produced no verdict (got '$result')" ;;
  esac
fi

skell_report
