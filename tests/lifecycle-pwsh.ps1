#!/usr/bin/env pwsh
param(
    [Parameter(Mandatory)][string]$ModulePath,
    [Parameter(Mandatory)][string]$Sandbox
)

$ErrorActionPreference = 'Stop'
$pass = 0
$fail = 0

function Assert-Equal([string]$Label, [string]$Want, [string]$Got) {
    if ($Want -ceq $Got) { $script:pass++ } else {
        $script:fail++
        Write-Host "  FAIL $Label"
        Write-Host "       want [$Want]"
        Write-Host "       got  [$Got]"
    }
}

function Assert-True([string]$Label, [bool]$Condition) {
    if ($Condition) { $script:pass++ } else {
        $script:fail++
        Write-Host "  FAIL $Label"
    }
}

# Use a sentinel prompt as the pre-existing prompt.
Set-Item -Path function:global:prompt -Value { "SENTINEL> " }
$sentinel = $function:prompt.ToString()

Import-Module $ModulePath -Force
Assert-True 'import replaces the prompt' ($function:prompt.ToString() -ne $sentinel)
Assert-True 'import keeps the inner prompt reachable' ((prompt) -match 'SENTINEL')

Remove-Module Skell
$global:SkellProbeCalls = 0
Set-Item -Path function:global:prompt -Value { $global:SkellProbeCalls++; "SENTINEL> " }
$priorPrompt = $function:prompt.ToString()
Import-Module $ModulePath -Force
Import-Module $ModulePath -Force
Import-Module $ModulePath -Force
$global:SkellProbeCalls = 0
$null = prompt
Assert-Equal 'three imports leave one inner prompt' '1' "$($global:SkellProbeCalls)"

Remove-Module Skell
Assert-Equal 'remove restores the prior prompt' $priorPrompt $function:prompt.ToString()
Assert-Equal 'restored prompt still renders' 'SENTINEL> ' (prompt)

Import-Module $ModulePath -Force
Assert-True 'reimport wraps the prompt again' ($function:prompt.ToString() -ne $sentinel)
Assert-True 'reimport keeps the inner prompt reachable' ((prompt) -match 'SENTINEL')

Remove-Module Skell
Set-Item -Path function:global:prompt -Value { $q = $?; "exit=$LASTEXITCODE ok=$q" }
Import-Module $ModulePath -Force

& pwsh -NoLogo -NoProfile -Command 'exit 3'
$rendered = prompt
Assert-True 'wrapped prompt sees the native exit code' ($rendered -match 'exit=3')
Assert-True 'wrapped prompt sees a false $?' ($rendered -match 'ok=False')

& pwsh -NoLogo -NoProfile -Command 'exit 0'
$rendered = prompt
Assert-True 'wrapped prompt sees a zero exit code' ($rendered -match 'exit=0')
Assert-True 'wrapped prompt sees a true $?' ($rendered -match 'ok=True')

