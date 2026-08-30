# skell -- one command history for bash, fish, powershell, and zsh.
# https://github.com/kvnxiao/skell

if ($PSVersionTable.PSVersion -lt [version]'7.4') {
    throw 'skell: PowerShell 7.4 or newer is required'
}

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

# The history store contains recorded commands. Unix mode bits are set directly;
# Windows replaces inherited ACL entries with one entry for the current account
# because profile directories can inherit broader rights.
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
    $createdStore = $false
    try {
        $stream = [System.IO.FileStream]::new(
            $env:SKELL_HISTORY,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::ReadWrite)
        $createdStore = $true
        $stream.Dispose()
    } catch [System.IO.IOException] {
        if (-not [System.IO.File]::Exists($env:SKELL_HISTORY)) { throw }
    }
    if ($createdStore) {
        try { Set-SkellPrivateAcl $env:SKELL_HISTORY } catch {
            Write-Warning "skell: could not restrict $env:SKELL_HISTORY : $($_.Exception.Message)"
        }
    }
}

# A lock acquired with MSYS2's `flock` and a Windows named mutex do not
# coordinate, so no lock spans these shells. FILE_APPEND_DATA reaches the same
# kernel atomic append as Cygwin's O_APPEND, which is the only coordination
# between PowerShell and the POSIX halves.
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

# The ranked files are plaintext dumps of the whole history, so keep them in
# skell's own directory rather than a temp directory shared with every other
# user of the machine. MSYS2 and Windows number processes separately, so their
# names include the shell and process ID.
function Get-SkellRankPath {
    return Join-Path -Path $env:SKELL_DATA_DIR -ChildPath "rank-pwsh-$PID.tsv"
}

function Get-SkellRawRankPath {
    return Join-Path -Path $env:SKELL_DATA_DIR -ChildPath "rank-pwsh-$PID.raw.tsv"
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

# Concurrent appends do not tear records up to 1024 bytes on NTFS through the
# Cygwin and MSYS2 runtimes, which are covered by skell's tests. A
# record holding any non-ASCII code point is capped at a quarter of the budget,
# since four bytes is the widest UTF-8 encoding and a byte count would need a
# second pass. .NET counts UTF-16 units, as bash and zsh do under Cygwin's
# 16-bit wchar_t, while gawk and fish count code points. Both counts keep the
# record inside 1000 bytes, so a command outside the BMP is cut at a different
# point depending on which shell recorded it.
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
        # Replacing the directory can make the record fit without cutting the
        # command. Return it without `\+`; that marker means the command was cut.
        if ($record.Length -le $limit) { return $record }
        $keep = $limit - $Head.Length - 3
        if ($keep -lt 0) { $keep = 0 }
    }
    $cmd = $Command.Substring(0, $keep)
    # .NET counts UTF-16 units, so a cut can split a surrogate pair. Encoding a
    # lone surrogate yields U+FFFD, which no decoder can reverse; drop the
    # orphaned half.
    if ($cmd.Length -gt 0 -and [char]::IsHighSurrogate($cmd[$cmd.Length - 1])) {
        $cmd = $cmd.Substring(0, $cmd.Length - 1)
    }
    # Keep complete escape pairs: an odd trailing backslash run means the cut
    # landed inside one, so drop its last backslash.
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

    # A PowerShell error leaves the previous native command's $LASTEXITCODE in
    # place. Match the newest error record's invocation line to the command
    # before recording status 1.
    $code = 0
    if (-not $Ok) {
        $code = if ($LastExit) { $LastExit } else { 1 }
        if ($global:error.Count -gt 0) {
            $line = $global:error[0].InvocationInfo.Line
            if ($null -ne $line -and $line.Trim() -eq $raw.Trim()) { $code = 1 }
        }
    }

    $cmd = Get-SkellEscapedField $raw

    # Only the FileSystem provider supplies a path that the other shells can
    # match; record registry or certificate locations as unknown.
    $cwd = 'unknown'
    if ($PWD.Provider.Name -eq 'FileSystem') {
        # POSIX writers use an MSYS2 path, so normalize a drive-letter path to
        # match.
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

# PSReadLine accepts one AddToHistoryHandler, so preserve and consult the
# existing handler for commands without a leading space. Write-SkellRecord
# repeats the leading-space check after history storage.
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

        # Assigning $LASTEXITCODE sets $? to true. Restore a false captured
        # status after the assignment and before the inner prompt runs.
        $global:LASTEXITCODE = $lastExit
        if (-not $ok) { Write-Error '' -ErrorAction Ignore }

        if ($null -ne $script:SkellInnerPrompt) { & $script:SkellInnerPrompt }
    }.GetNewClosure()
}

