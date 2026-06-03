$fabToken = (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
$h = @{ Authorization = "Bearer $fabToken"; "Content-Type" = "application/json" }

$wsB  = "5015e396-cb2d-4fbe-8ebf-c87544cf6bfd"
$wsI  = "cbc321b0-5e65-41c1-a98c-eea5781305b7"
$lhB  = "8093805b-3709-454e-9998-015b9faaf3c0"
$lhI  = "317f23e4-0dd7-4ace-9780-2c81c342bd5a"

$shortcuts = @(
    @{ name = "sc_dim_customers";        sourcePath = "Tables/dim_customers" }
    @{ name = "sc_fact_bank_accounts";   sourcePath = "Tables/fact_bank_accounts" }
    @{ name = "sc_bridge_ins_customers"; sourcePath = "Tables/bridge_ins_customers" }
)

foreach ($sc in $shortcuts) {
    $body = @{
        path = "Tables"
        name = $sc.name
        target = @{
            type      = "OneLake"
            oneLake   = @{
                workspaceId = $wsB
                itemId      = $lhB
                path        = $sc.sourcePath
            }
        }
    } | ConvertTo-Json -Depth 10

    $url = "https://api.fabric.microsoft.com/v1/workspaces/" + $wsI + "/items/" + $lhI + "/shortcuts"
    try {
        $r = Invoke-RestMethod -Method POST -Uri $url -Headers $h -Body $body
        Write-Host ("  OK shortcut " + $sc.name)
    } catch {
        $msg = $_.Exception.Message
        if ($msg -like "*409*" -or $msg -like "*Conflict*") {
            Write-Host ("  SKIP " + $sc.name + " (already exists)")
        } else {
            Write-Host ("  WARN " + $sc.name + ": " + $msg)
        }
    }
}

Write-Host "Shortcuts done."
Write-Host ""
Write-Host "=== NEXT STEPS ==="
Write-Host "1. Open Fabric portal: https://app.fabric.microsoft.com"
Write-Host "2. Navigate to WS-Insurance -> Lakehouse_Insurance"
Write-Host "3. Verify shortcuts sc_dim_customers, sc_fact_bank_accounts, sc_bridge_ins_customers visible in Tables/"
Write-Host "4. Create a new Semantic Model (Direct Lake) on top of Lakehouse_Insurance"
Write-Host "5. Add RLS role 'BankingAdvisor': USERPRINCIPALNAME() = security_table[user_email] -> customer_id"
Write-Host "6. Add OLS: hide sc_fact_bank_accounts[balance] from Insurance_User role"
