# Update the pstack and teamai plugins (Windows PowerShell 5.1+)
# Stops at the first failing step, exits with that step's exit code, and does not print the success message.
# (ASCII only on purpose: PowerShell 5.1 misreads UTF-8 scripts without a BOM.)
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host "claude command not found. Install Claude Code first, then run this again." -ForegroundColor Red
    exit 1
}

# A native command's non-zero exit code does not raise an error in PowerShell,
# so every call is followed by an explicit $LASTEXITCODE check.
$ErrorActionPreference = "Stop"
claude plugin marketplace update pstack-claude
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
claude plugin update pstack@pstack-claude
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
claude plugin marketplace update teamai-pstack
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
claude plugin update teamai@teamai-pstack
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Updated. Open a new session to apply." -ForegroundColor Green