# Windows PowerShell uses the native PATH, which excludes MSYS2's and Git for
# Windows' usr\bin. If SKELL_GAWK is set, use only that path; otherwise check
# PATH, git's usr\bin, and C:\msys64\usr\bin in that order.
function Get-SkellGawkPath {
    if ($env:SKELL_GAWK) {
        if ([System.IO.File]::Exists($env:SKELL_GAWK)) { return $env:SKELL_GAWK }
        return $null
    }
    # Select the first PATH match because the caller invokes the returned path
    # directly.
    $onPath = @(Get-Command gawk -CommandType Application -ErrorAction Ignore)[0]
    if ($onPath) { return $onPath.Source }
    if (-not $IsWindows) { return $null }

    $candidates = @()
    $git = @(Get-Command git -CommandType Application -ErrorAction Ignore)[0]
    if ($git) {
        $gitRoot = Split-Path -Parent (Split-Path -Parent $git.Source)
        $candidates += Join-Path -Path $gitRoot -ChildPath 'usr' -AdditionalChildPath 'bin', 'gawk.exe'
    }
    $candidates += 'C:\msys64\usr\bin\gawk.exe'
    foreach ($candidate in $candidates) {
        if ([System.IO.File]::Exists($candidate)) { return $candidate }
    }
    return $null
}

# When a native command runs in a PSReadLine key handler, the handler's pipeline
# collects and discards every stream. Skim draws its interface on stderr, so
# redirect only stdin and stdout.
function Invoke-SkellSearch([string]$SkPath, [string[]]$SkArgs, [string[]]$Lines, [string]$GawkDir) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $SkPath
    foreach ($arg in $SkArgs) { $psi.ArgumentList.Add($arg) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.StandardInputEncoding = [System.Text.UTF8Encoding]::new()
    $psi.StandardOutputEncoding = [System.Text.UTF8Encoding]::new()
    # Only sk and the preview processes it spawns get gawk's directory on PATH.
    $psi.Environment['PATH'] = "$GawkDir$([System.IO.Path]::PathSeparator)$($psi.Environment['PATH'])"

    $proc = [System.Diagnostics.Process]::Start($psi)
    # Start the stdout read before writing candidates; a full pipe would stall
    # sk while skell feeds it.
    $reading = $proc.StandardOutput.ReadToEndAsync()
    foreach ($item in $Lines) { $proc.StandardInput.WriteLine($item) }
    $proc.StandardInput.Close()
    $proc.WaitForExit()
    return @(($reading.GetAwaiter().GetResult() -split "\r?\n") | Where-Object { $_.Length -gt 0 })
}

