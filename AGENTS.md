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

fisher is the only supported fish installer. It copies only a plugin's root
`conf.d/`, `functions/`, `completions/`, and `themes/`. Build `fish/` as the
root of `fish-releases` and put `share/*.awk` under `functions/skell-share`.
`_skell_history` appends `skell-share` to `(status dirname)`. Fish reports
`(status dirname)` as the directory from which it autoloaded the function.
Before `.github/workflows/fish-releases.yml` force-pushes the branch, it runs
`tests/plugin-fish.sh`. The test fails when the build omits an awk script or
uses an awk directory name that differs from the fish sources.

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
  Allow command substitutions around builtins or shell functions when the shell
  evaluates them in-process. Do not use command substitutions around external
  commands.
- Keep shell-specific implementations direct. Do not introduce a shared
  runtime dependency to remove small amounts of duplication.
- Load `zsh/completion.zsh` after `compinit`, and preserve zsh's completers,
  matcher lists, styles, prefixes, suffixes, and quoting rules.
- Start skim from a PSReadLine key handler through
  `System.Diagnostics.Process`. Inherit stderr and keep
  `[Console]::OutputEncoding` set to UTF-8 until the redraw completes. When a
  key handler invokes a native command, the handler's pipeline collects and
  discards every stream. Skim draws its interface on stderr.
- Use GNU awk features deliberately; the project requires `gawk`.
- Keep inline comments only for cross-shell format constraints, shell or OS
  behavior, ordering requirements, and wrong-looking compatibility choices.

## Verification

Run the applicable commands from the repository root. The command patterns
select files by directory and extension. Adding a file under a covered directory
does not require editing this list:

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
fitter's boundaries, each recording hook's output, the files fish loads from
the built plugin, the atuin importer's failure paths, store permissions, and the
PowerShell module's lifecycle. It skips suites for unavailable shells and names
each skipped suite.

No suite drives a real line editor. Bash records under `bash -i`; zsh and fish
are called at the hook boundary with the arguments their editors pass because
the test environment cannot provide a pty on every supported platform.
PowerShell's `Get-History` is empty outside an interactive session, so
`Write-SkellRecord` cannot be driven. The suite covers the store opener and
fitter instead. Exercise a key binding, a widget, or PowerShell's own recording
by hand.

A change to the escape grammar or the record budget belongs in
`tests/lib/vectors.tsv`. Every implementation is measured against this vector
set. A divergent writer fails instead of storing a record another shell cannot
decode.

## Ad hoc shell scripts on Windows

A native Windows binary ignores the MSYS signal that `timeout` sends.
`timeout N script -q -c '…'` therefore does not bound `script` or the processes
it starts. Driving `sk` or an interactive shell through a pty leaves the
wrapper and its children running after the timeout expires, and they accumulate
across a session. End them with `Stop-Process -Id <pid> -Force` from PowerShell;
matching on process name alone would also kill the interactive shells the user
is working in.

MSYS2's zsh and Git-for-Windows Bash run in separate Cygwin runtimes.
`env VAR=x zsh …` reaches zsh with `VAR` unset. A harness that prefixes zsh
with `env VAR=x` tests the real configuration instead of the fixture. Write
test configuration to a file and source it as the session's first command.

The two runtimes resolve `/tmp` differently. Git-for-Windows mounts `/tmp` as
`usertemp` at `%LOCALAPPDATA%\Temp`; MSYS2 roots at `C:/msys64` and has no
`/tmp` entry. The same POSIX path therefore identifies different directories in
the two runtimes. MSYS2 zsh and fish report `No such file or directory` for a
path that Git Bash's `ls` resolves. `TMP` and `TEMP` do not govern the mapping;
the mount in `/etc/fstab` does.

A mixed `C:/...` path from `cygpath -m` does not work for MSYS2 redirection.
MSYS2 fish can stat the path but cannot redirect to it, and reports `Path does
not exist` for a directory that `test -d` accepts. Use a native path for the
fixture: `C:/msys64/tmp` is `/tmp` to MSYS2 zsh and fish,
`/c/msys64/tmp` to the agent's Bash, and `C:/msys64/tmp` to PowerShell. All four
read and write it.

`mount` and the other utilities resolve paths using the invoking runtime.
Running `zsh -c 'mount'` from agent Bash reports Bash's mount table, not
MSYS2's. Read runtime-specific configuration from a shell started by that
runtime.

An MSYS2 shell started by an agent inherits the agent's `PATH`. Git-for-Windows
precedes `/usr/bin` in that path. `mkdir -p /tmp/x` therefore invokes
Git-for-Windows' `mkdir` against Git-for-Windows' `/tmp`; MSYS2 cannot see the
resulting directory. Prepend `/usr/bin:/bin` in the fixture that a zsh or fish
session sources before anything external runs.

A Git-for-Windows clone sets `core.filemode` to false, so git does not record
a new script's executable bit. Invoke a repository script through `bash`.
