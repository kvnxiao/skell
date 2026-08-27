# skell -- one command history for bash, fish, powershell, and zsh.
# https://github.com/kvnxiao/skell

$env:SKELL_ROOT = Split-Path -Parent $PSScriptRoot
if (-not $env:SKELL_DATA_DIR) {
    $env:SKELL_DATA_DIR = if ($env:XDG_DATA_HOME) {
        Join-Path -Path $env:XDG_DATA_HOME -ChildPath 'skell'
    } else {
        Join-Path -Path $HOME -ChildPath '.local' -AdditionalChildPath 'share', 'skell'
    }
}
if (-not $env:SKELL_HISTORY) {
    $env:SKELL_HISTORY = Join-Path -Path $env:SKELL_DATA_DIR -ChildPath 'history.tsv'
}

# The store holds every command the user runs. On Unix the mode is set
# directly; on Windows the inherited ACL is replaced by one entry for the
# current account, since a profile directory can inherit wider rights.
function Set-SkellPrivateAcl {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path)

    if (-not $PSCmdlet.ShouldProcess($Path, 'Restrict access to the current account')) { return }
    $item = Get-Item -LiteralPath $Path
    $isDir = $item -is [System.IO.DirectoryInfo]
    if ($IsWindows) {
        # A descriptor built from scratch contains no rules, so protecting it
        # against inheritance and adding one entry leaves exactly that entry.
        # Editing the item's own descriptor would mean removing each inherited
        # rule, which cannot be removed while inheritance still applies.
        $acl = if ($isDir) {
            [System.Security.AccessControl.DirectorySecurity]::new()
        } else {
            [System.Security.AccessControl.FileSecurity]::new()
        }
        $acl.SetAccessRuleProtection($true, $false)
        $inherit = if ($isDir) {
            [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
            [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        } else {
            [System.Security.AccessControl.InheritanceFlags]::None
        }
        $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(
                [System.Security.Principal.WindowsIdentity]::GetCurrent().User,
                [System.Security.AccessControl.FileSystemRights]::FullControl,
                $inherit,
                [System.Security.AccessControl.PropagationFlags]::None,
                [System.Security.AccessControl.AccessControlType]::Allow))
        # .NET Core dropped the SetAccessControl instance methods; the extension
        # class is the only route to a DACL from PowerShell 7.
        if ($isDir) {
            [System.IO.FileSystemAclExtensions]::SetAccessControl([System.IO.DirectoryInfo]$item, $acl)
        } else {
            [System.IO.FileSystemAclExtensions]::SetAccessControl([System.IO.FileInfo]$item, $acl)
        }
        return
    }
    $mode = if ($isDir) {
        [System.IO.UnixFileMode]::UserRead -bor
        [System.IO.UnixFileMode]::UserWrite -bor
        [System.IO.UnixFileMode]::UserExecute
    } else {
        [System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite
    }
    [System.IO.File]::SetUnixFileMode($Path, $mode)
}

if (-not [System.IO.Directory]::Exists($env:SKELL_DATA_DIR)) {
    $null = [System.IO.Directory]::CreateDirectory($env:SKELL_DATA_DIR)
    try { Set-SkellPrivateAcl $env:SKELL_DATA_DIR } catch {
        Write-Warning "skell: could not restrict $env:SKELL_DATA_DIR : $($_.Exception.Message)"
    }
}
if (-not [System.IO.File]::Exists($env:SKELL_HISTORY)) {
    [System.IO.File]::WriteAllText($env:SKELL_HISTORY, '')
    try { Set-SkellPrivateAcl $env:SKELL_HISTORY } catch {
        Write-Warning "skell: could not restrict $env:SKELL_HISTORY : $($_.Exception.Message)"
    }
}

# An MSYS2 flock and a Windows named mutex cannot see each other, so no lock
# spans these shells. FILE_APPEND_DATA reaches the same kernel atomic append
# that Cygwin's O_APPEND compiles to, which is the only coordination between
# PowerShell and the POSIX halves.
# AppendAllText, Add-Content, and Out-File -Append all open GENERIC_WRITE
# without FILE_APPEND_DATA and emulate the append as GetLength() plus a
# positional write, which races another shell mid-command. They also open
# FileShare.Read, so a second writer throws.
function Open-SkellStore {
    if ($IsWindows) {
        return [System.IO.FileSystemAclExtensions]::Create(
            [System.IO.FileInfo]::new($env:SKELL_HISTORY),
            [System.IO.FileMode]::Append,
            [System.Security.AccessControl.FileSystemRights]::AppendData,
            [System.IO.FileShare]::ReadWrite,
            4096,
            [System.IO.FileOptions]::None,
            $null)
    }
    return [System.IO.FileStream]::new(
        $env:SKELL_HISTORY,
        [System.IO.FileMode]::Append,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::ReadWrite)
}

# The ranked file is a plaintext dump of the whole history, so it stays in
# skell's own directory rather than a temp directory shared with every other
# user of the machine. MSYS2 and Windows number processes separately, so the
# name carries the shell as well as the id.
function Get-SkellRankPath {
    return Join-Path -Path $env:SKELL_DATA_DIR -ChildPath "rank-pwsh-$PID.tsv"
}

function Get-SkellEscapedField([string]$Text) {
    return $Text.Replace('\', '\\').Replace("`n", '\n').Replace("`t", '\t').Replace("`r", '\r')
}

# The encoded backslash pair is consumed before any other escape is decoded, so
# a byte the store holds literally can never be read as an escape introducer. A
# decoder that swapped in a placeholder character would rewrite that character
# when it restored the backslashes.
function Convert-SkellEscape([string]$Text) {
    $parts = $Text.Split([string[]]@('\\'), [System.StringSplitOptions]::None)
    for ($i = 0; $i -lt $parts.Length; $i++) {
        $parts[$i] = $parts[$i].Replace('\t', "`t").Replace('\r', "`r").Replace('\+', ' […]').Replace('\n', "`n")
    }
    return $parts -join '\'
}

# Concurrent appenders interleave without tearing up to 1024 bytes on NTFS
# through the Cygwin and MSYS2 runtimes, which is where skell is tested. A
# record holding any non-ASCII code point is capped at a quarter of the budget,
# since four bytes is the widest UTF-8 encoding and a byte count would need a
# second pass. .NET counts UTF-16 units, as bash and zsh do under Cygwin's
# 16-bit wchar_t, while gawk and fish count code points; either count stays
# inside 1000 bytes, so a command outside the BMP is cut at a different point
# depending on which shell recorded it.
function Get-SkellFittedRecord([string]$Head, [string]$Command) {
    $record = "$Head`t$Command"
    $limit = if ([System.Text.Encoding]::UTF8.GetByteCount($record) -eq $record.Length) { 1000 } else { 250 }
    if ($record.Length -le $limit) { return $record }

    $keep = $limit - $Head.Length - 3
    if ($keep -lt 1) {
        $f = $Head.Split("`t")
        $Head = "$($f[0])`tunknown`t$($f[2])`t$($f[3])"
        $record = "$Head`t$Command"
        $limit = if ([System.Text.Encoding]::UTF8.GetByteCount($record) -eq $record.Length) { 1000 } else { 250 }
        # Dropping the directory can be enough on its own, and a record that
        # now fits is whole: marking it elided would claim a cut that never
        # happened.
        if ($record.Length -le $limit) { return $record }
        $keep = $limit - $Head.Length - 3
        if ($keep -lt 0) { $keep = 0 }
    }
    $cmd = $Command.Substring(0, $keep)
    # .NET counts UTF-16 units, so a cut can land between the halves of a
    # surrogate pair. Encoding a lone surrogate yields U+FFFD, which no decoder
    # can undo, so the orphaned half goes.
    if ($cmd.Length -gt 0 -and [char]::IsHighSurrogate($cmd[$cmd.Length - 1])) {
        $cmd = $cmd.Substring(0, $cmd.Length - 1)
    }
    # An even run of trailing backslashes is whole escape pairs; an odd run
    # means the cut landed inside one, so the last backslash goes.
    $run = 0
    for ($i = $cmd.Length - 1; $i -ge 0 -and $cmd[$i] -eq '\'; $i--) { $run++ }
    if ($run % 2) { $cmd = $cmd.Substring(0, $cmd.Length - 1) }
    return "$Head`t$cmd\+"
}

function Write-SkellRecord($Ok, $LastExit) {
    $entry = Get-History -Count 1
    if (-not $entry -or $entry.Id -eq $script:SkellLastId) { return }
    $script:SkellLastId = $entry.Id

    $raw = $entry.CommandLine
    if ([string]::IsNullOrEmpty($raw) -or $raw.StartsWith(' ')) { return }

    # A native command sets LASTEXITCODE; a PowerShell error leaves whatever
    # the last native command put there, so LASTEXITCODE alone would record a
    # stale code. The newest error record names the line it was raised from,
    # and matching that line against the command just run tells the two apart.
    $code = 0
    if (-not $Ok) {
        $code = if ($LastExit) { $LastExit } else { 1 }
        if ($global:error.Count -gt 0) {
            $line = $global:error[0].InvocationInfo.Line
            if ($null -ne $line -and $line.Trim() -eq $raw.Trim()) { $code = 1 }
        }
    }

    $cmd = Get-SkellEscapedField $raw

    # Only the FileSystem provider has a path that the other shells could
    # match; a registry or certificate location records as unknown.
    $cwd = 'unknown'
    if ($PWD.Provider.Name -eq 'FileSystem') {
        # The POSIX halves write an MSYS2 path, so the drive-letter form is
        # folded to match.
        $cwd = $PWD.ProviderPath.Replace('\', '/')
        if ($cwd.Length -ge 2 -and $cwd[1] -eq ':') {
            $cwd = '/' + [char]::ToLowerInvariant($cwd[0]) + $cwd.Substring(2)
        }
        # A directory holding a tab or a newline would shift every field that
        # follows it.
        $cwd = Get-SkellEscapedField $cwd
    }

    $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $record = Get-SkellFittedRecord "$stamp`t$cwd`t$code`tpwsh" $cmd

    $stream = Open-SkellStore
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($record + "`n")
        $stream.Write($bytes, 0, $bytes.Length)
    } finally {
        $stream.Dispose()
    }
}

# PSReadLine allows one AddToHistoryHandler, so the handler already in place is
# captured and consulted first: a command it rejects stays out of PSReadLine's
# history. Write-SkellRecord checks the leading space again, so replacing this
# handler later cannot put the command in the store.
if (Get-Command Set-PSReadLineOption -ErrorAction Ignore) {
    $script:SkellPriorHistoryHandler = (Get-PSReadLineOption).AddToHistoryHandler
    Set-PSReadLineOption -AddToHistoryHandler {
        param([string]$line)
        if ($line.StartsWith(' ')) {
            return [Microsoft.PowerShell.AddToHistoryOption]::SkipAdding
        }
        if ($script:SkellPriorHistoryHandler) {
            # PSReadLine returns a Func[string, object] rather than a
            # ScriptBlock, and the call operator rejects a delegate.
            return $script:SkellPriorHistoryHandler.Invoke($line)
        }
        return [Microsoft.PowerShell.AddToHistoryOption]::MemoryAndFile
    }.GetNewClosure()
}

# Import skell after starship and zoxide: the wrapper defined last runs first,
# which is the only point where $? still belongs to the user's command. $? and
# $LASTEXITCODE are put back before the inner prompt reads them.
if (-not $script:SkellHooked) {
    $script:SkellHooked = $true
    # Seeding from the session's current entry keeps a re-import from recording
    # a command that ran before the import.
    $script:SkellLastId = (Get-History -Count 1).Id
    if ($null -eq $script:SkellLastId) { $script:SkellLastId = -1 }
    $script:SkellInnerPrompt = $function:prompt

    Set-Item -Path function:global:prompt -Value {
        $ok = $global:?
        $lastExit = $global:LASTEXITCODE

        Write-SkellRecord $ok $lastExit

        # The LASTEXITCODE assignment leaves $? true on its own, so only the
        # false case needs an action, and it has to run last before the inner
        # prompt reads $?.
        $global:LASTEXITCODE = $lastExit
        if (-not $ok) { Write-Error '' -ErrorAction Ignore }

        if ($null -ne $script:SkellInnerPrompt) { & $script:SkellInnerPrompt }
    }.GetNewClosure()
}

# gawk writes the ranked file itself: `>` would decode the native command's
# stdout and re-encode every non-ASCII command in the store. PowerShell has no
# input redirection, so the file is read back and piped, with the console and
# pipeline encodings pinned to UTF-8 for the length of the call. The preview
# runs gawk rather than a nested pwsh, whose startup cost is several times
# skim's whole debounce budget.
if (Get-Command Set-PSReadLineKeyHandler -ErrorAction Ignore) {
    Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -BriefDescription 'Search skell history' -ScriptBlock {
        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        $store = [System.IO.FileInfo]::new($env:SKELL_HISTORY)
        if (-not $store.Exists -or $store.Length -eq 0) { return }

        $rank = Get-SkellRankPath

        # gawk's -v processes escape sequences in the value, so a path spelled
        # with backslashes loses every one that precedes a letter.
        $rankArg = $rank.Replace('\', '/')
        $awkDir = (Join-Path -Path $env:SKELL_ROOT -ChildPath 'share').Replace('\', '/')
        # A ranked file left by an earlier keypress must not stand in for this
        # one when gawk fails.
        if ([System.IO.File]::Exists($rank)) { Remove-Item -LiteralPath $rank -Force }
        & gawk -f "$awkDir/rank.awk" -v "out=$rankArg" $env:SKELL_HISTORY
        if ($LASTEXITCODE -ne 0 -or -not [System.IO.File]::Exists($rank)) { return }
        if (([System.IO.FileInfo]::new($rank)).Length -eq 0) { return }

        $consoleEncoding = [Console]::OutputEncoding
        $pipeEncoding = $OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
            $OutputEncoding = [System.Text.UTF8Encoding]::new()
            $chosen = @([System.IO.File]::ReadAllLines($rank) | & sk `
                    --height '60%' --min-height 15 --layout=reverse --border rounded `
                    --prompt 'history > ' --info inline --ansi `
                    --delimiter "`t" --with-nth '6..' `
                    --tiebreak score,index `
                    --query $line `
                    --preview "gawk -f `"$awkDir/codec.awk`" -f `"$awkDir/preview-history.awk`" -v n={1} `"$rankArg`"" `
                    --preview-window 'right:55%:wrap' `
                    --bind 'enter:accept(edit),alt-enter:accept(run)')
        } finally {
            [Console]::OutputEncoding = $consoleEncoding
            $OutputEncoding = $pipeEncoding
        }

        if ($chosen.Count -lt 2) {
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
            return
        }
        $fields = $chosen[1].Split("`t", 6)
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, (Convert-SkellEscape $fields[5]))
        [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
        if ($chosen[0] -eq 'run') {
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        }
    }
}

# Remove-Module leaves the wrapped prompt and the history handler pointing at a
# module that is gone, so both are put back as they were found.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    if ($null -ne $script:SkellInnerPrompt) {
        Set-Item -Path function:global:prompt -Value $script:SkellInnerPrompt
    } else {
        Remove-Item -Path function:global:prompt -ErrorAction Ignore
    }
    if (Get-Command Set-PSReadLineOption -ErrorAction Ignore) {
        Set-PSReadLineOption -AddToHistoryHandler $script:SkellPriorHistoryHandler
    }
    Remove-Item -LiteralPath (Get-SkellRankPath) -Force -ErrorAction Ignore
}

Export-ModuleMember -Function Convert-SkellEscape, Get-SkellEscapedField,
Get-SkellFittedRecord, Write-SkellRecord
