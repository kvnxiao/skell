# skell

Skell gives bash, fish, PowerShell, and zsh one shared command history. It uses
[skim](https://github.com/skim-rs/skim) for search and replaces zsh's
tab-completion menu.

Each shell appends to the same file without starting a process while recording.
History search starts skim once and runs the preview helper for the candidate
under the cursor.

## Requirements

Skell supports bash, fish, PowerShell, and zsh on Windows, Linux, and macOS:

| shell      | needs | tested against |
| ---------- | ----- | -------------- |
| bash       | 5.0   | 5.3            |
| fish       | 4.0   | 4.8            |
| PowerShell | 7.0   | 7.6            |
| zsh        |       | 5.9            |

Bash 5.0 supplies `EPOCHSECONDS`, fish 4.0 supplies `path mtime` and the
`ctrl-r` key notation used by the binding, and PowerShell 7 supplies
`FileSystemAclExtensions`. The zsh integration uses parameter flags and hooks
available before zsh 5.9.

- [skim](https://github.com/skim-rs/skim) for `sk`, tested against 5.6.6. The
  `accept(edit)` and `accept(run)` binds are skim's current syntax; skim also
  accepts their deprecated spelling.
- `gawk` for ranking and previews (`mktime`, `systime`, and `PROCINFO` are GNU
  extensions). Windows has no built-in awk, and neither MSYS2 nor Git for
  Windows puts its `usr\bin` on the native `PATH`. On Windows, the PowerShell
  module searches for `gawk.exe` on `PATH`, in the `usr\bin` directory of the
  Git for Windows installation found through `git`, and in
  `C:\msys64\usr\bin`. Scoop can install a native build with
  `scoop install gawk`.
  Set `SKELL_GAWK` to override these lookups; the other shells resolve `gawk`
  only through `PATH`.
- [lsd](https://github.com/lsd-rs/lsd) for the completion menu's directory
  preview; without lsd the preview uses `ls`

## Install

Clone the repository, then wire the shells you use:

```sh
git clone https://github.com/kvnxiao/skell ~/github/skell
```

**fish** — [fisher](https://github.com/jorgebucaran/fisher) does not install a
plugin's `share/` directory. The generated `fish-releases` branch therefore puts
the awk scripts in `functions/skell-share`.
Install fish support from `fish-releases`:

```fish
fisher install kvnxiao/skell@fish-releases
```

**zsh** — [zim](https://github.com/zimfw/zimfw) treats an absolute path as an
external module and does not install or update it. In `.zimrc`, load it after
`compinit` and before `fast-syntax-highlighting`:

```zsh
zmodule ~/github/skell/zsh -n skell
```

Without zim, source `zsh/init.zsh` from `.zshrc`.

**bash** — source it before starship. Starship moves `PROMPT_COMMAND` into
`STARSHIP_PROMPT_COMMAND` and runs it with `$?` restored:

```bash
[ -f ~/github/skell/bash/skell.bash ] && . ~/github/skell/bash/skell.bash
```

**PowerShell** — import it after starship and zoxide. The wrapper defined last
runs first while `$?` still records the user's command:

```powershell
Import-Module "$HOME\github\skell\powershell\Skell.psm1"
```

`Remove-Module Skell` restores the prompt and the PSReadLine history handler.

History search requires `sk` and `gawk`. If either is missing, the search leaves
the command line unchanged; PowerShell also writes a warning.

## History search

| key         | action                              |
| ----------- | ----------------------------------- |
| `Ctrl+R`    | search history                      |
| `Enter`     | put the command on the line         |
| `Alt+Enter` | put the command on the line and run |
| `Esc`       | leave the line untouched            |

Because a `bind -x` handler cannot submit a line, bash `Alt+Enter` asks the
terminal for a status report and binds the reply to `accept-line`. If the
terminal does not answer DSR, the command remains on the line for `Enter`.

## Completion menu

The completion menu applies only to zsh. Skell binds `Tab` and sends zsh's
matches through skim. Zsh's completers, matcher lists, and `:completion:*`
styles still supply the candidates. Skell sets
`zstyle ':completion:*' list-grouped false` so matches that share a description
stay on separate rows.

| key          | action                         |
| ------------ | ------------------------------ |
| `Tab`        | open the menu, then move down  |
| `Shift+Tab`  | move up                        |
| `Ctrl+Space` | add the match to the selection |
| `Enter`      | insert the selection           |
| `Esc`        | leave the line untouched       |

Before opening the menu, zsh inserts an unambiguous prefix. Completing `sub`
against `subdir-one` and `subdir-two` inserts `subdir-`; the next `Tab` opens the
menu.

When matches span groups, Skell shows each group description beside its matches
in a dim column. Descriptions are capped at 20 characters and longer text is
elided. Skell omits the column when one group supplies all matches. Queries
filter matches, not group descriptions: `co` does not select every entry in a
group named `commands`. The `format` style supplies the group text. A value such
as `Completing %d` fills the column; bare `%d` leaves it empty.

For a candidate that names a directory, the preview uses `lsd` when available
and otherwise uses `ls`. For other candidates, the preview prints the
description. Skell shows the preview window only when the candidate set
contains a directory.

Selecting multiple matches inserts them with spaces between them.

## Store

Skell stores history in `$XDG_DATA_HOME/skell/history.tsv` or, when
`XDG_DATA_HOME` is unset, in `~/.local/share/skell/history.tsv`. The file
contains one tab-separated record per line:

```
<epoch>	<directory>	<exit>	<shell>	<command>
1787700487	/c/Users/kvnxiao/.dotfiles	0	fish	git status
```

In the command and directory fields, `\` becomes `\\`, and newline, tab, and
carriage return become `\n`, `\t`, and `\r`. These escapes keep one record per
line. The decoder consumes `\\` before it decodes the other escape sequences,
so a command containing a literal `\n` and a command containing a newline
round-trip to different strings. Unrecognized escapes remain unchanged. NUL is
outside the contract because no supported line editor produces it.

A trailing `\+` marks a record cut by the length cap. If the directory alone is
long enough to leave no room for the command, the directory is stored as
`unknown` and the command is kept whole.

Set `SKELL_HISTORY` to move the file. Set `SKELL_DATA_DIR` to move its
containing directory. On Windows, bash, fish, and zsh use MSYS2 paths; PowerShell
uses a native Windows path.

Fish can stat a drive-letter path such as `C:/...` but cannot redirect to it.
Before opening the store, Skell rewrites the drive-letter path to its mounted
MSYS2 path. Bash and zsh append using their configured paths.

### Who can read it

The store contains the commands recorded by Skell. On Linux and macOS, Skell
creates the directory with mode `0700` and the file with mode `0600`. When the
PowerShell module creates the store on Windows, it replaces inherited ACL
entries with one entry for your account.

Cygwin and MSYS2 mount NTFS with `noacl`, which discards the umask. Bash, fish,
and zsh on Windows cannot set a mode, so the store keeps the permissions the
parent directory grants. On Windows, the PowerShell module applies the
single-account ACL when it creates the store items; set an existing ACL with
`icacls`.

### Append synchronization

MSYS2 `flock` and a Windows named mutex do not coordinate, so these shells share
no lock. Cygwin's `O_APPEND` compiles to a single `NtWriteFile` at
`FILE_WRITE_TO_END_OF_FILE`, and .NET's `FILE_APPEND_DATA` reaches the same
kernel atomic append. These append operations share a store without a common
lock.

Each writer appends a record with one write, and each record stays inside the
atomic-append window. On NTFS under Cygwin and MSYS2, Skell tests a 1024-byte
window. The fitter cuts longer records to fit. It counts characters instead of
bytes to avoid a second pass in each writer. For non-ASCII input, it uses a
250-character limit because UTF-8 code points use at most four bytes. Other
platforms and filesystems are untested. Lower the cap in every writer if a
filesystem has a smaller atomic-append window.

Writers count characters differently: gawk and fish count code points; Bash and
zsh count UTF-16 units under Cygwin's 16-bit `wchar_t`, as PowerShell does. Both
counts stay within the 1024-byte window, but a command outside the Basic
Multilingual Plane, such as one containing emoji or most historic scripts, is
cut at a different point depending on which shell recorded it. Matching the
counts would require a per-code-point scan on the Bash and zsh prompt paths,
which recording cannot perform.

PowerShell uses `FileSystemAclExtensions` for appending.
`AppendAllText`, `Add-Content`, and `Out-File -Append` all open `GENERIC_WRITE`
without `FILE_APPEND_DATA`. These methods emulate append as `GetLength()` plus
a positional write and can race another shell mid-command. They also open
`FileShare.Read`, so a second writer throws.

### Directories are machine-local

A record contains the directory but no machine identifier. When a path is read
on another machine, it remains a plain string and may name a directory that does
not exist or a different directory entirely. On Windows, every shell records the
MSYS2 form (`/c/Users/...`); PowerShell folds its native path to match. A
location outside the FileSystem provider, such as a registry path, records as
`unknown`.

### Leading-space commands

Skell's hook excludes commands whose typed form starts with a space. Shell
history configuration cannot re-enable them.

Each shell's own history filters remain active:

- Bash preserves `HISTCONTROL` and `HISTIGNORE`; Skell adds `ignorespace` to
  `HISTCONTROL` only when neither `ignorespace` nor `ignoreboth` is present.
- Fish excludes leading-space commands by default.
- PowerShell calls an existing `AddToHistoryHandler` before its own handler.
- Zsh sets `HIST_IGNORE_SPACE` without changing its other history options.

Shell filters reject commands before Skell sees them. A command accepted by a
shell filter reaches the store unless its typed form starts with a space. Skell
adds no other denylist.

## Ranking

Skell computes frecency in one read-time pass without stored state. The score
sums an age-based weight for each occurrence: 4 within the hour, 2 within the
day, 0.5 within the week, and 0.25 beyond. Ties go to the more recent command.

Skell keeps duplicate records; each occurrence adds to the score.

## Migrating from atuin

```sh
bash share/migrate-atuin.sh
bash share/migrate-atuin.sh --append
bash share/migrate-atuin.sh --dry-run
bash share/migrate-atuin.sh --force
```

Before a normal import, close the shells that record to the store. The migration
writes temporary files beside the target, validates the converted records, and
publishes the staged file with one rename. A shell write that races the staging
step can be lost. Without `--force`, a normal import prompts before starting.

Validation checks field count, record length, and oldest-first order. If
conversion fails, the target remains byte for byte unchanged. Retrying does not
duplicate a partial prefix. Existing target permissions are preserved.

When `workspaces = true`, `atuin history list` limits output to the Git
repository containing the current directory. The migration sets
`ATUIN_FILTER_MODE=global` to include all repositories and passes
`--reverse=true` for oldest-first output. Without global mode, a new repository
can produce no records.

## Tests

```sh
bash tests/run-all.sh
```

Each suite creates its own store under a temporary directory and never reads the
live store. Suites for unavailable shells are skipped and named in the summary.
The mode assertions in `tests/permissions.sh` are skipped when the filesystem
discards the umask, including NTFS mounts under Cygwin and MSYS2.

No suite drives a real line editor. Test key bindings and completion-menu
changes manually.

## License

[MIT](LICENSE)
