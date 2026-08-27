# skell

One command history for bash, fish, PowerShell, and zsh, searched with
[skim](https://github.com/skim-rs/skim). In zsh, skell also replaces the
tab-completion menu.

Every shell appends to the same file with its own builtins, so recording does
not spawn a process. Search spawns skim once, then one preview helper per
candidate skim settles on.

## Requirements

Windows, Linux, and macOS, with the shells you want to wire up:

| shell      | needs | tested against |
| ---------- | ----- | -------------- |
| bash       | 5.0   | 5.3            |
| fish       | 4.0   | 4.8            |
| PowerShell | 7.0   | 7.6            |
| zsh        |       | 5.9            |

bash 5.0 supplies `EPOCHSECONDS`, fish 4.0 supplies both `path mtime` and the
`ctrl-r` key notation the binding uses, and PowerShell 7 supplies
`FileSystemAclExtensions`. zsh needs nothing newer than the version this was
written against; the parameter flags and hooks it uses are much older.

- [skim](https://github.com/skim-rs/skim) for `sk`, tested against 5.6.6. The
  `accept(edit)` and `accept(run)` binds are the current form of a bind skim
  also accepts in a deprecated spelling.
- `gawk` for ranking and previews (`mktime`, `systime`, and `PROCINFO` are GNU
  extensions). Windows ships no awk, and neither MSYS2 nor Git for Windows puts
  its `usr\bin` on the native `PATH`, so the PowerShell module looks for
  `gawk.exe` beside the `git` on `PATH` and then in `C:\msys64\usr\bin`. Git for
  Windows ships gawk at the first of those. `scoop install gawk` installs a
  native build on the `PATH` instead. The module reads `SKELL_GAWK` as the path
  to a gawk executable ahead of both; the other shells resolve `gawk` through
  the `PATH` alone.
- [lsd](https://github.com/lsd-rs/lsd) for the completion menu's directory
  preview; without lsd the preview uses `ls`

## Install

Clone the repository, then wire the shells you use:

```sh
git clone https://github.com/kvnxiao/skell ~/github/skell
```

**fish** — [fisher](https://github.com/jorgebucaran/fisher) copies a plugin's
root `conf.d/` and `functions/` but never its `share/`, so fish installs from
`fish-releases`, a generated branch with the awk scripts inside `functions/`.
fish is the one shell that does not read the clone:

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

**bash** — source it before starship, which moves any `PROMPT_COMMAND` it finds
into `STARSHIP_PROMPT_COMMAND` and runs it with `$?` restored:

```bash
[ -f ~/github/skell/bash/skell.bash ] && . ~/github/skell/bash/skell.bash
```

**PowerShell** — import it last, after starship and zoxide. The prompt wrapper
defined last runs first, which is the only point where `$?` still belongs to the
user's command:

```powershell
Import-Module "$HOME\github\skell\powershell\Skell.psm1"
```

`Remove-Module Skell` puts the prompt and the PSReadLine history handler back as
it found them.

`sk` is resolved through the `PATH` the session runs with. When either `sk` or
`gawk` is missing, `Ctrl+R` warns and leaves the line untouched.

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

zsh only. skell binds `Tab` and offers zsh's own matches through skim, so your
completers, matcher lists, and `:completion:*` styles still decide what the
candidates are. skell changes one style: it forces
`zstyle ':completion:*' list-grouped false` to keep matches that share a
description on separate rows.

| key          | action                         |
| ------------ | ------------------------------ |
| `Tab`        | open the menu, then move down  |
| `Shift+Tab`  | move up                        |
| `Ctrl+Space` | add the match to the selection |
| `Enter`      | insert the selection           |
| `Esc`        | leave the line untouched       |

zsh inserts an unambiguous prefix before it offers a choice, so completing
`sub` against `subdir-one` and `subdir-two` inserts `subdir-` and opens the menu
on the next `Tab`.

When the candidates fall into more than one group, each group's description is
shown beside its match in a dim column, capped at 20 characters and elided past
it. A single group leaves the column out. A query filters on the match alone, so
the query `co` does not select every entry under a group named `commands`. The
`format` style supplies that text, so a verbose value such as `Completing %d`
fills the column and a bare `%d` does not.

The preview runs `lsd` on a candidate that names a directory, and prints the
description of any other candidate. The preview window appears only when the
candidate set contains a directory.

Selecting more than one match inserts them all, separated by spaces.

## Store

`$XDG_DATA_HOME/skell/history.tsv`, defaulting to
`~/.local/share/skell/history.tsv`. One record per line, tab separated:

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

A trailing `\+` marks a record that the length cap cut. Where the directory
alone is long enough to leave no room for the command, the directory is stored
as `unknown` and the command is kept whole.

Set `SKELL_HISTORY` to move the file and `SKELL_DATA_DIR` to move the directory
that holds it.

### Who can read it

The store holds every command you run. skell creates the directory `0700` and
the file `0600` on Linux and macOS, and on Windows the PowerShell module
replaces the inherited descriptor with a single entry for your own account.

Cygwin and MSYS2 mount NTFS with `noacl`, which discards the umask, so bash,
fish, and zsh on Windows cannot set a mode: the store keeps whatever the parent
directory grants. Import the PowerShell module once to tighten it, or set the
ACL yourself with `icacls`.

### Why it does not need a lock

An MSYS2 `flock` and a Windows named mutex cannot see each other, so no lock
spans these shells. Cygwin's `O_APPEND` compiles to a single `NtWriteFile` at
`FILE_WRITE_TO_END_OF_FILE` and .NET's `FILE_APPEND_DATA` reaches the same
kernel atomic append, so the two interoperate without coordination.

Every record leaves in one write, sized to stay inside the window where
concurrent appenders interleave without tearing. On NTFS through the Cygwin and
MSYS2 runtimes, which is where skell is tested, that window is 1024 bytes; a
longer record is cut to fit rather than torn. The cap is counted in characters
rather than bytes, since a byte count would cost a second pass in every writer,
so a record holding any non-ASCII code point is held to a quarter of the budget:
four bytes is the widest UTF-8 encoding. Other platforms and filesystems are
untested, and a filesystem with a smaller atomic-append window would need the
cap lowered in every writer at once.

The writers count characters differently. gawk and fish count code points; bash
and zsh count UTF-16 units under Cygwin's 16-bit `wchar_t`, as PowerShell does.
Both counts stay inside 1024 bytes, so no record is ever torn, but a command
outside the Basic Multilingual Plane — emoji, most historic scripts — is cut at
a different point depending on which shell recorded it. Making the counts match
would need a per-code-point scan on the prompt path in bash and zsh, which
recording may not do.

PowerShell reaches that append through `FileSystemAclExtensions`.
`AppendAllText`, `Add-Content`, and `Out-File -Append` all open `GENERIC_WRITE`
without `FILE_APPEND_DATA` and emulate the append as `GetLength()` plus a
positional write, which races another shell mid-command; they also open
`FileShare.Read`, so a second writer throws.

### Directories are machine-local

A record names the directory but not the machine, and skell has no field for
one. A path recorded on another machine is read back as a plain string, so it
may name a directory that does not exist or a different directory entirely.
On Windows every shell records the MSYS2 form (`/c/Users/...`); PowerShell folds
its native path to match. A location outside the FileSystem provider, such as a
registry path, records as `unknown`.

### Leading-space commands

A command typed with a leading space is excluded. skell checks the leading space
in its own hook, so the store never holds one regardless of how the shell is
configured.

skell also leaves each shell's own exclusions working:

- bash keeps whatever `HISTCONTROL` and `HISTIGNORE` you set; skell adds
  `ignorespace` to `HISTCONTROL` only where neither `ignorespace` nor
  `ignoreboth` is already present.
- fish excludes leading-space commands by default.
- in PowerShell, skell consults any `AddToHistoryHandler` already installed
  before its own.
- zsh gets `HIST_IGNORE_SPACE`, an independent option that leaves your other
  history options alone.

A command your shell excludes from its own history still reaches skell's store
unless it starts with a space. There is no denylist.

## Ranking

Frecency, computed in one read-time pass with no stored state: the sum over
every occurrence of a decay by age — 4 within the hour, 2 within the day, 0.5
within the week, 0.25 beyond. Ties go to the more recent command.

Duplicate records are kept; each occurrence adds to the score.

## Migrating from atuin

```sh
bash share/migrate-atuin.sh            # writes the default store
bash share/migrate-atuin.sh --append   # adds to an existing one
bash share/migrate-atuin.sh --dry-run  # converts and validates without writing
bash share/migrate-atuin.sh --force    # skips the confirmation prompt
```

Close the shells that record to the store first. The import rewrites the file
rather than appending to it, so an append from another shell during the run
would be lost; without `--force` it asks before starting.

The conversion goes to a temporary file beside the target and is validated for
field count, record length, and oldest-first order before a rename publishes it.
A run that fails partway leaves the target byte for byte as it was, and retrying
cannot duplicate a partial prefix. Where the target already exists, its
permissions are kept.

A `workspaces = true` config narrows `atuin history list` to the git repository
that the export runs in, so the export overrides `ATUIN_FILTER_MODE`. Running it
in a fresh repository would otherwise write nothing. The export also passes
`--reverse=true` rather than relying on whichever order the installed atuin
defaults to.

## Tests

```sh
bash tests/run-all.sh
```

Each suite builds its own store under a temporary directory and never reads
yours. A shell the machine does not have is skipped and named in the summary.
The mode assertions in `tests/permissions.sh` are skipped where the filesystem
discards the umask, which is every NTFS mount under Cygwin and MSYS2.

No suite drives a real line editor, so a key binding or a completion-menu
change has to be exercised by hand.

## License

[MIT](LICENSE)
