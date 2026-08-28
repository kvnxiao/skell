#!/usr/bin/env bash
# Build skell's fisher plugin tree in $1.
#
# fisher copies only root conf.d, functions, completions, and themes
# directories. Store the awk scripts under functions/skell-share; fish does
# not autoload that subdirectory.

set -euo pipefail

repo=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
out=${1:?usage: build-fish-plugin.sh <directory>}

if [ -e "$out" ] && [ -n "$(ls -A -- "$out")" ]; then
  printf 'build-fish-plugin: %s is not empty\n' "$out" >&2
  exit 1
fi

# Remove partial output to let retries pass the non-empty check.
trap 'rm -rf -- "$out"' ERR

mkdir -p "$out/conf.d" "$out/functions/skell-share"
cp -- "$repo"/fish/conf.d/*.fish "$out/conf.d/"
cp -- "$repo"/fish/functions/*.fish "$out/functions/"
cp -- "$repo"/share/*.awk "$out/functions/skell-share/"
cp -- "$repo/LICENSE" "$out/LICENSE"

cat > "$out/README.md" <<'EOF'
# skell for fish

One command history for bash, fish, PowerShell, and zsh. This branch is built
from [kvnxiao/skell](https://github.com/kvnxiao/skell). Open issues and pull
requests against `main`.

```fish
fisher install kvnxiao/skell@fish-releases
```

Skell needs [skim](https://github.com/skim-rs/skim) and `gawk` on `PATH`.
`Ctrl+R` searches the store shared by every skell shell.
EOF
