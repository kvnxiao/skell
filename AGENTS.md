# Repository guidelines

## Purpose

Skell records one command history for bash, fish, PowerShell, and zsh, searches
it with skim, and replaces each shell's `Tab` completion menu with skim. The
shell hooks append to a shared TSV store without spawning a process. History
search and the completion menus may run `sk`, `gawk`, `eza`, `lsd`, `ls`, or
`dir`.

Treat the store format and the shell hooks as one cross-shell interface. A
format change updates every writer, decoder, preview script, and the README in
the same change.

Skell needs bash 5.1, fish 4.0, and PowerShell 7.4 on Windows, Linux, and
macOS. Bash 5.1 keeps `HISTCMD` current inside `PROMPT_COMMAND`, which the
recording hook compares to detect a new command; bash 5.0 reports 1 there.
Bash 5.0 supplies `EPOCHSECONDS`, `complete -I`, and a `READLINE_POINT`
counted in characters. Do not add version branches for older bash.

## Layout

Each shell has one entry point that records and searches history:

- `bash/skell.bash`
- `fish/conf.d/skell.fish` and `fish/functions/`
- `powershell/Skell.psm1`
- `zsh/init.zsh`

Each shell presents its own completion matches through skim:

- `bash/completion.bash` wraps each compspec to record readline's matches
  during a `Tab` macro.
- `fish/functions/_skell_complete*.fish`, `_skell_commandline.fish`,
  `_skell_unclosed_quote.fish`, and `_skell_visible.fish` present fish's
  `complete -C` matches. `_skell_skim` runs skim for fish history search and
  completion.
- `Invoke-SkellComplete` in `powershell/Skell.psm1` presents `TabExpansion2`
  matches.
- `zsh/completion.zsh` captures zsh's `compadd` matches.

Each shell checks for `sk` and `gawk` once per session with `_skell_ready`
(bash, fish, zsh) or `Test-SkellReady` (PowerShell). `_skell_scratch` (fish,
zsh) and `_skell_empty` (bash) create and empty scratch files.

The shared scripts live in `share/`:

- `rank.awk` ranks distinct commands by frecency.
- `preview-*.awk` render skim previews.
- `build-fish-plugin.sh` assembles the `fish-releases` branch.

## Store contract

- Write `epoch`, `directory`, `exit status`, `shell`, and `command` as
  tab-separated fields in that order.
- Escape backslashes before newlines, tabs, and carriage returns. Decode the
  doubled backslashes before the other escape sequences.
- Keep the encoded record at or below 1000 bytes before its final newline, and
  append it with one write. Treat a limit change as concurrency-sensitive and
  document its platform and filesystem assumptions.
- Preserve duplicate commands; each occurrence contributes to frecency.
- Exclude commands whose typed form starts with a space.
- Preserve the command's exit status across prompt hooks.

## Process cost

Process startup is slow under MSYS2, and every fork on an interactive path
delays the prompt or the key press. Keep interactive paths in-process:

- Keep recording hooks fork-free; no external utility runs on the prompt path.
  Command substitutions around builtins or shell functions are allowed when the
  shell evaluates them in-process; command substitutions around external
  commands are not.
- Keep the fish completion path fork-free until skim starts. In bash, keep
  skell's own code on the `Tab` path fork-free until `gawk` renders the menu;
  completion functions may fork as they do under native `Tab`.
- Empty scratch files with a builtin instead of `rm` in bash, fish, and zsh,
  and leave deletion to the exit hook. For example, write `: >| "$file"`.

Prefer fish builtins over external commands when editing `.fish` files. Choose
the simplest builtin that preserves behavior; for example, iterate with
`for item in $items` instead of generating indices with `seq`:

