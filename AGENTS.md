# Repository guidelines

## Purpose

Skell records one command history for bash, fish, PowerShell, and zsh. The
shell hooks append to the shared TSV store without spawning a process. Search
and zsh completion may invoke `sk`, `gawk`, `lsd`, or `ls`.

Treat the store format and shell hooks as one cross-shell interface. A format
change must update every writer, decoder, preview script, migration script,
and the README in the same change.

## Layout

- `bash/skell.bash`, `fish/conf.d/skell.fish`, `fish/functions/`,
  `powershell/Skell.psm1`, and `zsh/init.zsh` record and search history.
- `zsh/completion.zsh` captures zsh completion matches and presents them
  through skim.
- `share/rank.awk` ranks distinct commands by frecency.
- `share/preview-*.awk` render skim previews.
- `share/migrate-atuin.sh` and `share/migrate-atuin.awk` import atuin history.
- `share/build-fish-plugin.sh` assembles the `fish-releases` branch.

## fish plugin branch

fisher is the only supported fish install. It copies only a plugin's root
`conf.d/`, `functions/`, `completions/`, and `themes/`, so the build makes
`fish/` the root of `fish-releases` and puts `share/*.awk` under
`functions/skell-share`. `_skell_history` appends `skell-share` to
`(status dirname)`, which fish reports as the directory it autoloaded the
function from. Before `.github/workflows/fish-releases.yml` force-pushes the
branch, it runs `tests/plugin-fish.sh`, which fails when the build omits an awk
script or spells the awk directory differently from the fish sources.

## Store contract

- Write `epoch`, `directory`, `exit status`, `shell`, and `command` as
  tab-separated fields in that order.
- Escape backslashes before newlines, tabs, and carriage returns. Decode the
  doubled backslashes before the other escape sequences.
- Keep the encoded record at or below 1000 bytes before its final newline, and
  append the record with one write. Treat limit changes as concurrency-sensitive
  and document their platform and filesystem assumptions.
- Preserve duplicate commands because each occurrence contributes to
  frecency.
- Exclude commands whose typed form starts with a space.
- Preserve the command's exit status across prompt hooks.
- Use a temporary `SKELL_DATA_DIR` and `SKELL_HISTORY` in tests. Never read or
  write the developer's live history store.

## Implementation rules

- Keep recording hooks fork-free. No external utility runs on the prompt path.
  A command substitution around a builtin or a shell function is fine where the
  shell evaluates it in-process, as fish does; one around an external command is
  not.
- Keep shell-specific implementations direct. Do not introduce a shared
  runtime dependency to remove small amounts of duplication.
- Load `zsh/completion.zsh` after `compinit`, and preserve zsh's completers,
  matcher lists, styles, prefixes, suffixes, and quoting rules.
- Use GNU awk features deliberately; the project requires `gawk`.
- Keep inline comments only for cross-shell format constraints, shell or OS
  behavior, ordering requirements, and wrong-looking compatibility choices.

## Verification

Run the applicable commands from the repository root. Each command selects by
directory and extension, so adding a file under a covered directory does not
require editing this list:

```sh
bash -n bash/*.bash share/*.sh tests/*.sh tests/lib/*.sh
shellcheck --severity=style bash/*.bash share/*.sh tests/*.sh tests/lib/*.sh
fish -n fish/conf.d/*.fish fish/functions/*.fish tests/lib/*.fish
fish_indent --check fish/conf.d/*.fish fish/functions/*.fish tests/lib/*.fish
zsh -n zsh/*.zsh tests/lib/*.zsh
pwsh -NoLogo -NoProfile -Command '$findings = @(Invoke-ScriptAnalyzer -Path powershell -Recurse -Settings PSScriptAnalyzerSettings.psd1 -Severity Error,Warning,Information); $findings | Format-Table -Wrap; $blocking = @($findings | Where-Object Severity -In "Error","Warning"); if ($blocking.Count) { exit 1 }'
for script in share/*.awk; do gawk -f "$script" </dev/null >/dev/null; done
bash tests/run-all.sh
```

`tests/run-all.sh` covers the codec in all five implementations, the record
fitter's boundaries, what each recording hook writes, what fish loads from the
built plugin, the atuin importer's failure paths, store permissions, and the
PowerShell module's lifecycle. It skips a suite whose shell the machine lacks
and names what it skipped.

No suite drives a real line editor. bash records under `bash -i`, so its
records come from readline; zsh and fish are called at the hook boundary with
the arguments their editors pass, because no pty is available on every
supported platform. PowerShell's `Get-History` is empty outside an interactive
session, so `Write-SkellRecord` cannot be driven; the suite covers the store
opener and the fitter instead. Exercise a key binding, a widget, or
PowerShell's own recording by hand.

A change to the escape grammar or the record budget belongs in
`tests/lib/vectors.tsv`. Every implementation is measured against it, so a
writer that diverges fails rather than silently storing something another shell
cannot read back.

## Ad hoc shell scripts on Windows

A native Windows binary ignores the MSYS signal that `timeout` sends, so
`timeout N script -q -c '…'` bounds nothing that `script` starts. Driving `sk`
or an interactive shell through a pty that way leaves the wrapper and its
children spinning on CPU long after the timeout expires, and they accumulate
across a session. End them with `Stop-Process -Id <pid> -Force` from
PowerShell; matching on process name alone would also kill the interactive
shells the user is working in.

MSYS2's zsh and the Git-for-Windows bash that an agent runs are separate Cygwin
runtimes, so `env VAR=x zsh …` reaches zsh with `VAR` unset. A harness that
sets `ZDOTDIR` this way silently tests the real config instead of the fixture.
Write test configuration to a file and source it as the first line of the
session.

The two runtimes also resolve `/tmp` differently. Git-for-Windows mounts it
`usertemp` at `%LOCALAPPDATA%\Temp`, while MSYS2 roots at `C:/msys64` and has
no `/tmp` entry, so the same POSIX path names two different directories: MSYS2
zsh and fish report `No such file or directory` for a path `ls` resolves in
bash. `TMP` and `TEMP` do not govern the mapping; the mount in `/etc/fstab`
does.

The mixed `C:/...` form that `cygpath -m` prints is not a way around the split.
MSYS2 fish stats a mixed path but cannot redirect to one, and fails with `Path
does not exist` on a directory it will happily `test -d`. Instead, put the
fixture where every runtime addresses it natively: `C:/msys64/tmp` is `/tmp` to
MSYS2 zsh and fish, `/c/msys64/tmp` to the agent's bash, and `C:/msys64/tmp` to
PowerShell. All four read and write it.

`mount` and the other utilities resolve per runtime as well, so
`zsh -c 'mount'` run from an agent bash reports bash's table rather than
MSYS2's. Read a runtime's own configuration only from a shell that runtime
started.

An MSYS2 shell that an agent starts also inherits the agent's `PATH`, which puts
Git-for-Windows ahead of `/usr/bin`. `mkdir -p /tmp/x` then runs
Git-for-Windows' `mkdir` against Git-for-Windows' `/tmp`, so the directory
appears somewhere the MSYS2 shell cannot see and the shell reports it missing.
Prepend `/usr/bin:/bin` in the fixture that a zsh or fish session sources
before anything external runs.

A Git-for-Windows clone sets `core.filemode` to false, so git does not record
a new script's executable bit. Invoke a repository script through `bash`.
