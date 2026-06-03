# Crée SM_BankingInsurance et poll le status de l'opération async

$fabToken = (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
$h = @{ Authorization = "Bearer $fabToken"; "Content-Type" = "application/json" }

$wsI = "cbc321b0-5e65-41c1-a98c-eea5781305b7"
$lhI = "317f23e4-0dd7-4ace-9780-2c81c342bd5a"

# ── BIM Direct Lake avec 6 tables, 5 relations, 2 rôles RLS + OLS ────────────
$bimLines = @(
'{'
'  "name": "SM_BankingInsurance",'
'  "compatibilityLevel": 1604,'
'  "model": {'
'    "culture": "fr-FR",'
'    "defaultPowerBIDataSourceVersion": "powerBI_V3",'
'    "tables": ['
# ── sc_dim_customers ─────────────────────────────────────────────────────────
'      {'
'        "name": "sc_dim_customers",'
'        "columns": ['
'          {"name":"customer_id","dataType":"string","sourceColumn":"customer_id"},'
'          {"name":"name","dataType":"string","sourceColumn":"name"},'
'          {"name":"region","dataType":"string","sourceColumn":"region"},'
'          {"name":"segment","dataType":"string","sourceColumn":"segment"},'
'          {"name":"advisor_email","dataType":"string","sourceColumn":"advisor_email"}'
'        ],'
'        "partitions": [{"name":"p","mode":"directLake","source":{"type":"entity","schemaName":"dbo","entityName":"sc_dim_customers"}}]'
'      },'
# ── sc_fact_bank_accounts ────────────────────────────────────────────────────
'      {'
'        "name": "sc_fact_bank_accounts",'
'        "columns": ['
'          {"name":"account_id","dataType":"string","sourceColumn":"account_id"},'
'          {"name":"customer_id","dataType":"string","sourceColumn":"customer_id"},'
'          {"name":"product_type","dataType":"string","sourceColumn":"product_type"},'
'          {"name":"balance","dataType":"double","sourceColumn":"balance"}'
'        ],'
'        "partitions": [{"name":"p","mode":"directLake","source":{"type":"entity","schemaName":"dbo","entityName":"sc_fact_bank_accounts"}}]'
'      },'
# ── sc_bridge_ins_customers ──────────────────────────────────────────────────
'      {'
'        "name": "sc_bridge_ins_customers",'
'        "columns": ['
'          {"name":"bridge_id","dataType":"string","sourceColumn":"bridge_id"},'
'          {"name":"customer_id","dataType":"string","sourceColumn":"customer_id"},'
'          {"name":"insurance_consent","dataType":"string","sourceColumn":"insurance_consent"},'
'          {"name":"sharing_scope","dataType":"string","sourceColumn":"sharing_scope"}'
'        ],'
'        "partitions": [{"name":"p","mode":"directLake","source":{"type":"entity","schemaName":"dbo","entityName":"sc_bridge_ins_customers"}}]'
'      },'
# ── insurance_contracts ──────────────────────────────────────────────────────
'      {'
'        "name": "insurance_contracts",'
'        "columns": ['
'          {"name":"contract_id","dataType":"string","sourceColumn":"contract_id"},'
'          {"name":"customer_id","dataType":"string","sourceColumn":"customer_id"},'
'          {"name":"contract_type","dataType":"string","sourceColumn":"contract_type"},'
'          {"name":"product_label","dataType":"string","sourceColumn":"product_label"},'
'          {"name":"premium","dataType":"double","sourceColumn":"premium"},'
'          {"name":"status","dataType":"string","sourceColumn":"status"}'
'        ],'
'        "partitions": [{"name":"p","mode":"directLake","source":{"type":"entity","schemaName":"dbo","entityName":"insurance_contracts"}}]'
'      },'
# ── insurance_claims ─────────────────────────────────────────────────────────
'      {'
'        "name": "insurance_claims",'
'        "columns": ['
'          {"name":"claim_id","dataType":"string","sourceColumn":"claim_id"},'
'          {"name":"contract_id","dataType":"string","sourceColumn":"contract_id"},'
'          {"name":"claim_date","dataType":"string","sourceColumn":"claim_date"},'
'          {"name":"claim_type","dataType":"string","sourceColumn":"claim_type"},'
'          {"name":"amount","dataType":"double","sourceColumn":"amount"},'
'          {"name":"status","dataType":"string","sourceColumn":"status"}'
'        ],'
'        "partitions": [{"name":"p","mode":"directLake","source":{"type":"entity","schemaName":"dbo","entityName":"insurance_claims"}}]'
'      },'
# ── security_table ───────────────────────────────────────────────────────────
'      {'
'        "name": "security_table",'
'        "columns": ['
'          {"name":"user_email","dataType":"string","sourceColumn":"user_email"},'
'          {"name":"customer_id","dataType":"string","sourceColumn":"customer_id"}'
'        ],'
'        "partitions": [{"name":"p","mode":"directLake","source":{"type":"entity","schemaName":"dbo","entityName":"security_table"}}]'
'      }'
'    ],'
# ── Relationships ─────────────────────────────────────────────────────────────
'    "relationships": ['
'      {"name":"r1","fromTable":"sc_fact_bank_accounts","fromColumn":"customer_id","toTable":"sc_dim_customers","toColumn":"customer_id","crossFilteringBehavior":"bothDirections"},'
'      {"name":"r2","fromTable":"sc_bridge_ins_customers","fromColumn":"customer_id","toTable":"sc_dim_customers","toColumn":"customer_id","crossFilteringBehavior":"bothDirections"},'
'      {"name":"r3","fromTable":"insurance_contracts","fromColumn":"customer_id","toTable":"sc_dim_customers","toColumn":"customer_id","crossFilteringBehavior":"bothDirections"},'
'      {"name":"r4","fromTable":"insurance_claims","fromColumn":"contract_id","toTable":"insurance_contracts","toColumn":"contract_id"},'
'      {"name":"r5","fromTable":"security_table","fromColumn":"customer_id","toTable":"sc_dim_customers","toColumn":"customer_id","crossFilteringBehavior":"bothDirections"}'
'    ],'
# ── RLS Roles ─────────────────────────────────────────────────────────────────
'    "roles": ['
'      {'
'        "name": "BankingAdvisor",'
'        "modelPermission": "read",'
'        "tablePermissions": ['
'          {"name":"sc_dim_customers","filterExpression":"[advisor_email] = USERPRINCIPALNAME()"},'
'          {"name":"security_table","filterExpression":"[user_email] = USERPRINCIPALNAME()"}'
'        ]'
'      },'
'      {'
'        "name": "InsuranceUser",'
'        "modelPermission": "read",'
'        "tablePermissions": ['
'          {"name":"sc_dim_customers","filterExpression":"[customer_id] IN VALUES(sc_bridge_ins_customers[customer_id])"},'
'          {"name":"security_table","filterExpression":"[user_email] = USERPRINCIPALNAME()"},'
'          {"name":"sc_fact_bank_accounts","filterExpression":"FALSE()"}'
'        ]'
'      }'
'    ]'
'  }'
'}'
)

$bim = $bimLines -join "`n"

# Encode en base64
$b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($bim))

