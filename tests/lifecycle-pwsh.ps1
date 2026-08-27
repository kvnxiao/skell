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
} finally {
    $env:SKELL_GAWK = $priorOverride
}

Remove-Module Skell

Assert-True 'store stayed inside the sandbox' `
  ($env:SKELL_HISTORY.Replace('\', '/').StartsWith($Sandbox.Replace('\', '/')))

Write-Host "lifecycle-pwsh: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
