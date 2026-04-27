$flowsPath = Join-Path $PSScriptRoot "flows.json"
$envPath   = Join-Path $PSScriptRoot ".env"
if (Test-Path $envPath) {
    Get-Content $envPath | ForEach-Object {
        if ($_ -match '^\s*([^#=\s]+)\s*=\s*(.*)\s*$') {
            $k = $matches[1]; $v = $matches[2] -replace '^["'']|["'']$',''
            if (-not [Environment]::GetEnvironmentVariable($k)) {
                Set-Item -Path "env:$k" -Value $v
            }
        }
    }
}
$host_   = if ($env:NODE_RED_HOST) { $env:NODE_RED_HOST } else { "http://localhost:1881" }
$user    = if ($env:NODE_RED_USER) { $env:NODE_RED_USER } else { "admin" }
if (-not $env:NODE_RED_PASS) { Write-Host "Set NODE_RED_PASS env var" -ForegroundColor Red; exit 1 }
$pass    = $env:NODE_RED_PASS

Write-Host "Validating flows.json..."
try {
    Get-Content $flowsPath -Raw | ConvertFrom-Json | Out-Null
    Write-Host "OK" -ForegroundColor Green
} catch {
    Write-Host "INVALID JSON" -ForegroundColor Red
    exit 1
}

Write-Host "Authenticating to Node-RED..."
$token = $null
try {
    $authBody = @{
        client_id  = "node-red-admin"
        grant_type = "password"
        scope      = "*"
        username   = $user
        password   = $pass
    } | ConvertTo-Json
    $auth = Invoke-RestMethod -Uri "$host_/auth/token" -Method POST -ContentType "application/json" -Body $authBody
    $token = $auth.access_token
} catch {
    Write-Host "Auth failed, fallback to docker cp" -ForegroundColor Yellow
    docker cp $flowsPath birthday-bot-nodered:/data/flows.json
    docker restart birthday-bot-nodered
    Write-Host "Container restarted" -ForegroundColor Green
    exit 0
}

Write-Host "Uploading to $host_/flows"
try {
    Invoke-RestMethod -Uri "$host_/flows" -Method POST `
        -ContentType "application/json" `
        -Headers @{ "Authorization" = "Bearer $token"; "Node-RED-Deployment-Type" = "full" } `
        -InFile $flowsPath | Out-Null
    Write-Host "Deployed" -ForegroundColor Green
} catch {
    Write-Host "API failed, fallback to docker cp" -ForegroundColor Yellow
    docker cp $flowsPath birthday-bot-nodered:/data/flows.json
    docker restart birthday-bot-nodered
    Write-Host "Container restarted" -ForegroundColor Green
}
