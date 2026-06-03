$fabToken = (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
$h = @{ Authorization = "Bearer $fabToken"; "Content-Type" = "application/json" }

$wsB = "5015e396-cb2d-4fbe-8ebf-c87544cf6bfd"
$wsI = "cbc321b0-5e65-41c1-a98c-eea5781305b7"
$lhB = "8093805b-3709-454e-9998-015b9faaf3c0"
$lhI = "317f23e4-0dd7-4ace-9780-2c81c342bd5a"

$needed = @("dim_customers","fact_bank_accounts","bridge_ins_customers")

Write-Host "Waiting for Banking Delta tables..."
$maxWait = 600; $elapsed = 0
$ready = $false

while (-not $ready -and $elapsed -lt $maxWait) {
    Start-Sleep 20; $elapsed += 20
    # Refresh token every 4 minutes
    if ($elapsed % 240 -eq 0) {
        $fabToken = (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
        $h = @{ Authorization = "Bearer $fabToken"; "Content-Type" = "application/json" }
    }
    try {
        $r    = Invoke-RestMethod -Uri ("https://api.fabric.microsoft.com/v1/workspaces/" + $wsB + "/lakehouses/" + $lhB + "/tables") -Headers $h
        $have = $r.data | ForEach-Object { $_.name }
        $missing = $needed | Where-Object { $_ -notin $have }
        Write-Host ("[" + $elapsed + "s] Tables: " + ($have -join ", ") + "  Missing: " + ($missing -join ", "))
        if ($missing.Count -eq 0) { $ready = $true }
    } catch {
        Write-Host ("[" + $elapsed + "s] poll error: " + $_.Exception.Message)
    }
}

if (-not $ready) {
    Write-Host "TIMEOUT waiting for Banking tables. Re-run this script later."
    exit 1
}

Write-Host "Banking tables ready! Creating shortcuts..."

$shortcuts = @(
    @{ name = "sc_dim_customers";        src = "Tables/dim_customers" }
    @{ name = "sc_fact_bank_accounts";   src = "Tables/fact_bank_accounts" }
    @{ name = "sc_bridge_ins_customers"; src = "Tables/bridge_ins_customers" }
)

foreach ($sc in $shortcuts) {
    $body = @{
        path = "Tables"
        name = $sc.name
        target = @{
            type    = "OneLake"
            oneLake = @{
                workspaceId = $wsB
                itemId      = $lhB
                path        = $sc.src
            }
        }
    } | ConvertTo-Json -Depth 10

    $url = "https://api.fabric.microsoft.com/v1/workspaces/" + $wsI + "/items/" + $lhI + "/shortcuts"
    try {
        Invoke-RestMethod -Method POST -Uri $url -Headers $h -Body $body | Out-Null
        Write-Host ("  OK " + $sc.name)
    } catch {
        $resp = $_.Exception.Response
        if ($resp) {
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
            Write-Host ("  WARN " + $sc.name + ": " + $reader.ReadToEnd())
        } else {
            Write-Host ("  WARN " + $sc.name + ": " + $_.Exception.Message)
        }
    }
}

Write-Host ""
Write-Host "=== SHORTCUTS DONE ==="
Write-Host "Verify in Fabric portal:"
Write-Host "  WS-Insurance -> Lakehouse_Insurance -> Tables/ -> sc_dim_customers, sc_fact_bank_accounts, sc_bridge_ins_customers"
Write-Host ""
Write-Host "=== ALL REMAINING STEPS ==="
Write-Host "1. Create Direct Lake Semantic Model in WS-Insurance:"
Write-Host "   New Semantic Model -> Select Lakehouse_Insurance tables"
Write-Host "   Include: sc_dim_customers, sc_fact_bank_accounts, sc_bridge_ins_customers"
Write-Host "            insurance_contracts, insurance_claims, security_table"
Write-Host "2. Define relationships between tables"
Write-Host "3. Add RLS role 'BankingAdvisor':"
Write-Host "   DAX: [customer_id] = LOOKUPVALUE(security_table[customer_id], security_table[user_email], USERPRINCIPALNAME())"
Write-Host "4. Add RLS role 'InsuranceUser' on insurance_contracts + insurance_claims only"
Write-Host "5. OLS: hide sc_fact_bank_accounts[balance] from InsuranceUser role"
Write-Host "6. Build report in WS-Insurance with cross-domain visuals"
