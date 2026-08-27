#!/usr/bin/env pwsh
# Check that importing, re-importing, and removing the module leave the session
# as they found it, and that the wrapped prompt still reports the status of the
# command the user ran.

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

# A sentinel prompt stands in for whatever starship or zoxide left behind.
Set-Item -Path function:global:prompt -Value { "SENTINEL> " }
$sentinel = $function:prompt.ToString()

Import-Module $ModulePath -Force
Assert-True 'import replaces the prompt' ($function:prompt.ToString() -ne $sentinel)
Assert-True 'import keeps the inner prompt reachable' ((prompt) -match 'SENTINEL')

# A second import must not wrap the wrapper: the inner prompt would then run
# twice per prompt. A scriptblock's ToString() is the source text from the psm1
# and is identical at any nesting depth, so nesting is counted by how many times
# the innermost prompt actually runs.
Remove-Module Skell
$global:SkellProbeCalls = 0
Set-Item -Path function:global:prompt -Value { $global:SkellProbeCalls++; "SENTINEL> " }
$counting = $function:prompt.ToString()
Import-Module $ModulePath -Force
Import-Module $ModulePath -Force
Import-Module $ModulePath -Force
$global:SkellProbeCalls = 0
$null = prompt
Assert-Equal 'three imports leave one inner prompt' '1' "$($global:SkellProbeCalls)"

Remove-Module Skell
Assert-Equal 'remove restores the prior prompt' $counting $function:prompt.ToString()
Assert-Equal 'restored prompt still renders' 'SENTINEL> ' (prompt)

Import-Module $ModulePath -Force
Assert-True 'reimport wraps the prompt again' ($function:prompt.ToString() -ne $sentinel)
Assert-True 'reimport keeps the inner prompt reachable' ((prompt) -match 'SENTINEL')

# The wrapper reads $? and $LASTEXITCODE before anything else and puts both back
# for the inner prompt. Removing the module first restores the sentinel, so the
# reporting prompt is installed after the removal and before the import that
# wraps it. It captures $? as its first statement, as a real prompt does.
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

Remove-Module Skell

Assert-True 'store stayed inside the sandbox' `
  ($env:SKELL_HISTORY.Replace('\', '/').StartsWith($Sandbox.Replace('\', '/')))

Write-Host "lifecycle-pwsh: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
