$fabToken = (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
$h = @{ Authorization = "Bearer $fabToken"; "Content-Type" = "application/json" }

$wsB = "5015e396-cb2d-4fbe-8ebf-c87544cf6bfd"
$wsI = "cbc321b0-5e65-41c1-a98c-eea5781305b7"
$lhB = "8093805b-3709-454e-9998-015b9faaf3c0"
$lhI = "317f23e4-0dd7-4ace-9780-2c81c342bd5a"

# Check tables in Banking Lakehouse
Write-Host "=== Tables in Lakehouse_Banking ==="
try {
    $r = Invoke-RestMethod -Uri ("https://api.fabric.microsoft.com/v1/workspaces/" + $wsB + "/lakehouses/" + $lhB + "/tables") -Headers $h
    $r.data | ForEach-Object { Write-Host ("  " + $_.name + " (" + $_.type + ")") }
    if (-not $r.data) { Write-Host "  (no tables yet - notebooks still running)" }
} catch {
    Write-Host ("  ERROR: " + $_.Exception.Message)
}

# Check tables in Insurance Lakehouse
Write-Host "=== Tables in Lakehouse_Insurance ==="
try {
    $r = Invoke-RestMethod -Uri ("https://api.fabric.microsoft.com/v1/workspaces/" + $wsI + "/lakehouses/" + $lhI + "/tables") -Headers $h
    $r.data | ForEach-Object { Write-Host ("  " + $_.name + " (" + $_.type + ")") }
    if (-not $r.data) { Write-Host "  (no tables yet)" }
} catch {
    Write-Host ("  ERROR: " + $_.Exception.Message)
}

# Try shortcut with verbose error
Write-Host ""
Write-Host "=== Test shortcut creation (verbose) ==="
$body = @{
    path = "Tables"
    name = "sc_dim_customers"
    target = @{
        type    = "OneLake"
        oneLake = @{
            workspaceId = $wsB
            itemId      = $lhB
            path        = "Tables/dim_customers"
        }
    }
} | ConvertTo-Json -Depth 10

$url = "https://api.fabric.microsoft.com/v1/workspaces/" + $wsI + "/items/" + $lhI + "/shortcuts"
try {
    $r = Invoke-RestMethod -Method POST -Uri $url -Headers $h -Body $body
    Write-Host "  OK: shortcut created"
    $r | ConvertTo-Json
} catch {
    $resp = $_.Exception.Response
    if ($resp) {
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $body2  = $reader.ReadToEnd()
        Write-Host ("  HTTP " + [int]$resp.StatusCode + ": " + $body2)
    } else {
        Write-Host ("  " + $_.Exception.Message)
    }
}
