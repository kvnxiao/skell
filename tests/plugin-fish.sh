#!/usr/bin/env bash
# fisher installs the generated tree instead of this clone. Test that tree.
# conf.d/skell.fish returns in a non-interactive shell. Run the probe
# interactively.
# shellcheck source=tests/lib/harness.sh disable=SC2016
. "$(dirname -- "${BASH_SOURCE[0]}")/lib/harness.sh"

out="$SKELL_SANDBOX/out"
mkdir -p "$out"

plugin="$SKELL_SANDBOX/plugin"
skell_true 'the plugin build succeeds' \
  bash "$SKELL_REPO_ROOT/share/build-fish-plugin.sh" "$plugin"

for source in "$SKELL_REPO_ROOT"/fish/functions/*.fish; do
  name=$(basename -- "$source")
  skell_true "the plugin contains $name" test -f "$plugin/functions/$name"
done

# The widget appends this directory name to its load path. Use the same name for
# the build's awk directory.
awk_subdir=$(grep -ho -e '(status dirname)/[A-Za-z0-9._-]*' \
  "$SKELL_REPO_ROOT"/fish/functions/*.fish | sed -e 's#.*/##' | sort -u)
skell_eq 'the fish sources derive one awk directory' 1 \
  "$(printf '%s\n' "$awk_subdir" | grep -c .)"

# An omitted awk script breaks Ctrl+R only in the installed plugin. No other
# suite tests that package boundary.
refs=$(grep -ho -e '\$awk_dir/[A-Za-z0-9._-]*\.awk' \
  "$SKELL_REPO_ROOT"/fish/conf.d/*.fish "$SKELL_REPO_ROOT"/fish/functions/*.fish |
  sed -e 's#.*/##' | sort -u)
skell_true 'the fish sources reference at least one awk script' test -n "$refs"
while read -r name; do
  [ -n "$name" ] || continue
  skell_true "the plugin contains $name" \
    test -f "$plugin/functions/$awk_subdir/$name"
done <<< "$refs"

# The widget derives its awk directory from the function's load path. Prevent
# the clone's share/ directory from replacing the installed copy.
skell_false 'no fish source reads skell_root or skell_share' \
  grep -riq -e 'skell_root' -e 'skell_share' "$SKELL_REPO_ROOT/fish"

{
  # The inherited PATH resolves coreutils and /tmp through Git for Windows.
  # Prepend MSYS2 tools.
  printf 'set -gx PATH /usr/bin /bin $PATH\n'
  printf 'set -gx SKELL_DATA_DIR %s/data\n' "$SKELL_SANDBOX_MSYS"
  printf 'set -gx SKELL_HISTORY %s/data/history.tsv\n' "$SKELL_SANDBOX_MSYS"
  # fisher puts its install root on fish_function_path; the build does not.
  printf 'set -p fish_function_path %s/plugin/functions\n' "$SKELL_SANDBOX_MSYS"
  printf 'source %s/plugin/conf.d/skell.fish\n' "$SKELL_SANDBOX_MSYS"
  printf 'functions -q _skell_history; and echo yes >%s/out/widget\n' \
    "$SKELL_SANDBOX_MSYS"
  printf 'functions -q _skell_escape; and echo yes >%s/out/codec\n' \
    "$SKELL_SANDBOX_MSYS"
  printf 'bind ctrl-r >%s/out/bind\n' "$SKELL_SANDBOX_MSYS"
  printf 'echo (functions --details _skell_history | path dirname) >%s/out/fndir\n' \
    "$SKELL_SANDBOX_MSYS"
} > "$SKELL_SANDBOX/probe.fish"
printf 'source %s/probe.fish\nexit\n' "$SKELL_SANDBOX_MSYS" |
  fish --no-config -i >"$SKELL_SANDBOX/probe.log" 2>&1

if [ -f "$out/fndir" ]; then
  skell_ok 'the probe ran to completion'
else
  cat -- "$SKELL_SANDBOX/probe.log" >&2
  skell_not_ok 'the probe ran to completion'
fi

skell_eq 'the plugin autoloads the widget' yes "$(cat -- "$out/widget" 2>/dev/null)"
skell_eq 'the plugin autoloads the codec' yes "$(cat -- "$out/codec" 2>/dev/null)"
skell_true 'the plugin binds ctrl-r to the widget' \
  grep -q '_skell_history' "$out/bind"
skell_eq 'the widget loads from the plugin functions directory' \
  "$SKELL_SANDBOX_MSYS/plugin/functions" "$(cat -- "$out/fndir" 2>/dev/null)"

skell_report
