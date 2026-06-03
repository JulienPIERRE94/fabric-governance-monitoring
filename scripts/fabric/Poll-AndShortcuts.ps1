$fabToken = (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
$h = @{ Authorization = "Bearer $fabToken" }

$wsB = "5015e396-cb2d-4fbe-8ebf-c87544cf6bfd"
$lhB = "8093805b-3709-454e-9998-015b9faaf3c0"
$wsI = "cbc321b0-5e65-41c1-a98c-eea5781305b7"
$lhI = "317f23e4-0dd7-4ace-9780-2c81c342bd5a"

$needed = @("dim_customers","fact_bank_accounts","bridge_ins_customers")

Write-Host "Polling Banking tables (up to 10 min)..."
$elapsed = 0
$ready = $false
while (-not $ready -and $elapsed -lt 600) {
    Start-Sleep 30; $elapsed += 30
    if ($elapsed % 300 -eq 0) {
        $fabToken = (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
        $h = @{ Authorization = "Bearer $fabToken" }
    }
    try {
        $r    = Invoke-RestMethod -Uri ("https://api.fabric.microsoft.com/v1/workspaces/" + $wsB + "/lakehouses/" + $lhB + "/tables") -Headers $h
        $have = @($r.data | ForEach-Object { $_.name })
        $miss = @($needed | Where-Object { $_ -notin $have })
        Write-Host ("[" + $elapsed + "s] have=" + ($have -join ",") + "  missing=" + ($miss -join ","))
        if ($miss.Count -eq 0) { $ready = $true }
    } catch {
        Write-Host ("[" + $elapsed + "s] " + $_.Exception.Message)
    }
}

if (-not $ready) {
    Write-Host "TIMEOUT - tables still not ready."
    Write-Host "ACTION REQUIRED: Go to Fabric portal, open Lakehouse_Banking, click 'Load to Tables' on each CSV under Files/data/"
    exit 1
}

Write-Host "All Banking tables ready!"

# Now create shortcuts
Write-Host "Creating shortcuts in Lakehouse_Insurance..."
$hPost = @{ Authorization = "Bearer $fabToken"; "Content-Type" = "application/json" }

$sc_list = @(
    @{ name = "sc_dim_customers";        src = "Tables/dim_customers" }
    @{ name = "sc_fact_bank_accounts";   src = "Tables/fact_bank_accounts" }
    @{ name = "sc_bridge_ins_customers"; src = "Tables/bridge_ins_customers" }
)

foreach ($sc in $sc_list) {
    $body = @{
        path   = "Tables"
        name   = $sc.name
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
        Invoke-RestMethod -Method POST -Uri $url -Headers $hPost -Body $body | Out-Null
        Write-Host ("  OK " + $sc.name)
    } catch {
        $resp = $_.Exception.Response
        if ($resp) {
            $rd = New-Object System.IO.StreamReader($resp.GetResponseStream())
            $detail = $rd.ReadToEnd()
            if ($detail -like "*AlreadyExists*" -or $detail -like "*409*") {
                Write-Host ("  SKIP " + $sc.name + " (already exists)")
            } else {
                Write-Host ("  WARN " + $sc.name + ": " + $detail)
            }
        } else {
            Write-Host ("  WARN " + $sc.name + ": " + $_.Exception.Message)
        }
    }
}

Write-Host ""
Write-Host "=== DEPLOYMENT COMPLETE ==="
Write-Host "WS-Banking   : 5015e396-cb2d-4fbe-8ebf-c87544cf6bfd"
Write-Host "WS-Insurance : cbc321b0-5e65-41c1-a98c-eea5781305b7"
Write-Host ""
Write-Host "Lakehouse_Banking tables  : dim_customers, fact_bank_accounts, bridge_ins_customers"
Write-Host "Lakehouse_Insurance tables: insurance_contracts, insurance_claims, security_table"
Write-Host "                shortcuts : sc_dim_customers, sc_fact_bank_accounts, sc_bridge_ins_customers"
Write-Host ""
Write-Host "=== REMAINING MANUAL STEPS ==="
Write-Host "1. https://app.fabric.microsoft.com -> WS-Insurance -> New Semantic Model"
Write-Host "   Add all 6 tables (3 owned + 3 shortcuts)"
Write-Host "2. In Semantic Model -> Security -> New role 'BankingAdvisor'"
Write-Host "   Filter on sc_dim_customers: [advisor_email] = USERPRINCIPALNAME()"
Write-Host "3. New role 'InsuranceUser'"
Write-Host "   Filter on sc_dim_customers via bridge: bridge_ins_customers[customer_id]"
Write-Host "4. OLS: on role InsuranceUser -> sc_fact_bank_accounts -> [balance] = None"
Write-Host "5. Build a report with cross-domain visuals"
