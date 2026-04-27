$dbDir = Join-Path $PSScriptRoot "db"
$migrations = Get-ChildItem $dbDir -Filter "migration_*.sql" | Sort-Object Name

Write-Host "Found $($migrations.Count) migrations:"
$migrations | ForEach-Object { Write-Host "  - $($_.Name)" }
Write-Host ""

foreach ($m in $migrations) {
    Write-Host "Applying $($m.Name)..." -ForegroundColor Cyan
    Get-Content $m.FullName | docker exec -i birthday-bot-db psql -U postgres -d birthday_bot
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAILED" -ForegroundColor Red
        exit 1
    }
    Write-Host "  OK" -ForegroundColor Green
}

Write-Host ""
Write-Host "All migrations applied successfully" -ForegroundColor Green
