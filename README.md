# skell

Skell is skim for your shell: it puts [skim](https://github.com/skim-rs/skim),
a fuzzy finder, behind the two keys you press most when working in a terminal.
`Ctrl+R` searches every command you have run, and `Tab` lists the shell's own
completions in a filterable menu. Skell works the same way in bash, fish,
PowerShell, and zsh on Windows, Linux, and macOS, and it keeps out of the way
of the prompt: recording a command starts no process.

- **Shared history.** Every shell appends to one history file, so a command run
  in zsh is one `Ctrl+R` away in PowerShell. Each record keeps the time, the
  working directory, the exit status, and the shell that ran it.
- **History search.** `Ctrl+R` opens skim over your history, ranked by how
  often and how recently you ran each command. A preview pane shows the details
  of the command under the cursor.
- **Completion menu.** `Tab` sends the shell's native completion matches
  through skim, so your existing completions keep working and gain fuzzy
  filtering, descriptions, multi-select, and a directory preview.

## Requirements

| shell      | needs | tested against |
| ---------- | ----- | -------------- |
| bash       | 5.1   | 5.3            |
| fish       | 4.0   | 4.8            |
| PowerShell | 7.4   | 7.6            |
| zsh        |       | 5.9            |

macOS ships bash 3.2 as `/bin/bash`; install bash 5 with `brew install bash`.
Under a bash older than 5.1, `bash/skell.bash` prints a warning and loads
nothing.

Skell also needs these programs:

- [skim](https://github.com/skim-rs/skim) for `sk`, tested against 5.6.6.
- `gawk` for ranking and previews. Other awk implementations lack the GNU
  extensions Skell uses (`mktime`, `systime`, and `PROCINFO`).
- Optionally, [eza](https://github.com/eza-community/eza) or
  [lsd](https://github.com/lsd-rs/lsd) for the completion menu's directory
  preview. Without either, the preview uses `ls`.

On Windows, bash, fish, and zsh find `gawk` on `PATH`. Windows has no built-in
awk, and neither MSYS2 nor Git for Windows puts its `usr\bin` on the native
`PATH`, so the PowerShell module looks for `gawk` itself:

1. MSYS2's `usr\bin\gawk.exe`, found through the installer's uninstall entry
   or at `C:\msys64`.
2. Git for Windows' `usr\bin\gawk.exe`, found through the installer's registry
   key or through `git` on `PATH`.

The module ignores `gawk` on `PATH`. A native Windows build, such as Scoop's,
runs previews through `cmd.exe`, which expands a defined `%NAME%` and cannot
pass characters outside the ANSI code page. Set `SKELL_GAWK` to the path of a
`gawk` to override the lookup.

## Install

Clone the repository, then wire up each shell you use:

```sh
git clone https://github.com/kvnxiao/skell ~/github/skell
```

**fish** — install the `fish-releases` branch with
[fisher](https://github.com/jorgebucaran/fisher):

```fish
fisher install kvnxiao/skell@fish-releases
```

fisher does not install a plugin's `share/` directory, so the generated
`fish-releases` branch puts the awk scripts in `functions/skell-share`.

**zsh** — with [zim](https://github.com/zimfw/zimfw), add the module to
`.zimrc` after `compinit` and before `fast-syntax-highlighting`:

```zsh
zmodule ~/github/skell/zsh -n skell
```

zim treats an absolute path as an external module and does not install or
update it; run `git pull` in the clone to update. Without zim, source
`zsh/init.zsh` from `.zshrc` after `compinit`.

**bash** — source it from `.bashrc` before starship:

```bash
[ -f ~/github/skell/bash/skell.bash ] && . ~/github/skell/bash/skell.bash
```

Starship moves `PROMPT_COMMAND` into `STARSHIP_PROMPT_COMMAND` and runs it with
`$?` restored, so Skell still records each command's exit status.

**PowerShell** — import it from your profile after starship and zoxide:

```powershell
Import-Module "$HOME\github\skell\powershell\Skell.psm1"
```

The prompt wrapper defined last runs first, while `$?` still records your
command's exit status. When `Ctrl+R`, `Tab`, or `Shift+Tab` already has a
custom handler, Skell keeps it and does not install its own binding.
`Remove-Module Skell` restores the prompt, the PSReadLine history handler, and
the prior `Ctrl+R`, `Tab`, and `Shift+Tab` bindings. It does not replace a
custom handler installed after Skell.

If `sk` or `gawk` is missing, each shell warns once per session, and `Ctrl+R`
and `Tab` fall back to the shell's own history search and completion.

## History search

| key         | action                              |
| ----------- | ----------------------------------- |
| `Ctrl+R`    | search history                      |
| `Enter`     | put the command on the line         |
| `Alt+Enter` | put the command on the line and run |
| `Esc`       | leave the line untouched            |

Skell ranks distinct commands by frecency. Each time you ran a command adds to
its score by age: 4 within the hour, 2 within the day, 0.5 within the week, and
0.25 beyond. Ties go to the more recent command. The ranking runs when you open
the search and keeps no state of its own.

In history and completion text, skim shows control characters (C0 and C1
controls and DEL) as `<0xNN>`. The command placed on the line keeps the original
characters.

A bash `bind -x` handler cannot submit a line, so in bash `Alt+Enter` asks the
terminal for a status report and binds the reply to `accept-line`. If the
terminal does not answer that report, the command stays on the line for
`Enter`.

## Completion menu

| key          | action                         |
| ------------ | ------------------------------ |
| `Tab`        | open the menu, then move down  |
| `Shift+Tab`  | move up                        |
| `Ctrl+Space` | add the match to the selection |
| `Enter`      | insert the selection           |
| `Esc`        | leave the line untouched       |

Before opening the menu, Skell inserts any unambiguous prefix. Completing `sub`
against `subdir-one` and `subdir-two` inserts `subdir-`, and the next `Tab`
opens the menu. A single match is inserted without the menu. Selecting several
matches inserts them separated by spaces; PowerShell sometimes joins them with
commas instead, as its section below describes.

Outside the menu, `Shift+Tab` runs the shell's native completion:

- bash: readline's `complete`.
- fish: fish's pager.
- PowerShell: PSReadLine's `MenuComplete`.
- zsh: zsh's completion widget.

In bash and zsh, Skell binds `Shift+Tab` only when it has no binding.

### Preview

`SKELL_COMPLETE_PREVIEW` selects what the preview pane shows:

| value                   | preview                                                        |
| ----------------------- | -------------------------------------------------------------- |
| `description` (default) | directory listings and descriptions                            |
| `directory`             | directory listings, shown only when a candidate is a directory |
| `off`                   | none                                                           |

Bash has no match descriptions, so `description` behaves as `directory` there.

On Windows, each cursor move in the menu starts `cmd.exe` and `gawk`, and a
directory also starts the directory lister. Set `SKELL_COMPLETE_PREVIEW=off` to
skip them.

`SKELL_COMPLETE_LS` selects the directory lister:

| value          | lister                                        |
| -------------- | --------------------------------------------- |
| unset or empty | the first of `eza`, `lsd`, and `ls` on `PATH` |
| `eza`          | `eza`                                         |
| `lsd`          | `lsd`                                         |
| `ls`           | `ls`                                          |

A named lister has no fallback: when it is not on `PATH`, the preview shows the
shell's error. Any other value makes the preview print an error instead of a
listing. The preview reads the variable from the environment, so export it:

- bash and zsh: `export SKELL_COMPLETE_LS=lsd`
- fish: `set -gx SKELL_COMPLETE_LS lsd`
- PowerShell: `$env:SKELL_COMPLETE_LS = 'lsd'`

When `SKELL_GAWK` names a native Windows `gawk`, the lister runs through
`cmd.exe`, and the unset default tries `eza`, then `lsd`, then `dir /b`. There
a directory does not list when its path has characters outside the ANSI code
page or the name of a defined variable between `%` signs.

### Turning the menu off

`SKELL_COMPLETE=off` leaves `Tab` to the shell and keeps history search. Bash
reads it when `bash/skell.bash` loads; fish, PowerShell, and zsh read it on each
`Tab`.

### bash

Readline does not expose its matches to a key binding, so `Tab` runs a macro
that calls readline's own `complete`. Skell wraps each compspec, including
bash-completion's lazily loaded ones, to record the matches. Readline still
splits the words and runs the completion functions, so the menu offers the same
matches as native `Tab`.

- Skell quotes filename matches as readline does: inside an open quote, or with
  backslashes.
- A directory match gets a trailing `/`; other finished matches get a space
  unless the compspec sets `nospace`.
- When no `-D`, `-E`, or `-I` compspec exists, Skell adds one to receive
  default, empty-line, and command-name completion. Each falls back to bash's
  own completion when the menu is not running.
- Readline lists matches on a second `Tab` only after its own `complete`. When
  the menu records nothing, as at a continuation prompt, a second `Tab` does
  not list them; `Shift+Tab` twice does.

### fish

`complete -C` supplies the candidates, so fish's completions, ranking, and
escaping still apply. Each description appears in a dim column; queries filter
candidates, not descriptions.

- A token with a `*` glob goes to fish's own completion, which expands it in
  place.
- `Shift+Tab` opens fish's pager, and `Tab` then moves through its entries.
- On an empty line, the menu lists every command.
- An inserted match gets a trailing space unless it ends in `/`, `=`, `@`, `:`,
  `.`, `,`, or `-`, matching fish. A space also closes a quote the match left
  open.

### PowerShell

`TabExpansion2` supplies the matches in-process, so argument completers and
`TabExpansion2` overrides still apply. Tooltips appear as descriptions, except
for files, directories, and executables, whose tooltips repeat their path.

- A single directory match gets a trailing separator, as in PSReadLine.
- Multiple values for a PowerShell command join with commas into one array, as
  in `Get-ChildItem ./a,./b`. Parameter names, command names, and arguments to
  native executables join with spaces.

### zsh

Zsh's completers, matcher lists, and `:completion:*` styles still supply the
candidates. Skell sets `zstyle ':completion:*' list-grouped false` so matches
that share a description stay on separate rows.

When matches span groups, Skell shows each group description beside its matches
in a dim column. Descriptions are capped at 20 characters and longer text is
elided. Skell omits the column when one group supplies all matches. Queries
filter matches, not group descriptions: `co` does not select every entry in a
group named `commands`. The `format` style supplies the group text. A value such
as `Completing %d` fills the column; bare `%d` leaves it empty.

## Your history

Skell stores history in `$XDG_DATA_HOME/skell/history.tsv` or, when
`XDG_DATA_HOME` is unset or empty, in `~/.local/share/skell/history.tsv`. Set
`SKELL_DATA_DIR` to move the `skell` directory, which also has each session's
scratch files, or `SKELL_HISTORY` to move only the history file. On Windows,
bash, fish, and zsh use MSYS2 paths; PowerShell uses a native Windows path.

### What gets recorded

Skell records every command except those you type with a leading space. Shell
history configuration cannot re-enable leading-space commands, and Skell adds
no other denylist. Each shell's own history filters still apply, and they
reject commands before Skell sees them:

- Bash preserves `HISTCONTROL` and `HISTIGNORE`; Skell adds `ignorespace` to
  `HISTCONTROL` only when neither `ignorespace` nor `ignoreboth` is present.
- Fish excludes leading-space commands by default.
- PowerShell calls an existing `AddToHistoryHandler` before its own handler.
- Zsh sets `HIST_IGNORE_SPACE` without changing its other history options.

Skell keeps every occurrence of a command, since each one adds to its frecency
score.

### Who can read it

On Linux and macOS, Skell creates the directory with mode `0700` and the file
with mode `0600`. When the PowerShell module creates the store on Windows, it
replaces inherited ACL entries with one entry for your account.

Cygwin and MSYS2 mount NTFS with `noacl`, which discards the umask. Bash, fish,
and zsh on Windows cannot set a mode, so a store they create keeps the
permissions the parent directory grants. Set an existing store's ACL with
`icacls`.

### Directories are machine-local

A record has the directory but no machine identifier. When you sync the file to
another machine, a recorded path may name a directory that does not exist there
or a different directory entirely. On Windows, every shell records the MSYS2
form (`/c/Users/...`); PowerShell converts its native path to match. A location
outside the FileSystem provider, such as a registry path, records as `unknown`.

### File format

The file has one tab-separated record per line:

```
<epoch>	<directory>	<exit>	<shell>	<command>
1787700487	/c/Users/kvnxiao/.dotfiles	0	fish	git status
```

In the command and directory fields, `\` becomes `\\`, and newline, tab, and
carriage return become `\n`, `\t`, and `\r`. These escapes keep one record per
line. The decoder consumes `\\` before it decodes the other escape sequences,
so a command containing a literal `\n` and a command containing a newline
round-trip to different strings. Unrecognized escapes remain unchanged. NUL is
outside the format because no supported line editor produces it.

Skell caps each record's length, and a trailing `\+` marks a record cut by the
cap. If the directory alone is long enough to leave no room for the command,
the directory is stored as `unknown` and the command is kept whole.

## How shells share the file

The shells share no lock: MSYS2 `flock` and a Windows named mutex do not
coordinate. Instead, each writer appends a whole record with one atomic append.
Cygwin's `O_APPEND` compiles to a single `NtWriteFile` at
`FILE_WRITE_TO_END_OF_FILE`, and .NET's `FILE_APPEND_DATA` reaches the same
kernel atomic append.

The record cap keeps each append inside the atomic-append window. On NTFS under
Cygwin and MSYS2, Skell tests a 1024-byte window. Other platforms and
filesystems are untested; lower the cap in every writer if a filesystem has a
smaller atomic-append window.

The fitter counts characters instead of bytes to avoid a second pass in each
writer. For non-ASCII input, it uses a 250-character limit because UTF-8 code
points use at most four bytes. Writers count characters differently: gawk and
fish count code points, while bash and zsh count UTF-16 units under Cygwin's
16-bit `wchar_t`, as PowerShell does. Both counts stay within the 1024-byte
window, but a command outside the Basic Multilingual Plane, such as one
containing emoji, is cut at a different point depending on which shell recorded
it. Matching the counts would require a per-code-point scan on the bash and zsh
prompt paths, which recording cannot afford.

PowerShell appends through `FileSystemAclExtensions`. `AppendAllText`,
`Add-Content`, and `Out-File -Append` open `GENERIC_WRITE` without
`FILE_APPEND_DATA`. They emulate append as `GetLength()` plus a positional
write, which can race another shell mid-command. They also open
`FileShare.Read`, so a second writer throws.

Fish can stat a drive-letter path such as `C:/...` but cannot redirect to it,
so before opening the store, fish rewrites a drive-letter path to its mounted
MSYS2 path. Bash and zsh append using their configured paths.

## Development

Each minimum version supplies features Skell uses:

- bash 5.1: a `HISTCMD` that advances inside `PROMPT_COMMAND`, which the
  recording hook compares to detect a new command. Bash 5.0 reports 1 there.
  Bash 5.0 also supplies `EPOCHSECONDS`, `complete -I`, and a `READLINE_POINT`
  counted in characters.
- fish 4.0: `path mtime` and the `ctrl-r` key notation used by the binding.
- PowerShell 7.4: the .NET filesystem APIs used to apply Unix modes.

The zsh integration uses parameter flags and hooks available before zsh 5.9.
The `accept(edit)` and `accept(run)` skim binds are skim's current syntax; skim
also accepts their deprecated spelling.

Run the test suites from the repository root:

```sh
bash tests/run-all.sh
```

The suites need bash 5.1 or newer as the first `bash` on `PATH`; under an older
bash, they exit with an error. Each suite creates its own store under a
temporary directory and never reads the live store. Suites for unavailable
shells are skipped and named in the summary. The mode assertions in
`tests/permissions.sh` are skipped when the filesystem discards the umask,
including NTFS mounts under Cygwin and MSYS2.

No suite drives a real line editor. Test key bindings and completion-menu
changes manually.

## License

[MIT](LICENSE)