# The harness cannot drive a line editor; test the resolver directly.
$fake = Join-Path -Path $Sandbox -ChildPath 'fake-gawk.exe'
Set-Content -LiteralPath $fake -Value 'not an executable' -NoNewline
$priorOverride = $env:SKELL_GAWK
try {
    $env:SKELL_GAWK = $fake
    Assert-Equal 'an existing SKELL_GAWK wins' $fake (Get-SkellGawkPath)

    $env:SKELL_GAWK = Join-Path -Path $Sandbox -ChildPath 'absent-gawk.exe'
    Assert-True 'a missing SKELL_GAWK resolves to nothing' ($null -eq (Get-SkellGawkPath))

    $env:SKELL_GAWK = ''
    $resolved = Get-SkellGawkPath
    Assert-True 'an unset SKELL_GAWK resolves to a file or to nothing' `
      ($null -eq $resolved -or [System.IO.File]::Exists($resolved))

    if ($IsWindows) {
        $pathDir = Join-Path -Path $Sandbox -ChildPath 'path-gawk'
        $null = New-Item -ItemType Directory -Force -Path $pathDir
        $pathGawk = Join-Path -Path $pathDir -ChildPath 'gawk.exe'
        Set-Content -LiteralPath $pathGawk -Value 'not an executable' -NoNewline
        $priorPath = $env:PATH
        try {
            $env:PATH = "$pathDir;$priorPath"
            $resolved = Get-SkellGawkPath
            Assert-True 'Windows skips a gawk on PATH' ($resolved -ne $pathGawk)
            # A registered MSYS2 elsewhere takes precedence over C:\msys64.
            $elsewhere = @('HKCU:', 'HKLM:' | ForEach-Object {
                    Get-ChildItem -Path "$_\Software\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction Ignore
                } | Where-Object {
                    $_.GetValue('Publisher') -eq 'The MSYS2 Developers' -and
                    ([string]$_.GetValue('InstallLocation')).TrimEnd('\') -ine 'C:\msys64'
                })
            if ([System.IO.File]::Exists('C:\msys64\usr\bin\gawk.exe') -and $elsewhere.Count -eq 0) {
                Assert-True 'Windows prefers MSYS2 gawk' ($resolved -ieq 'C:\msys64\usr\bin\gawk.exe')
            }
        } finally {
            $env:PATH = $priorPath
        }
    }
} finally {
    $env:SKELL_GAWK = $priorOverride
}

Remove-Module Skell

if ((Get-Command Set-PSReadLineKeyHandler -ErrorAction Ignore) -and
    (Get-Command Get-PSReadLineKeyHandler -ErrorAction Ignore)) {
    Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -Function ReverseSearchHistory
    Import-Module $ModulePath -Force
    $handler = Get-PSReadLineKeyHandler -Chord 'Ctrl+r'
    Assert-Equal 'import installs the Ctrl+R handler' 'Search skell history' $handler.Function
    Remove-Module Skell
    $handler = Get-PSReadLineKeyHandler -Chord 'Ctrl+r'
    Assert-Equal 'remove restores the prior Ctrl+R handler' 'ReverseSearchHistory' $handler.Function

    Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -BriefDescription 'Existing Ctrl R' -ScriptBlock { }
    Import-Module $ModulePath -Force
    $handler = Get-PSReadLineKeyHandler -Chord 'Ctrl+r'
    Assert-Equal 'import preserves a custom Ctrl+R handler' 'Existing Ctrl R' $handler.Function
    Remove-Module Skell
    $handler = Get-PSReadLineKeyHandler -Chord 'Ctrl+r'
    Assert-Equal 'remove preserves the original custom Ctrl+R handler' 'Existing Ctrl R' $handler.Function

    Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -Function ReverseSearchHistory
    Import-Module $ModulePath -Force
    Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -BriefDescription 'Later Ctrl R' -ScriptBlock { }
    Remove-Module Skell
    $handler = Get-PSReadLineKeyHandler -Chord 'Ctrl+r'
    Assert-Equal 'remove preserves a later custom Ctrl+R handler' 'Later Ctrl R' $handler.Function
}

if ((Get-Command Set-PSReadLineKeyHandler -ErrorAction Ignore) -and
    (Get-Command Get-PSReadLineKeyHandler -ErrorAction Ignore)) {
    Set-PSReadLineKeyHandler -Chord 'Tab' -Function TabCompleteNext
    Set-PSReadLineKeyHandler -Chord 'Shift+Tab' -Function TabCompletePrevious
    Import-Module $ModulePath -Force
    Assert-Equal 'import installs the Tab handler' 'Complete with skell' (Get-PSReadLineKeyHandler -Chord 'Tab').Function
    Assert-Equal 'import binds Shift+Tab to MenuComplete' 'MenuComplete' (Get-PSReadLineKeyHandler -Chord 'Shift+Tab').Function
    Remove-Module Skell
    Assert-Equal 'remove restores the prior Tab handler' 'TabCompleteNext' (Get-PSReadLineKeyHandler -Chord 'Tab').Function
    Assert-Equal 'remove restores the prior Shift+Tab handler' 'TabCompletePrevious' (Get-PSReadLineKeyHandler -Chord 'Shift+Tab').Function

    Set-PSReadLineKeyHandler -Chord 'Tab' -BriefDescription 'Existing Tab' -ScriptBlock { }
    Import-Module $ModulePath -Force
    Assert-Equal 'import preserves a custom Tab handler' 'Existing Tab' (Get-PSReadLineKeyHandler -Chord 'Tab').Function
    Remove-Module Skell
    Assert-Equal 'remove preserves the custom Tab handler' 'Existing Tab' (Get-PSReadLineKeyHandler -Chord 'Tab').Function
    Set-PSReadLineKeyHandler -Chord 'Tab' -Function TabCompleteNext
}

Import-Module $ModulePath -Force
$skell = Get-Module Skell
Assert-Equal 'prefix ignores case' 'Get-Ch' (& $skell { Get-SkellCommonPrefix @('Get-ChildItem', 'get-chocolate') })
Assert-Equal 'prefix of disjoint texts is empty' '' (& $skell { Get-SkellCommonPrefix @('alpha', 'beta') })
Assert-Equal 'visible renders controls' 'a<0x1B>]0;t<0x07>b<0x9D>' `
  (& $skell { ConvertTo-SkellVisible "a`e]0;t`ab$([char]0x9d)" })

function New-Match([string]$Text, [string]$Type, [string]$Tip = $Text, [string]$Label = $Text) {
    [System.Management.Automation.CompletionResult]::new($Text, $Label, $Type, $Tip)
}
$sep = [System.IO.Path]::DirectorySeparatorChar
Assert-Equal 'a parameter keeps its tooltip' '[switch] Force' `
  (& $skell { Get-SkellCompletionDescription $args[0] } (New-Match '-Force' 'ParameterName' '[switch] Force' 'Force'))
Assert-Equal 'a file drops its path tooltip' '' `
  (& $skell { Get-SkellCompletionDescription $args[0] } (New-Match './a.txt' 'ProviderItem' '/tmp/a.txt' 'a.txt'))
Assert-Equal 'an executable drops its path tooltip' '' `
  (& $skell { Get-SkellCompletionDescription $args[0] } (New-Match 'git' 'Command' '/usr/bin/git'))
Assert-Equal 'a tooltip folds newlines' 'Get-Item [-Path] <string[]>' `
  (& $skell { Get-SkellCompletionDescription $args[0] } (New-Match 'Get-Item' 'Command' "`r`nGet-Item [-Path] <string[]>`r`n"))
Assert-Equal 'a single directory gets a separator' "./d$sep" `
  (& $skell { Join-SkellCompletion @($args[0]) 'Get-Item ./d' 9 } (New-Match './d' 'ProviderContainer'))
Assert-Equal 'a quoted directory gets the separator inside the quote' "'./a b$sep'" `
  (& $skell { Join-SkellCompletion @($args[0]) "Get-Item './a b'" 9 } (New-Match "'./a b'" 'ProviderContainer'))
Assert-Equal 'cmdlet values join with commas' './a,./b' `
  (& $skell { Join-SkellCompletion $args 'Get-Item ./' 9 } (New-Match './a' 'ProviderItem') (New-Match './b' 'ProviderItem'))
Assert-Equal 'empty cmdlet values join with commas' './a,./b' `
  (& $skell { Join-SkellCompletion $args 'Get-Item ' 9 } (New-Match './a' 'ProviderItem') (New-Match './b' 'ProviderItem'))
Assert-Equal 'empty cmdlet values after a parameter join with commas' 'a,b' `
  (& $skell { Join-SkellCompletion $args 'Get-Process -Name ' 18 } (New-Match 'a' 'ParameterValue') (New-Match 'b' 'ParameterValue'))
Assert-Equal 'values join with spaces after a pipeline ends' './a ./b' `
  (& $skell { Join-SkellCompletion $args 'Get-Item a; ' 12 } (New-Match './a' 'ProviderItem') (New-Match './b' 'ProviderItem'))
Assert-Equal 'a dynamic command name joins with spaces' './a ./b' `
  (& $skell { Join-SkellCompletion $args '& $exe ' 7 } (New-Match './a' 'ProviderItem') (New-Match './b' 'ProviderItem'))
Assert-Equal 'parameter names join with spaces' '-Force -File' `
  (& $skell { Join-SkellCompletion $args 'Get-ChildItem -F' 14 } (New-Match '-Force' 'ParameterName') (New-Match '-File' 'ParameterName'))
Assert-Equal 'command names join with spaces' 'Get-Item Get-Date' `
  (& $skell { Join-SkellCompletion $args 'Get-' 0 } (New-Match 'Get-Item' 'Command') (New-Match 'Get-Date' 'Command'))
$native = @(Get-Command -CommandType Application -ErrorAction Ignore | Where-Object Name -Match '^[\w.-]+$' | Select-Object -First 1)[0]
if ($native) {
    Assert-Equal 'native command values join with spaces' './a ./b' `
      (& $skell { Join-SkellCompletion $args[1..2] "$($args[0]) ./" ($args[0].Length + 1) } $native.Name (New-Match './a' 'ProviderItem') (New-Match './b' 'ProviderItem'))
}
Remove-Module Skell

Assert-True 'store stayed inside the sandbox' `
  ($env:SKELL_HISTORY.Replace('\', '/').StartsWith($Sandbox.Replace('\', '/')))

Write-Host "lifecycle-pwsh: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
