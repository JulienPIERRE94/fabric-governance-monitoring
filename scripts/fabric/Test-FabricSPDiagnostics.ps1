param([string]$CredsPath = "secrets\fabric-monitoring-sp.credentials.json")

$creds = Get-Content $CredsPath -Raw | ConvertFrom-Json
Write-Host "Tenant : $($creds.TenantId)"
Write-Host "AppId  : $($creds.ClientId)"
Write-Host ""

# === Test 1 : Token PBI ===
$body = @{
    grant_type    = "client_credentials"
    client_id     = $creds.ClientId
    client_secret = $creds.ClientSecret
    scope         = "https://analysis.windows.net/powerbi/api/.default"
}
$pbiTok = (Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$($creds.TenantId)/oauth2/v2.0/token" -Body $body).access_token

# Decode JWT
$parts = $pbiTok.Split('.')
$payload = $parts[1]
$pad = 4 - ($payload.Length % 4); if ($pad -lt 4) { $payload += "=" * $pad }
$claims = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload.Replace('-','+').Replace('_','/'))) | ConvertFrom-Json

Write-Host "=== JWT Power BI ==="
Write-Host "aud   : $($claims.aud)"
Write-Host "appid : $($claims.appid)"
Write-Host "tid   : $($claims.tid)"
Write-Host "oid   : $($claims.oid)"
Write-Host "roles : $($claims.roles -join ', ')"
if ($claims.wids) { Write-Host "wids  : $($claims.wids -join ', ')" }
Write-Host ""

# === Test 2 : /admin/capacities ===
Write-Host "=== Test /admin/capacities ==="
try {
    $r = Invoke-RestMethod -Method GET -Uri "https://api.powerbi.com/v1.0/myorg/admin/capacities" -Headers @{Authorization = "Bearer $pbiTok"}
    Write-Host "OK - $($r.value.Count) capacites" -ForegroundColor Green
    $r.value | Select-Object id, displayName, sku, state | Format-Table | Out-String | Write-Host
} catch {
    $resp = $_.Exception.Response
    Write-Host "Status : $($resp.StatusCode) ($([int]$resp.StatusCode))" -ForegroundColor Red
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
        Write-Host "Body   : $($_.ErrorDetails.Message)"
    }
    if ($resp.Headers) {
        $reqId = $resp.Headers | Where-Object { $_.Key -eq "RequestId" } | Select-Object -First 1
        if ($reqId) { Write-Host "RequestId : $($reqId.Value -join ',')" }
    }
}

Write-Host ""
Write-Host "=== Test /admin/workspaces?`$top=1 (PBI legacy) ==="
try {
    $r = Invoke-RestMethod -Method GET -Uri 'https://api.powerbi.com/v1.0/myorg/admin/groups?$top=1' -Headers @{Authorization = "Bearer $pbiTok"}
    Write-Host "OK - $($r.'@odata.count') workspaces total (page 1)" -ForegroundColor Green
} catch {
    Write-Host "Status : $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    if ($_.ErrorDetails.Message) { Write-Host "Body   : $($_.ErrorDetails.Message)" }
}

Write-Host ""
# === Test 3 : Token Fabric + endpoint Fabric ===
$bodyF = @{
    grant_type    = "client_credentials"
    client_id     = $creds.ClientId
    client_secret = $creds.ClientSecret
    scope         = "https://api.fabric.microsoft.com/.default"
}
$fabTok = (Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$($creds.TenantId)/oauth2/v2.0/token" -Body $bodyF).access_token

$parts = $fabTok.Split('.')
$payload = $parts[1]
$pad = 4 - ($payload.Length % 4); if ($pad -lt 4) { $payload += "=" * $pad }
$fabClaims = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload.Replace('-','+').Replace('_','/'))) | ConvertFrom-Json

Write-Host "=== JWT Fabric ==="
Write-Host "aud   : $($fabClaims.aud)"
Write-Host "roles : $($fabClaims.roles -join ', ')"
Write-Host ""

Write-Host "=== Test /v1/admin/workspaces ==="
try {
    $r = Invoke-RestMethod -Method GET -Uri "https://api.fabric.microsoft.com/v1/admin/workspaces?type=Workspace" -Headers @{Authorization = "Bearer $fabTok"}
    Write-Host "OK - $($r.workspaces.Count) workspaces" -ForegroundColor Green
} catch {
    Write-Host "Status : $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    if ($_.ErrorDetails.Message) { Write-Host "Body   : $($_.ErrorDetails.Message)" }
}
