#!/usr/bin/env bash
# Assemble skell's fisher-installable layout in the directory named by $1.
#
# fisher installs only a plugin's root conf.d, functions, completions, and
# themes, so the awk scripts go under functions/skell-share, which fisher
# copies whole and fish does not autoload from.

set -euo pipefail

repo=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
out=${1:?usage: build-fish-plugin.sh <directory>}

if [ -e "$out" ] && [ -n "$(ls -A -- "$out")" ]; then
  printf 'build-fish-plugin: %s is not empty\n' "$out" >&2
  exit 1
fi

# A half-written tree would fail the non-empty check on the next run.
trap 'rm -rf -- "$out"' ERR

mkdir -p "$out/conf.d" "$out/functions/skell-share"
cp -- "$repo"/fish/conf.d/*.fish "$out/conf.d/"
cp -- "$repo"/fish/functions/*.fish "$out/functions/"
cp -- "$repo"/share/*.awk "$out/functions/skell-share/"
cp -- "$repo/LICENSE" "$out/LICENSE"

cat > "$out/README.md" <<'EOF'
# skell for fish

One command history for bash, fish, PowerShell, and zsh. This branch is built
from [kvnxiao/skell](https://github.com/kvnxiao/skell); open issues and pull
requests against `main`.

```fish
fisher install kvnxiao/skell@fish-releases
```

skell needs [skim](https://github.com/skim-rs/skim) and `gawk` on `PATH`.
`ctrl-r` searches the store, which every skell shell shares.
EOF