$pbism = '{"$schema":"https://developer.microsoft.com/json-schemas/fabric/item/semanticModel/definitionProperties/1.0.0/schema.json","version":"4.2","settings":{},"defaultLakehouseBindingInfo":{"workspaceId":"' + $wsI + '","lakehouseId":"' + $lhI + '"}}'
$pbismB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pbism))

$bodyObj = [ordered]@{
    displayName = "SM_BankingInsurance"
    definition  = @{
        parts = @(
            @{ path = "definition.pbism"; payload = $pbismB64; payloadType = "InlineBase64" }
            @{ path = "model.bim";        payload = $b64;      payloadType = "InlineBase64" }
        )
    }
}
$bodyJson = $bodyObj | ConvertTo-Json -Depth 10

Write-Host "Creating SM_BankingInsurance..."

# Invoke-WebRequest pour capturer les headers de réponse
try {
    $resp = Invoke-WebRequest -Method POST `
        -Uri ("https://api.fabric.microsoft.com/v1/workspaces/" + $wsI + "/semanticModels") `
        -Headers $h -Body $bodyJson -UseBasicParsing

    Write-Host ("HTTP " + $resp.StatusCode)
    $loc = $resp.Headers["Location"]
    Write-Host ("Location: " + $loc)

    if ($resp.StatusCode -eq 201) {
        $r = $resp.Content | ConvertFrom-Json
        Write-Host ("Created immediately - id: " + $r.id)
    } elseif ($loc) {
        # Poll operation
        Write-Host "Polling operation..."
        $elapsed = 0
        do {
            Start-Sleep 10; $elapsed += 10
            $fabToken2 = if ($elapsed % 300 -eq 0) { (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv) } else { $fabToken }
            $hPoll = @{ Authorization = "Bearer $fabToken2" }
            $op = Invoke-RestMethod -Uri $loc -Headers $hPoll
            Write-Host ("[" + $elapsed + "s] status=" + $op.status)
            if ($op.status -eq "Succeeded") {
                Write-Host ("SM id: " + $op.createdItemId)
                break
            }
            if ($op.status -eq "Failed") {
                Write-Host ("FAILED: " + ($op | ConvertTo-Json -Depth 5))
                break
            }
        } while ($elapsed -lt 120)
    }
} catch {
    $r2 = $_.Exception.Response
    if ($r2) {
        $rd = New-Object System.IO.StreamReader($r2.GetResponseStream())
        Write-Host ("Error " + [int]$r2.StatusCode + ": " + $rd.ReadToEnd())
    } else {
        Write-Host ("Error: " + $_.Exception.Message)
    }
}

# Lister pour confirmer
Write-Host ""
Write-Host "All semantic models in WS-Insurance:"
$fabToken3 = (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
$h3 = @{ Authorization = "Bearer $fabToken3" }
$sms = Invoke-RestMethod -Uri ("https://api.fabric.microsoft.com/v1/workspaces/" + $wsI + "/semanticModels") -Headers $h3
$sms.value | ForEach-Object { Write-Host ("  " + $_.displayName + " -> " + $_.id) }