| Operation                        | External tool          | Prefer in fish                                         |
| -------------------------------- | ---------------------- | ------------------------------------------------------ |
| Iterate over list elements       | `seq` for indices      | `for item in $items`                                   |
| Replace literal text             | `sed`                  | `string replace -a -- old new "$value"`                |
| Replace text with a regex        | `sed`                  | `string replace -ar -- '[0-9]+' NUMBER "$value"`       |
| Check a regex match              | `grep -q`              | `string match -rq -- pattern "$value"`                 |
| Extract a colon-delimited field  | `cut`, simple `awk`    | `string split -f2 -- : "$value"`                       |
| Convert case                     | `tr`                   | `string lower -- "$value"`, `string upper -- "$value"` |
| Trim whitespace                  | `sed`, `awk`           | `string trim -- "$value"`                              |
| Extract a filename or directory  | `basename`, `dirname`  | `path basename -- "$file"`, `path dirname -- "$file"`  |
| Resolve an absolute path         | `realpath`             | `path resolve -- "$file"`                              |
| Count list elements              | `wc` over a pipeline   | `count $items`                                         |
| Check list membership            | `grep` over a pipeline | `contains -- "$target" $items`                         |
| Calculate a needed numeric value | `expr`, simple `bc`    | `math "$n + 1"`                                        |
| Read text into one variable      | `cat`                  | `set -l text (string collect -aN < file)`              |

Check behavior before replacing an external tool. For example, `count` counts
list elements rather than file lines, and `string collect -aN` preserves empty
input and trailing newlines. Keep `gawk` for substantial streaming
transformations instead of building a long shell loop.

## Shell rules

Keep each shell's implementation direct. Do not introduce a shared runtime
dependency to remove small amounts of duplication.

Keep skell working under the user's shell options and rc habits:

- Write scratch files with `>|` in bash and zsh, which `noclobber` would
  otherwise refuse to overwrite.
- Make each entry point safe to source again; users re-source their rc files.
  For example, keep existing maps and chained traps instead of resetting them.

### bash

- Declare skell's globals with `declare -g`; a user may source
  `bash/skell.bash` from inside a function. For example, write
  `declare -gA _skell_cw_func=()`.
- Declare no locals in a function that evaluates the user's chained trap; the
  trap would see them in place of its own globals.
- Keep `_skell_cw_run` returning the current word unchanged while the menu
  records matches; the macro's `complete` step must insert nothing.
- Match native `Tab` exactly: the menu offers the matches, quoting, and
  insertion that bash would produce. Compare each change against bash without
  skell in a pty, both with and without bash-completion loaded.

### fish

fisher is the only supported fish installer. It copies only a plugin's root
`conf.d/`, `functions/`, `completions/`, and `themes/`. Build `fish/` as the
root of `fish-releases` and put `share/*.awk` under `functions/skell-share`.
`_skell_history` appends `skell-share` to `(status dirname)`, which fish
reports as the directory from which it autoloaded the function.

Before `.github/workflows/fish-releases.yml` force-pushes the branch, it runs
`tests/plugin-fish.sh`. The test fails when the build omits an awk script or
uses an awk directory name that differs from the fish sources.

### PowerShell

- Start skim from a PSReadLine key handler through
  `System.Diagnostics.Process`, and inherit stderr; skim draws its interface
  there. A key handler's pipeline collects and discards every stream of a
  native command it invokes.
- Keep `[Console]::OutputEncoding` set to UTF-8 until the redraw completes.
- Write files that `gawk` reads with LF line endings.
  `[System.IO.File]::WriteAllLines` writes CRLF on Windows, and a POSIX `gawk`
  keeps the CR on the last field.

### zsh

Load `zsh/completion.zsh` after `compinit`. Preserve zsh's completers, matcher
lists, styles, prefixes, suffixes, and quoting rules.

### awk

Use GNU awk features deliberately; the project requires `gawk`. Under a native
Windows `gawk`, `PROCINFO["platform"]` is `"mingw"` and pipes run through
`cmd.exe`, which expands `%NAME%` and passes arguments in the ANSI code page.
PowerShell therefore resolves MSYS2's or Git for Windows' `gawk` and uses a
native build only when `SKELL_GAWK` names one.

## Comments

Keep inline comments only for cross-shell format constraints, shell or OS
behavior, ordering requirements, and wrong-looking compatibility choices.

## Verification

