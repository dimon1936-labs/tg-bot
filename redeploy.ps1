$flowsPath = Join-Path $PSScriptRoot "flows.json"
$url = "http://localhost:1881/flows"

Write-Host "Validating flows.json..."
try {
    Get-Content $flowsPath -Raw | ConvertFrom-Json | Out-Null
    Write-Host "OK" -ForegroundColor Green
} catch {
    Write-Host "INVALID JSON" -ForegroundColor Red
    exit 1
}

Write-Host "Uploading to $url"
try {
    $response = Invoke-RestMethod -Uri $url -Method POST -ContentType "application/json" -Headers @{ "Node-RED-Deployment-Type" = "full" } -InFile $flowsPath
    Write-Host "Deployed" -ForegroundColor Green
} catch {
    Write-Host "API failed, fallback to docker cp" -ForegroundColor Yellow
    docker cp $flowsPath birthday-bot-nodered:/data/flows.json
    docker restart birthday-bot-nodered
    Write-Host "Container restarted" -ForegroundColor Green
}
