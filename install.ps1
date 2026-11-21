# teamAI toolkit installer for Windows PowerShell 5.1+
# Usage: powershell -ExecutionPolicy Bypass -File .\install.ps1
# Installs the pstack and teamai plugins. Safe to run again.
# Stops at the first failing step, exits with that step's exit code, and does not print the success message.
# (ASCII only on purpose: PowerShell 5.1 misreads UTF-8 scripts without a BOM.)
$Repo = "teamaitwsg-redflag/teamai-pstack"

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host "claude command not found. Install Claude Code first, then run this again." -ForegroundColor Red
    exit 1
}

# A native command's non-zero exit code does not raise an error in PowerShell,
# so every call is followed by an explicit $LASTEXITCODE check.
$ErrorActionPreference = "Stop"
claude plugin marketplace add michael-denyer/pstack-claude
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
claude plugin install pstack@pstack-claude
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
claude plugin marketplace add $Repo
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
claude plugin install teamai@teamai-pstack
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Done. Open a new Claude Code session, then type /teamai:flow" -ForegroundColor Green