Run the applicable commands from the repository root with bash 5.1 or newer
first on `PATH`; on macOS, install Homebrew's bash. The command patterns select
files by directory and extension, so a new file under a covered directory
needs no edit here:

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

`tests/run-all.sh` runs every suite with a temporary `SKELL_DATA_DIR` and
`SKELL_HISTORY`, skips suites for unavailable shells, and names each skip. Run
`tests/lifecycle-pwsh.ps1` through it; the script needs the module path and
sandbox that `run-all.sh` passes. The suites cover:

- the codec in all five implementations and the record fitter's boundaries;
- each recording hook's output and store permissions;
- the fish completion menu's prefix, insertion, buffer, and control-rendering
  helpers;
- the bash menu's quoting, insertion, and compspec wrapping;
- the PowerShell menu's prefix, description, and join helpers, and the
  module's lifecycle;
- the completion preview's choice of directory lister;
- the files fish loads from the built plugin and fish's rewrite of an
  inherited Windows store path (skipped without MSYS2).

No suite drives a real line editor, because the test environment cannot
provide a pty on every supported platform. Bash records under `bash -i`; zsh
and fish are called at the hook boundary with the arguments their editors
pass. PowerShell's `Get-History` is empty outside an interactive session, so
the suite covers the store opener and fitter instead of `Write-SkellRecord`.
Exercise key bindings, widgets, menus, and PowerShell's recording by hand.

When writing tests:

- Never read or write the developer's live history store.
- Put escape-grammar and record-budget changes in `tests/lib/vectors.tsv`.
  Every implementation is measured against it, so a divergent writer fails
  instead of storing a record another shell cannot decode.
- Write non-ASCII fixture bytes as octal escapes, such as `$'\302\235'`.
  Bash expands `$'\u009d'` only in a UTF-8 locale.
- Use cmdlets and executables present on every platform. For example, use
  `Get-Process -Name` rather than the Windows-only `Get-Service`.

## Ad hoc shell scripts on Windows

A native Windows binary ignores the MSYS signal that `timeout` sends, so
`timeout N script -q -c '…'` does not stop `script` or the processes it
starts. Driving `sk` or an interactive shell through a pty leaves the wrapper
and its children running, and they accumulate across a session. End them with
`Stop-Process -Id <pid> -Force` from PowerShell; matching on process name would
also kill the user's interactive shells.

MSYS2's zsh and Git-for-Windows Bash run in separate Cygwin runtimes, and the
runtimes differ in ways that break fixtures:

- `env VAR=x zsh …` reaches zsh with `VAR` unset, so a harness that sets
  variables with `env` tests the real configuration instead of the fixture.
  Write test configuration to a file and source it as the session's first
  command.
- Git-for-Windows mounts `/tmp` as `usertemp` at `%LOCALAPPDATA%\Temp`; MSYS2
  roots at `C:/msys64` and has no `/tmp` entry. The same POSIX path names
  different directories, and MSYS2 zsh and fish report `No such file or
  directory` for a path Git Bash resolves. The mount in `/etc/fstab` governs
  the mapping, not `TMP` or `TEMP`.
- MSYS2 fish can stat a mixed `C:/...` path from `cygpath -m` but cannot
  redirect to it (`Path does not exist`). Use `C:/msys64/tmp` for fixtures: it
  is `/tmp` to MSYS2 zsh and fish, `/c/msys64/tmp` to the agent's Bash, and
  `C:/msys64/tmp` to PowerShell, and all four read and write it.
- `mount` and other utilities resolve paths with the invoking runtime;
  `zsh -c 'mount'` from agent Bash prints Bash's mount table. Read
  runtime-specific configuration from a shell started by that runtime.
- An MSYS2 shell started by an agent inherits the agent's `PATH`, where
  Git-for-Windows precedes `/usr/bin`. `mkdir -p /tmp/x` then runs
  Git-for-Windows' `mkdir` against its own `/tmp`. Prepend `/usr/bin:/bin` in
  the fixture that a zsh or fish session sources before anything external
  runs.

A Git-for-Windows clone sets `core.filemode` to false, so git does not record
a new script's executable bit. Invoke a repository script through `bash`.
