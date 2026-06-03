# ═══════════════════════════════════════════════════════════════════════════
#  Create-SemanticModel.ps1
#  Crée le Semantic Model Direct Lake dans WS-Insurance
#  Tables, Relations, RLS (BankingAdvisor + InsuranceUser), OLS (balance)
# ═══════════════════════════════════════════════════════════════════════════

$fabToken = (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
$h = @{ Authorization = "Bearer $fabToken"; "Content-Type" = "application/json" }

$wsI  = "cbc321b0-5e65-41c1-a98c-eea5781305b7"
$lhI  = "317f23e4-0dd7-4ace-9780-2c81c342bd5a"
$sqlServer = "w6qoaejc6fyerpfiqexi6onlee-waq4hs3fl3audkmm52sxqeyfw4.datawarehouse.fabric.microsoft.com"
$sqlDb     = "a0d40f2e-6359-4d38-8edf-f0d358ad38eb"

# ── BIM (TMSL JSON) ──────────────────────────────────────────────────────────
# Direct Lake: chaque table a une partition de type "entity" pointant vers
# le nom de la table Delta dans le lakehouse (via SQL Endpoint)

$bim = @'
{
  "name": "SM_BankingInsurance",
  "compatibilityLevel": 1604,
  "model": {
    "culture": "fr-FR",
    "defaultPowerBIDataSourceVersion": "powerBI_V3",
    "sourceQueryCulture": "fr-FR",
    "dataSources": [
      {
        "type": "structured",
        "name": "EntityDataSource",
        "connectionDetails": {
          "protocol": "entity",
          "address": {
            "lakehouse": "LAKEHOUSE_ID"
          }
        },
        "credential": {
          "AuthenticationKind": "OAuth2",
          "kind": "Lakehouse",
          "path": "LAKEHOUSE_ID",
          "WorkspaceId": "WORKSPACE_ID"
        }
      }
    ],
    "tables": [
      {
        "name": "sc_dim_customers",
        "columns": [
          { "name": "customer_id",    "dataType": "string",  "sourceColumn": "customer_id" },
          { "name": "name",           "dataType": "string",  "sourceColumn": "name" },
          { "name": "region",         "dataType": "string",  "sourceColumn": "region" },
          { "name": "segment",        "dataType": "string",  "sourceColumn": "segment" },
          { "name": "advisor_email",  "dataType": "string",  "sourceColumn": "advisor_email" }
        ],
        "partitions": [
          {
            "name": "EntityPartition",
            "mode": "directLake",
            "source": {
              "type": "entity",
              "schemaName": "dbo",
              "entityName": "sc_dim_customers"
            }
          }
        ]
      },
      {
        "name": "sc_fact_bank_accounts",
        "columns": [
          { "name": "account_id",   "dataType": "string",  "sourceColumn": "account_id" },
          { "name": "customer_id",  "dataType": "string",  "sourceColumn": "customer_id" },
          { "name": "product_type", "dataType": "string",  "sourceColumn": "product_type" },
          { "name": "balance",      "dataType": "double",  "sourceColumn": "balance" }
        ],
        "partitions": [
          {
            "name": "EntityPartition",
            "mode": "directLake",
            "source": {
              "type": "entity",
              "schemaName": "dbo",
              "entityName": "sc_fact_bank_accounts"
            }
          }
        ]
      },
      {
        "name": "sc_bridge_ins_customers",
        "columns": [
          { "name": "bridge_id",          "dataType": "string",  "sourceColumn": "bridge_id" },
          { "name": "customer_id",        "dataType": "string",  "sourceColumn": "customer_id" },
          { "name": "insurance_consent",  "dataType": "string",  "sourceColumn": "insurance_consent" },
          { "name": "sharing_scope",      "dataType": "string",  "sourceColumn": "sharing_scope" }
        ],
        "partitions": [
          {
            "name": "EntityPartition",
            "mode": "directLake",
            "source": {
              "type": "entity",
              "schemaName": "dbo",
              "entityName": "sc_bridge_ins_customers"
            }
          }
        ]
      },
      {
        "name": "insurance_contracts",
        "columns": [
          { "name": "contract_id",    "dataType": "string",  "sourceColumn": "contract_id" },
          { "name": "customer_id",    "dataType": "string",  "sourceColumn": "customer_id" },
          { "name": "contract_type",  "dataType": "string",  "sourceColumn": "contract_type" },
          { "name": "product_label",  "dataType": "string",  "sourceColumn": "product_label" },
          { "name": "premium",        "dataType": "double",  "sourceColumn": "premium" },
          { "name": "status",         "dataType": "string",  "sourceColumn": "status" }
        ],
        "partitions": [
          {
            "name": "EntityPartition",
            "mode": "directLake",
            "source": {
              "type": "entity",
              "schemaName": "dbo",
              "entityName": "insurance_contracts"
            }
          }
        ]
      },
      {
        "name": "insurance_claims",
        "columns": [
          { "name": "claim_id",      "dataType": "string",  "sourceColumn": "claim_id" },
          { "name": "contract_id",   "dataType": "string",  "sourceColumn": "contract_id" },
          { "name": "claim_date",    "dataType": "string",  "sourceColumn": "claim_date" },
          { "name": "claim_type",    "dataType": "string",  "sourceColumn": "claim_type" },
          { "name": "amount",        "dataType": "double",  "sourceColumn": "amount" },
          { "name": "status",        "dataType": "string",  "sourceColumn": "status" }
        ],
        "partitions": [
          {
            "name": "EntityPartition",
            "mode": "directLake",
            "source": {
              "type": "entity",
              "schemaName": "dbo",
              "entityName": "insurance_claims"
            }
          }
        ]
      },
      {
        "name": "security_table",
        "columns": [
          { "name": "user_email",   "dataType": "string",  "sourceColumn": "user_email" },
          { "name": "customer_id",  "dataType": "string",  "sourceColumn": "customer_id" }
        ],
        "partitions": [
          {
            "name": "EntityPartition",
            "mode": "directLake",
            "source": {
              "type": "entity",
              "schemaName": "dbo",
              "entityName": "security_table"
            }
          }
        ]
      }
    ],
    "relationships": [
      {
        "name": "fk_bank_accounts_customers",
        "fromTable": "sc_fact_bank_accounts",
        "fromColumn": "customer_id",
        "toTable": "sc_dim_customers",
        "toColumn": "customer_id",
        "crossFilteringBehavior": "bothDirections"
      },
      {
        "name": "fk_bridge_customers",
        "fromTable": "sc_bridge_ins_customers",
        "fromColumn": "customer_id",
        "toTable": "sc_dim_customers",
        "toColumn": "customer_id",
        "crossFilteringBehavior": "bothDirections"
      },
      {
        "name": "fk_contracts_customers",
        "fromTable": "insurance_contracts",
        "fromColumn": "customer_id",
        "toTable": "sc_dim_customers",
        "toColumn": "customer_id",
        "crossFilteringBehavior": "bothDirections"
      },
      {
        "name": "fk_claims_contracts",
        "fromTable": "insurance_claims",
        "fromColumn": "contract_id",
        "toTable": "insurance_contracts",
        "toColumn": "contract_id"
      },
      {
        "name": "fk_security_customers",
        "fromTable": "security_table",
        "fromColumn": "customer_id",
        "toTable": "sc_dim_customers",
        "toColumn": "customer_id",
        "crossFilteringBehavior": "bothDirections"
      }
    ],
    "roles": [
      {
        "name": "BankingAdvisor",
        "modelPermission": "read",
        "tablePermissions": [
          {
            "name": "sc_dim_customers",
            "filterExpression": "[advisor_email] = USERPRINCIPALNAME()"
          },
          {
            "name": "security_table",
            "filterExpression": "[user_email] = USERPRINCIPALNAME()"
          }
        ]
      },
      {
        "name": "InsuranceUser",
        "modelPermission": "read",
        "tablePermissions": [
          {
            "name": "sc_dim_customers",
            "filterExpression": "[customer_id] IN VALUES(sc_bridge_ins_customers[customer_id])"
          },
          {
            "name": "security_table",
            "filterExpression": "[user_email] = USERPRINCIPALNAME()"
          },
          {
            "name": "sc_fact_bank_accounts",
            "filterExpression": "FALSE()"
          }
        ],
        "columnPermissions": [
          {
            "table": "sc_fact_bank_accounts",
            "column": "balance",
            "permission": "none"
          }
        ]
      }
    ]
  }
}
'@

# Injecter les IDs réels
$bim = $bim.Replace("LAKEHOUSE_ID", $lhI).Replace("WORKSPACE_ID", $wsI)

# Encoder en base64
$b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($bim))

$bodyObj = [ordered]@{
    displayName = "SM_BankingInsurance"
    definition  = @{
        parts = @(@{
            path        = "model.bim"
            payload     = $b64
            payloadType = "InlineBase64"
        })
    }
}
$body = $bodyObj | ConvertTo-Json -Depth 10

Write-Host "Creating Semantic Model SM_BankingInsurance..."
try {
    $r = Invoke-RestMethod -Method POST `
        -Uri ("https://api.fabric.microsoft.com/v1/workspaces/" + $wsI + "/semanticModels") `
        -Headers $h -Body $body
    Write-Host ("OK - id: " + $r.id)
    Write-Host ("URL: https://app.fabric.microsoft.com/groups/" + $wsI + "/datasets/" + $r.id)
} catch {
    $resp = $_.Exception.Response
    if ($resp) {
        $rd = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $detail = $rd.ReadToEnd()
        Write-Host ("HTTP " + [int]$resp.StatusCode + ": " + $detail)
    } else {
        Write-Host ("ERROR: " + $_.Exception.Message)
    }
}
