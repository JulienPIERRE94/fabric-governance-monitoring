$fabToken = (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
$h = @{ Authorization = "Bearer $fabToken"; "Content-Type" = "application/json" }

$wsB = "5015e396-cb2d-4fbe-8ebf-c87544cf6bfd"
$lhB = "8093805b-3709-454e-9998-015b9faaf3c0"
$nbBId = "b0a68afc-b58d-408a-b2a4-e57d36c631d5"

# Retrieve notebook definition to inspect source
Write-Host "=== Retrieving Banking notebook definition ==="
try {
    $r = Invoke-RestMethod -Method POST `
        -Uri ("https://api.fabric.microsoft.com/v1/workspaces/" + $wsB + "/notebooks/" + $nbBId + "/getDefinition") `
        -Headers $h -Body "{}"
    $part = $r.definition.parts | Where-Object { $_.path -like "*.ipynb" }
    if ($part) {
        $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part.payload))
        Write-Host "Notebook source (first 500 chars):"
        Write-Host ($decoded.Substring(0, [Math]::Min(500, $decoded.Length)))
    } else {
        Write-Host "No ipynb part found"
        $r | ConvertTo-Json -Depth 5
    }
} catch {
    Write-Host ("Error: " + $_.Exception.Message)
}

# Try Lakehouse Load Table API (direct CSV -> Delta, no Spark needed)
Write-Host ""
Write-Host "=== Trying Lakehouse Load Table API (CSV -> Delta) ==="
$tables = @(
    @{ table = "dim_customers";        file = "dim_customers.csv" }
    @{ table = "fact_bank_accounts";   file = "fact_bank_accounts.csv" }
    @{ table = "bridge_ins_customers"; file = "bridge_ins_customers.csv" }
)

foreach ($t in $tables) {
    $body = @{
        relativePath   = "Files/data/" + $t.file
        pathType       = "File"
        mode           = "Overwrite"
        recursive      = $false
        formatOptions  = @{ format = "Csv"; header = $true; delimiter = "," }
    } | ConvertTo-Json -Depth 5

    $url = "https://api.fabric.microsoft.com/v1/workspaces/" + $wsB + "/lakehouses/" + $lhB + "/tables/" + $t.table + "/load"
    try {
        $r = Invoke-RestMethod -Method POST -Uri $url -Headers $h -Body $body
        Write-Host ("  Submitted load for " + $t.table)
    } catch {
        $resp = $_.Exception.Response
        if ($resp) {
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
            Write-Host ("  WARN " + $t.table + ": " + $reader.ReadToEnd())
        } else {
            Write-Host ("  WARN " + $t.table + ": " + $_.Exception.Message)
        }
    }
    Start-Sleep 2
}

Write-Host ""
Write-Host "Waiting 60s for table loads to complete..."
Start-Sleep 60

$r2 = Invoke-RestMethod -Uri ("https://api.fabric.microsoft.com/v1/workspaces/" + $wsB + "/lakehouses/" + $lhB + "/tables") -Headers $h
Write-Host "Tables in Banking Lakehouse now:"
$r2.data | ForEach-Object { Write-Host ("  " + $_.name) }
