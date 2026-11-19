# Update the pstack and teamai plugins (Windows PowerShell 5.1+)
$ErrorActionPreference = "Continue"
claude plugin marketplace update pstack-claude
claude plugin update pstack@pstack-claude
claude plugin marketplace update teamai-pstack
claude plugin update teamai@teamai-pstack
Write-Host "Updated. Open a new session to apply." -ForegroundColor Green
