# Fake-claude tests for install.ps1 and update.ps1. Runs on Windows only (CI).
# Each script runs under Windows PowerShell 5.1 and, if present, PowerShell 7.
# A failing claude call must stop the script, keep its exit code, and suppress the success message.
# Nothing here calls the real claude or changes machine settings: the child processes get
# -ExecutionPolicy Bypass for that process only, and PATH is changed for the child only.
# (ASCII only on purpose: PowerShell 5.1 misreads UTF-8 scripts without a BOM.)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('teamai-pstest-' + [guid]::NewGuid())
$bin = Join-Path $tmp 'bin'
New-Item -ItemType Directory -Path $bin -Force | Out-Null
$calls = Join-Path $tmp 'calls.txt'

# Fake claude: append one line per call; fail on call number FAIL_AT (or every call when FAIL_AT=all).
$fake = @'
@echo off
echo %*>>"%CALLS%"
set N=0
for /f %%c in ('type "%CALLS%" ^| find /c /v ""') do set N=%%c
if "%FAIL_AT%"=="all" goto fail
if "%FAIL_AT%"=="%N%" goto fail
exit /b 0
:fail
echo fake claude: failure on call %N% 1>&2
exit /b %FAIL_CODE%
'@
Set-Content -Path (Join-Path $bin 'claude.cmd') -Value $fake -Encoding ASCII

$shells = @("$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe")
$pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
if ($pwsh) { $shells += $pwsh.Source }
$sysPath = "$env:SystemRoot\System32;$env:SystemRoot"
$savedPath = $env:PATH
$script:pass = 0; $script:fail = 0

function Check([string]$name, [bool]$ok) {
    if ($ok) { $script:pass++; Write-Host "  PASS: $name" } else { $script:fail++; Write-Host "  FAIL: $name" }
}

function Invoke-Case([string]$shell, [string]$script, [string]$failAt, [bool]$withClaude) {
    New-Item -ItemType File -Path $calls -Force | Out-Null
    $env:CALLS = $calls; $env:FAIL_AT = $failAt; $env:FAIL_CODE = '7'
    if ($withClaude) { $env:PATH = "$bin;$sysPath" } else { $env:PATH = $sysPath }
    $out = & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root $script) 2>&1 | Out-String
    $rc = $LASTEXITCODE
    $env:PATH = $savedPath
    $n = @(Get-Content $calls | Where-Object { $_ -ne '' }).Count
    return @{ rc = $rc; calls = $n; out = $out }
}

foreach ($shell in $shells) {
    $ver = & $shell -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
    foreach ($spec in @(@('install.ps1', 'Done\.'), @('update.ps1', 'Updated\.'))) {
        $script = $spec[0]; $okRe = $spec[1]
        Write-Host "== $script under PowerShell $ver"
        $r = Invoke-Case $shell $script '0' $true
        Check 'all steps succeed: exit 0, 4 calls, success printed' (($r.rc -eq 0) -and ($r.calls -eq 4) -and ($r.out -match $okRe))
        foreach ($k in 1..4) {
            $r = Invoke-Case $shell $script "$k" $true
            Check "step $k fails: stops after call $k, exit 7, no success message" (($r.rc -eq 7) -and ($r.calls -eq $k) -and -not ($r.out -match $okRe))
        }
        $r = Invoke-Case $shell $script '0' $false
        Check 'claude not found: exit 1, no calls, no success message' (($r.rc -eq 1) -and ($r.calls -eq 0) -and -not ($r.out -match $okRe))
    }
}

Remove-Item -Recurse -Force $tmp
Write-Host ""
Write-Host "install.ps1 / update.ps1 tests: pass $($script:pass), fail $($script:fail)"
if ($script:fail -ne 0) { exit 1 }
exit 0
