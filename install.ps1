# teamAI toolkit installer for Windows PowerShell 5.1+
# Usage: powershell -ExecutionPolicy Bypass -File .\install.ps1
# Installs the pstack and teamai plugins. Safe to run again.
# (ASCII only on purpose: PowerShell 5.1 misreads UTF-8 scripts without a BOM.)
$Repo = "teamaitwsg-redflag/teamai-pstack"

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host "claude command not found. Install Claude Code first, then run this again." -ForegroundColor Red
    exit 1
}

$ErrorActionPreference = "Continue"
claude plugin marketplace add michael-denyer/pstack-claude
claude plugin install pstack@pstack-claude
claude plugin marketplace add $Repo
claude plugin install teamai@teamai-pstack

Write-Host ""
Write-Host "Done. Open a new Claude Code session, then type /teamai:flow" -ForegroundColor Green
