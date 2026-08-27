# skell

One command history for bash, fish, PowerShell, and zsh, searched with
[skim](https://github.com/skim-rs/skim). In zsh, skell also replaces the
tab-completion menu.

Every shell appends to the same file without spawning a process on the recording
path. Search starts skim once and runs the preview helper for the candidate under
the cursor.

## Requirements

Skell runs on Windows, Linux, and macOS with the shells you want to wire up:

| shell      | needs | tested against |
| ---------- | ----- | -------------- |
| bash       | 5.0   | 5.3            |
| fish       | 4.0   | 4.8            |
| PowerShell | 7.0   | 7.6            |
| zsh        |       | 5.9            |

Bash 5.0 supplies `EPOCHSECONDS`, fish 4.0 supplies both `path mtime` and the
`ctrl-r` key notation the binding uses, and PowerShell 7 supplies
`FileSystemAclExtensions`. The zsh integration uses parameter flags and hooks
available before the tested 5.9 release.

- [skim](https://github.com/skim-rs/skim) for `sk`, tested against 5.6.6. The
  `accept(edit)` and `accept(run)` binds are skim's current syntax; skim also
  accepts their deprecated spelling.
- `gawk` for ranking and previews (`mktime`, `systime`, and `PROCINFO` are GNU
  extensions). Windows ships no awk, and neither MSYS2 nor Git for Windows puts
  its `usr\bin` on the native `PATH`, so the PowerShell module searches for
  `gawk.exe` on `PATH`, in Git for Windows' `usr\bin` under the installation
  that provides `git` on `PATH`, and in `C:\msys64\usr\bin`. Git for Windows
  provides the copy in that `usr\bin` directory. Scoop can install a native
  build with `scoop install gawk`.
  Set `SKELL_GAWK` to override these lookups; the other shells resolve `gawk`
  only through `PATH`.
- [lsd](https://github.com/lsd-rs/lsd) for the completion menu's directory
  preview; without lsd the preview uses `ls`

## Install

Clone the repository, then wire the shells you use:

```sh
git clone https://github.com/kvnxiao/skell ~/github/skell
```

**fish** — [fisher](https://github.com/jorgebucaran/fisher) installs only a
plugin's root `conf.d/` and `functions/` directories. The generated
`fish-releases` branch therefore puts the awk scripts inside `functions/`.
Fish installs from `fish-releases` instead of the clone:

```fish
fisher install kvnxiao/skell@fish-releases
```

**zsh** — an absolute path marks the module external, so
[zim](https://github.com/zimfw/zimfw) never installs or updates it. In `.zimrc`,
after `compinit` and before `fast-syntax-highlighting`:

```zsh
zmodule ~/github/skell/zsh -n skell
```

Without zim, source `zsh/init.zsh` from `.zshrc`.

**bash** — source it before starship. Starship moves any `PROMPT_COMMAND` it
finds into `STARSHIP_PROMPT_COMMAND` and runs it with `$?` restored:

```bash
[ -f ~/github/skell/bash/skell.bash ] && . ~/github/skell/bash/skell.bash
```

**PowerShell** — import it last, after starship and zoxide. The prompt wrapper
defined last runs first while `$?` still records the user's command:

```powershell
Import-Module "$HOME\github\skell\powershell\Skell.psm1"
```

`Remove-Module Skell` restores the prompt and the PSReadLine history handler.

`sk` is resolved through the session's `PATH`. When either `sk` or `gawk` is
missing, `Ctrl+R` warns and leaves the line untouched.

## History search

| key         | action                              |
| ----------- | ----------------------------------- |
| `Ctrl+R`    | search history                      |
| `Enter`     | put the command on the line         |
| `Alt+Enter` | put the command on the line and run |
| `Esc`       | leave the line untouched            |

A `bind -x` handler cannot submit a line, so in bash `Alt+Enter` asks the
terminal for a status report and binds the reply to `accept-line`. A terminal
that does not answer DSR leaves the command on the line for `Enter`.

## Completion menu

The completion menu applies to zsh only. Skell binds `Tab` and sends zsh's own
matches through skim. Zsh's
completers, matcher lists, and `:completion:*` styles still supply the
candidates. Skell sets `zstyle ':completion:*' list-grouped false` to keep
matches that share a description on separate rows.

| key          | action                         |
| ------------ | ------------------------------ |
| `Tab`        | open the menu, then move down  |
| `Shift+Tab`  | move up                        |
| `Ctrl+Space` | add the match to the selection |
| `Enter`      | insert the selection           |
| `Esc`        | leave the line untouched       |

Zsh inserts an unambiguous prefix before opening the menu. Completing `sub`
against `subdir-one` and `subdir-two` inserts `subdir-`; the next `Tab` opens the
menu.

When candidates span groups, Skell shows each group description beside its
matches in a dim column. It caps descriptions at 20 characters and elides
longer text. With one group, Skell omits the column. Queries filter matches, not
group descriptions: `co` does not select every entry under a group named
`commands`. The `format` style supplies the group text. A value such as
`Completing %d` fills the column; bare `%d` does not.

When a candidate names a directory, the preview uses `lsd` when available and
otherwise uses `ls`. For any other candidate, the preview prints its
description. The preview window appears only when the candidate set contains a
directory.

Selecting more than one match inserts them all, separated by spaces.

## Store

Skell uses `$XDG_DATA_HOME/skell/history.tsv` and defaults to
`~/.local/share/skell/history.tsv` when `XDG_DATA_HOME` is unset. The file
contains one tab-separated record per line:

```
<epoch>	<directory>	<exit>	<shell>	<command>
1787700487	/c/Users/kvnxiao/.dotfiles	0	fish	git status
```

In both the command and the directory, `\` becomes `\\`, and newline, tab, and
carriage return become `\n`, `\t`, and `\r`, so one record is always one line.
Every other byte is stored as it was typed, and a decoder consumes the `\\`
pairs before it reads any other escape, so a command holding a literal `\n` and
a command holding a newline round-trip to different strings. NUL is the one
byte outside the contract: no supported line editor produces it.

A trailing `\+` marks a record cut by the length cap. If the directory alone is
long enough to leave no room for the command, the directory is stored as
`unknown` and the command is kept whole.

Set `SKELL_HISTORY` to move the file. Set `SKELL_DATA_DIR` to move its
containing directory.

### Who can read it

The store contains the commands recorded by skell. Skell creates the directory
`0700` and the file `0600` on Linux and macOS. On Windows, the PowerShell module
replaces the inherited descriptor with a single entry for your own account.

Cygwin and MSYS2 mount NTFS with `noacl`, which discards the umask. Bash, fish,
and zsh on Windows cannot set a mode, so the store keeps the permissions the
parent directory grants. On Windows, the PowerShell module applies the
single-account ACL when it creates the store items; set an existing ACL with
`icacls`.

### Why it does not need a lock

MSYS2 `flock` and a Windows named mutex use different lock mechanisms. No
shared lock spans these shells. Cygwin's `O_APPEND` compiles to a single
`NtWriteFile` at `FILE_WRITE_TO_END_OF_FILE`, and .NET's `FILE_APPEND_DATA`
reaches the same kernel atomic append. These append operations interoperate
without a shared lock.

Each writer appends a record with one write, and each record stays inside the
atomic-append window. On NTFS under Cygwin and MSYS2, Skell tests a 1024-byte
window. The fitter cuts longer records to fit. The cap uses characters rather
than bytes to avoid a second pass in each writer. For non-ASCII input, it limits
a record to one quarter of the 1000-byte budget because UTF-8 code points use at
most four bytes. Other platforms and filesystems are untested. Lower the cap in
every writer if a filesystem has a smaller atomic-append window.

Writers count characters differently: gawk and fish count code points; Bash and
zsh count UTF-16 units under Cygwin's 16-bit `wchar_t`, as PowerShell does. Both
methods stay within the 1024-byte window, but a command outside the Basic
Multilingual Plane — emoji and most historic scripts — is cut at a different
point depending on which shell recorded it. Matching the counts would require a
per-code-point scan on the Bash and zsh prompt paths, and recording cannot
perform that scan.

PowerShell uses `FileSystemAclExtensions` for the append.
`AppendAllText`, `Add-Content`, and `Out-File -Append` all open `GENERIC_WRITE`
without `FILE_APPEND_DATA`. These methods emulate append as `GetLength()` plus
a positional write and can race another shell mid-command. They also open
`FileShare.Read`, so a second writer throws.

### Directories are machine-local

A record contains the directory but no machine identifier. A path recorded on
another machine is read back as a plain string, so it may name a directory that
does not exist or a different directory entirely. On Windows every shell records
the MSYS2 form (`/c/Users/...`); PowerShell folds its native path to match. A
location outside the FileSystem provider, such as a registry path, records as
`unknown`.

### Leading-space commands

Skell excludes commands typed with a leading space. It applies this check in its
own hook, so shell history configuration cannot re-enable those commands.

Each shell's own history exclusions remain active:

- Bash preserves your `HISTCONTROL` and `HISTIGNORE` settings; Skell adds
  `ignorespace` to `HISTCONTROL` only where neither `ignorespace` nor
  `ignoreboth` is already present.
- Fish excludes leading-space commands by default.
- PowerShell consults any `AddToHistoryHandler` already installed
  before its own.
- Zsh gets `HIST_IGNORE_SPACE`, an independent option that leaves your other
  history options alone.

Commands rejected by a shell's own history filter do not reach skell's store.
Commands accepted by that filter still reach the store unless their typed form
starts with a space. Skell has no additional denylist.

## Ranking

Skell computes frecency in one read-time pass without stored state. The score
sums an age-based weight for each occurrence: 4 within the hour, 2 within the
day, 0.5 within the week, and 0.25 beyond. Ties go to the more recent command.

Duplicate records are kept; each occurrence adds to the score.

## Migrating from atuin

```sh
bash share/migrate-atuin.sh
bash share/migrate-atuin.sh --append
bash share/migrate-atuin.sh --dry-run
bash share/migrate-atuin.sh --force
```

Before importing, close the shells that record to the store. The import replaces
the file instead of appending; an append from another shell during the run is
lost. Without `--force`, the command prompts before starting.

The conversion writes to a temporary file beside the target. The command
validates the converted records for field count, record length, and oldest-first
order, then renames the staged file into place. If conversion fails, the target
remains byte for byte unchanged. Retrying does not duplicate a partial prefix.
Existing target permissions are preserved.

With `workspaces = true`, atuin limits `history list` to the Git repository that
contains the current directory. The export sets `ATUIN_FILTER_MODE=global`, which
includes history from all repositories. Without that override, a fresh
repository can produce no records. The export passes `--reverse=true` to request
oldest-first output.

## Tests

```sh
bash tests/run-all.sh
```

Each suite builds its own store under a temporary directory and never reads your
live store. Suites for unavailable shells are skipped and named in the summary. The
mode assertions in `tests/permissions.sh` are skipped when the filesystem
discards the umask, including NTFS mounts under Cygwin and MSYS2.

No suite drives a real line editor. Exercise key bindings and completion-menu
changes by hand.

## License

[MIT](LICENSE)
