#!/usr/bin/env pwsh
# Round-trip every codec vector through the PowerShell module's escape and
# decode, and check the fitter's boundaries. Vectors are rebuilt from their %XX
# specs so the comparison does not depend on how a file read crosses a runtime
# boundary.

param(
    [Parameter(Mandatory)][string]$VectorsTsv,
    [Parameter(Mandatory)][string]$ModulePath
)

$ErrorActionPreference = 'Stop'
$pass = 0
$fail = 0

function Assert-Equal([string]$Label, [string]$Want, [string]$Got) {
    if ($Want -ceq $Got) {
        $script:pass++
    } else {
        $script:fail++
        $w = ($Want.ToCharArray() | ForEach-Object { [int]$_ }) -join ' '
        $g = ($Got.ToCharArray() | ForEach-Object { [int]$_ }) -join ' '
        Write-Host "  FAIL $Label"
        Write-Host "       want $w"
        Write-Host "       got  $g"
    }
}

function Expand-Spec([string]$Spec) {
    $sb = [System.Text.StringBuilder]::new()
    $i = 0
    while ($i -lt $Spec.Length) {
        if ($Spec[$i] -eq '%') {
            $null = $sb.Append([char][System.Convert]::ToInt32($Spec.Substring($i + 1, 2), 16))
            $i += 3
        } else {
            $null = $sb.Append($Spec[$i])
            $i++
        }
    }
    return $sb.ToString()
}

Import-Module $ModulePath -Force

foreach ($line in [System.IO.File]::ReadAllLines($VectorsTsv)) {
    if ($line.StartsWith('#')) { continue }
    $f = $line.Split("`t")
    if ($f.Length -lt 3) { continue }
    $name = $f[0]
    $raw = Expand-Spec $f[1]
    $enc = Expand-Spec $f[2]

    Assert-Equal "escape $name" $enc (Get-SkellEscapedField $raw)
    Assert-Equal "unescape $name" $raw (Convert-SkellEscape $enc)
}

function Assert-Record([string]$Label, [string]$Record) {
    $fields = $Record.Split("`t")
    Assert-Equal "${Label}: five fields" '5' "$($fields.Length)"
    Assert-Equal "${Label}: one line" 'False' "$($Record.Contains("`n"))"
    $bytes = [System.Text.Encoding]::UTF8.GetByteCount($Record)
    if ($bytes -le 1000) { $script:pass++ } else {
        $script:fail++
        Write-Host "  FAIL ${Label}: within 1000 bytes (got $bytes)"
    }
}

Assert-Equal 'short record is preserved' "1787700487`t/d`t0`tpwsh`tgit status" `
  (Get-SkellFittedRecord "1787700487`t/d`t0`tpwsh" 'git status')

$longDir = '/' + ('d' * 1200)
$fitted = Get-SkellFittedRecord "1787700487`t$longDir`t0`tpwsh" 'git status'
Assert-Record 'oversized directory' $fitted
Assert-Equal 'oversized directory reads unknown' 'unknown' $fitted.Split("`t")[1]

foreach ($pad in 0, 1, 2, 3) {
    $cmd = ('x' * (980 + $pad)) + ('\' * 8)
    $fitted = Get-SkellFittedRecord "1787700487`t/d`t0`tpwsh" $cmd
    Assert-Record "cut at offset $pad" $fitted
    $field = $fitted.Split("`t")[4]
    $field = $field.Substring(0, $field.Length - 2)
    $run = 0
    for ($i = $field.Length - 1; $i -ge 0 -and $field[$i] -eq '\'; $i--) { $run++ }
    Assert-Equal "cut at offset ${pad}: no dangling escape" '0' "$($run % 2)"
}

Assert-Record 'non-ASCII record' (Get-SkellFittedRecord "1787700487`t/d`t0`tpwsh" ('世' * 400))

Write-Host "codec-pwsh: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