# Pass the ranked-file paths with gawk variables; PowerShell redirection would
# decode gawk's stdout and re-encode non-ASCII command text. The preview runs
# gawk directly instead of starting a nested pwsh process.
$script:SkellOwnsCtrlR = $false
$setKeyHandlerCommand = Get-Command Set-PSReadLineKeyHandler -ErrorAction Ignore
$getKeyHandlerCommand = Get-Command Get-PSReadLineKeyHandler -ErrorAction Ignore
if ($setKeyHandlerCommand -and $getKeyHandlerCommand) {
    $script:SkellPriorCtrlRHandler = @(Get-PSReadLineKeyHandler -Chord 'Ctrl+r' -ErrorAction Ignore)[0]
}
if ($setKeyHandlerCommand -and $getKeyHandlerCommand -and
    (-not $script:SkellPriorCtrlRHandler -or $script:SkellPriorCtrlRHandler.Group -ne 'Custom')) {
    Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -BriefDescription 'Search skell history' -ScriptBlock {
        # PSReadLine redraws through the console while skim draws on inherited
        # stderr. Keep [Console]::OutputEncoding at UTF-8 through the redraw,
        # then restore the session encoding.
        $priorEncoding = [Console]::OutputEncoding
        $rank = $null
        $rawRank = $null
        try {
            [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
            $gawk = Get-SkellGawkPath
            if (-not $gawk) {
                Write-Warning 'skell: history search found no gawk; install one or set SKELL_GAWK to its path'
                [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
                return
            }
            $sk = @(Get-Command sk -CommandType Application -ErrorAction Ignore)[0]
            if (-not $sk) {
                Write-Warning 'skell: history search needs sk on PATH'
                [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
                return
            }

            $line = $null
            $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

            $store = [System.IO.FileInfo]::new($env:SKELL_HISTORY)
            if (-not $store.Exists -or $store.Length -eq 0) { return }

            $rank = Get-SkellRankPath
            $rawRank = Get-SkellRawRankPath

            # gawk's -v interprets backslash escapes, so pass POSIX-style paths
            # instead of native paths with backslashes.
            $rankArg = $rank.Replace('\', '/')
            $rawRankArg = $rawRank.Replace('\', '/')
            $awkDir = (Join-Path -Path $env:SKELL_ROOT -ChildPath 'share').Replace('\', '/')
            # Remove stale ranked files before gawk runs; a failed run must not
            # reuse them.
            if ([System.IO.File]::Exists($rank)) { Remove-Item -LiteralPath $rank -Force }
            if ([System.IO.File]::Exists($rawRank)) { Remove-Item -LiteralPath $rawRank -Force }
            try {
                $gawkArgs = @(
                    '-f', "$awkDir/codec.awk", '-f', "$awkDir/rank.awk",
                    '-v', "out=$rankArg", '-v', "raw=$rawRankArg", $env:SKELL_HISTORY)
                & $gawk @gawkArgs
            } catch {
                Write-Warning "skell: $gawk did not run: $($_.Exception.Message)"
                [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
                return
            }
            if ($LASTEXITCODE -ne 0 -or -not [System.IO.File]::Exists($rank) -or
                -not [System.IO.File]::Exists($rawRank)) { return }
            if (([System.IO.FileInfo]::new($rank)).Length -eq 0) { return }

            # cmd.exe removes the first and last quote from a preview command
            # that starts and ends with a quote, so pass the executable name
            # through PATH and quote only its arguments.
            $gawkName = [System.IO.Path]::GetFileName($gawk)
            $preview = "$gawkName -f `"$awkDir/codec.awk`" -f `"$awkDir/preview-history.awk`" -v n={1} `"$rawRankArg`""

            $skArgs = @(
                '--height', '60%', '--min-height', '15', '--layout=reverse', '--border', 'rounded',
                '--prompt', 'history > ', '--info', 'inline',
                '--delimiter', "`t", '--with-nth', '6..',
                '--tiebreak', 'score,index',
                '--query', $line,
                '--preview', $preview,
                '--preview-window', 'right:55%:wrap',
                '--bind', 'enter:accept(edit),alt-enter:accept(run)')

            $chosen = Invoke-SkellSearch -SkPath $sk.Source -SkArgs $skArgs `
                -Lines ([System.IO.File]::ReadAllLines($rank)) -GawkDir (Split-Path -Parent $gawk)

            if ($chosen.Count -lt 2) {
                [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
                return
            }
            $id = $chosen[1].Split("`t", 2)[0]
            $record = [System.IO.File]::ReadLines($rawRank) |
                Where-Object { $_.StartsWith("$id`t", [System.StringComparison]::Ordinal) } |
                Select-Object -First 1
            if ($null -eq $record) { return }
            $fields = $record.Split("`t", 6)
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, (Convert-SkellEscape $fields[5]))
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
            if ($chosen[0] -eq 'run') {
                [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
            }
        } finally {
            if ($rank) { Remove-Item -LiteralPath $rank -Force -ErrorAction Ignore }
            if ($rawRank) { Remove-Item -LiteralPath $rawRank -Force -ErrorAction Ignore }
            [Console]::OutputEncoding = $priorEncoding
        }
    }
    $script:SkellOwnsCtrlR = $true
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
    if ($script:SkellOwnsCtrlR -and
        (Get-Command Get-PSReadLineKeyHandler -ErrorAction Ignore)) {
        $currentCtrlR = @(Get-PSReadLineKeyHandler -Chord 'Ctrl+r' -ErrorAction Ignore)[0]
        if ($currentCtrlR -and $currentCtrlR.Function -eq 'Search skell history') {
            if ($script:SkellPriorCtrlRHandler) {
                Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -Function $script:SkellPriorCtrlRHandler.Function
            } elseif (Get-Command Remove-PSReadLineKeyHandler -ErrorAction Ignore) {
                Remove-PSReadLineKeyHandler -Chord 'Ctrl+r'
            }
        }
    }
    Remove-Item -LiteralPath (Get-SkellRankPath) -Force -ErrorAction Ignore
    Remove-Item -LiteralPath (Get-SkellRawRankPath) -Force -ErrorAction Ignore
}

Export-ModuleMember -Function Convert-SkellEscape, Get-SkellEscapedField,
Get-SkellFittedRecord, Get-SkellGawkPath, Write-SkellRecord
