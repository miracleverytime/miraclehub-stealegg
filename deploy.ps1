# Steal An Egg Hub - Quick Deployment Script
# Run this from PowerShell or CMD

Write-Host "================================" -ForegroundColor Cyan
Write-Host "MiracleHub-SteaLEgg Deployer" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Navigate to repository directory
$repoPath = $PSScriptRoot
Set-Location $repoPath

Write-Host "[1/5] Checking git installation..." -ForegroundColor Yellow
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Git not found! Please install Git first." -ForegroundColor Red
    exit 1
}
Write-Host "✓ Git installed" -ForegroundColor Green
Write-Host ""

Write-Host "[2/5] Initializing local repository..." -ForegroundColor Yellow
git init
Write-Host "✓ Repository initialized" -ForegroundColor Green
Write-Host ""

Write-Host "[3/5] Adding all files to git..." -ForegroundColor Yellow
git add .
Write-Host "✓ Files staged" -ForegroundColor Green
Write-Host ""

Write-Host "[4/5] Creating initial commit..." -ForegroundColor Yellow
git commit -m "feat: Initial Steal An Egg Hub with trust-aware anti-cheat evasion"
Write-Host "✓ Commit created" -ForegroundColor Green
Write-Host ""

Write-Host "[5/5] Setting up main branch..." -ForegroundColor Yellow
git branch -M main
Write-Host "✓ Main branch set" -ForegroundColor Green
Write-Host ""

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "REPOSITORY READY FOR PUSH!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Create new repo on GitHub: miracleverytime/MiracleHub-SteaLEgg" -ForegroundColor White
Write-Host "2. Copy your remote URL (e.g., https://github.com/miracleverytime/MiracleHub-SteaLEgg.git)" -ForegroundColor White
Write-Host "3. Run command: git remote add origin YOUR_REMOTE_URL" -ForegroundColor White
Write-Host "4. Run command: git push -u origin main" -ForegroundColor White
Write-Host ""
Write-Host "Press any key to exit when ready..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
