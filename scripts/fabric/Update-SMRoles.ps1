# Met à jour SEM_Insurance avec les bons rôles RLS (BankingAdvisor + InsuranceUser corrigé)
# Basé sur la structure TMDL exacte récupérée via getDefinition

$fabToken = (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
$h = @{ Authorization = "Bearer $fabToken"; "Content-Type" = "application/json" }
$wsI  = "cbc321b0-5e65-41c1-a98c-eea5781305b7"
$smId = "5809e89f-eb8c-4cc1-b7a9-bf95809f5b62"
$lhI  = "317f23e4-0dd7-4ace-9780-2c81c342bd5a"

# ── TMDL des rôles ────────────────────────────────────────────────────────────

# Rôle BankingAdvisor : voit uniquement ses propres clients (via advisor_email)
$tmdlBankingAdvisor = @"
role BankingAdvisor
	modelPermission: read

	tablePermission sc_dim_customers = [advisor_email] = USERPRINCIPALNAME()

	tablePermission security_table = [user_email] = USERPRINCIPALNAME()

	annotation PBI_Id = ba12345678901234567890123456789a
"@

# Rôle InsuranceUser : voit uniquement les clients avec consentement (bridge)
# + ne voit PAS les données de sc_fact_bank_accounts (FALSE())
$tmdlInsuranceUser = @"
role InsuranceUser
	modelPermission: read

	tablePermission sc_dim_customers = [customer_id] IN VALUES(sc_bridge_ins_customers[customer_id])

	tablePermission security_table = [user_email] = USERPRINCIPALNAME()

	tablePermission sc_fact_bank_accounts = FALSE()

	annotation PBI_Id = ef929e7a0ba54699adfaa053c6719e21
"@

# ── Fichiers TMDL existants (récupérés via getDefinition) ─────────────────────
$pbism = '{"$schema":"https://developer.microsoft.com/json-schemas/fabric/item/semanticModel/definitionProperties/1.0.0/schema.json","version":"4.2","settings":{}}'

$tmdlDatabase = "database" + [char]10 + [char]9 + "compatibilityLevel: 1604" + [char]10

$olBase = "https://onelake.dfs.fabric.microsoft.com/" + $wsI + "/" + $lhI

$tmdlExpressions = "expression 'DirectLake - Lakehouse_Insurance' =" + [char]10 +
[char]9 + [char]9 + "let" + [char]10 +
[char]9 + [char]9 + "    Source = AzureStorage.DataLake(" + [char]34 + $olBase + [char]34 + ", [HierarchicalNavigation=true])" + [char]10 +
[char]9 + [char]9 + "in" + [char]10 +
[char]9 + [char]9 + "    Source" + [char]10 +
[char]9 + "lineageTag: 5baf1293-e9db-491e-a378-dcba41d5a55b" + [char]10 + [char]10 +
[char]9 + "annotation PBI_IncludeFutureArtifacts = False" + [char]10

$tmdlModel = @"
model Model
	culture: en-US
	defaultPowerBIDataSourceVersion: powerBI_V3
	sourceQueryCulture: en-US
	dataAccessOptions
		legacyRedirects
		returnErrorValuesAsNull

annotation PBI_QueryOrder = ["DirectLake - Lakehouse_Insurance"]

annotation __PBI_TimeIntelligenceEnabled = 1

annotation PBI_ProTooling = ["DirectLakeOnOneLakeInWeb","WebModelingEdit"]

ref table sc_dim_customers
ref table sc_fact_bank_accounts
ref table sc_bridge_ins_customers
ref table insurance_claims
ref table insurance_contracts
ref table security_table

ref role BankingAdvisor
ref role InsuranceUser
"@

$tmdlRelationships = @"
relationship r1
	fromColumn: sc_fact_bank_accounts.customer_id
	toColumn: sc_dim_customers.customer_id

relationship r2
	fromColumn: sc_bridge_ins_customers.customer_id
	toColumn: sc_dim_customers.customer_id

relationship r3
	fromColumn: insurance_contracts.customer_id
	toColumn: sc_dim_customers.customer_id

relationship r4
	fromColumn: insurance_claims.contract_id
	toColumn: insurance_contracts.contract_id

relationship r5
	fromColumn: security_table.customer_id
	toColumn: sc_dim_customers.customer_id
"@

# Tables TMDL (telles que récupérées, sans modification)
$tmdlTables = @{
    "sc_dim_customers" = @"
table sc_dim_customers
	lineageTag: aecef264-aba2-497c-811e-69c60fd6170a
	sourceLineageTag: [dbo].[sc_dim_customers]

	column customer_id
		dataType: string
		lineageTag: efcd16c4-6474-4660-9a05-35127a9a8a59
		sourceLineageTag: customer_id
		summarizeBy: none
		sourceColumn: customer_id

		annotation SummarizationSetBy = Automatic

	column name
		dataType: string
		lineageTag: e092227d-a06b-43b9-a8c4-9bd0d3176c4e
		sourceLineageTag: name
		summarizeBy: none
		sourceColumn: name

		annotation SummarizationSetBy = Automatic

	column region
		dataType: string
		lineageTag: 8d73d154-c059-4153-88c7-dde7e2b19918
		sourceLineageTag: region
		summarizeBy: none
		sourceColumn: region

		annotation SummarizationSetBy = Automatic

	column segment
		dataType: string
		lineageTag: 2cc3da8e-8b18-4b54-a365-9e047cca6574
		sourceLineageTag: segment
		summarizeBy: none
		sourceColumn: segment

		annotation SummarizationSetBy = Automatic

	column advisor_email
		dataType: string
		lineageTag: 49b23e92-226f-4590-9f0c-2130be472d94
		sourceLineageTag: advisor_email
		summarizeBy: none
		sourceColumn: advisor_email

		annotation SummarizationSetBy = Automatic

	partition sc_dim_customers = entity
		mode: directLake
		source
			entityName: sc_dim_customers
			expressionSource: 'DirectLake - Lakehouse_Insurance'
"@
    "sc_fact_bank_accounts" = @"
table sc_fact_bank_accounts
	lineageTag: f2e3c0cf-d05d-4ea6-a2e6-ca12f985989a
	sourceLineageTag: [dbo].[sc_fact_bank_accounts]

	column account_id
		dataType: string
		lineageTag: d32573a4-150d-46fd-8f33-218ed6891e2f
		sourceLineageTag: account_id
		summarizeBy: none
		sourceColumn: account_id

		annotation SummarizationSetBy = Automatic

	column customer_id
		dataType: string
		lineageTag: 95fa1193-5eb7-4f5e-8292-d60880d9adda
		sourceLineageTag: customer_id
		summarizeBy: none
		sourceColumn: customer_id

		annotation SummarizationSetBy = Automatic

	column product_type
		dataType: string
		lineageTag: 0020b654-f606-4c7c-9009-8e1fd429ee5b
		sourceLineageTag: product_type
		summarizeBy: none
		sourceColumn: product_type

		annotation SummarizationSetBy = Automatic

	column balance
		dataType: double
		lineageTag: 5a063c8a-7b34-4d6c-83e0-faf5456b5cae
		sourceLineageTag: balance
		summarizeBy: sum
		sourceColumn: balance

		annotation SummarizationSetBy = Automatic

		annotation PBI_FormatHint = {"isGeneralNumber":true}

	partition sc_fact_bank_accounts = entity
		mode: directLake
		source
			entityName: sc_fact_bank_accounts
			expressionSource: 'DirectLake - Lakehouse_Insurance'
"@
    "sc_bridge_ins_customers" = @"
table sc_bridge_ins_customers
	lineageTag: 4e1aa405-1470-4e05-83dd-42d6c167fc89
	sourceLineageTag: [dbo].[sc_bridge_ins_customers]

	column bridge_id
		dataType: string
		lineageTag: f4c0109d-5efc-4cc6-aa36-4592a58a60c8
		sourceLineageTag: bridge_id
		summarizeBy: none
		sourceColumn: bridge_id

		annotation SummarizationSetBy = Automatic

	column customer_id
		dataType: string
		lineageTag: 36cba9b7-a2e5-4142-bd51-2814b5e6d939
		sourceLineageTag: customer_id
		summarizeBy: none
		sourceColumn: customer_id

		annotation SummarizationSetBy = Automatic

	column insurance_consent
		dataType: boolean
		formatString: """TRUE"";""TRUE"";""FALSE"""
		lineageTag: 0f9fafa9-6579-40b0-9fbc-63561ac5553b
		sourceLineageTag: insurance_consent
		summarizeBy: none
		sourceColumn: insurance_consent

		annotation SummarizationSetBy = Automatic

	column sharing_scope
		dataType: string
		lineageTag: 489be453-1222-43bf-9545-81bdb4f11d98
		sourceLineageTag: sharing_scope
		summarizeBy: none
		sourceColumn: sharing_scope

		annotation SummarizationSetBy = Automatic

	partition sc_bridge_ins_customers = entity
		mode: directLake
		source
			entityName: sc_bridge_ins_customers
			expressionSource: 'DirectLake - Lakehouse_Insurance'
"@
    "insurance_contracts" = @"
table insurance_contracts
	lineageTag: e90ec974-3a21-44f0-950f-e8e05be2981b
	sourceLineageTag: [dbo].[insurance_contracts]

	column contract_id
		dataType: string
		lineageTag: 3a2c5721-9001-4205-9c31-e25a3bab16fc
		sourceLineageTag: contract_id
		summarizeBy: none
		sourceColumn: contract_id

		annotation SummarizationSetBy = Automatic

	column customer_id
		dataType: string
		lineageTag: 1b44f128-7706-423e-bd50-1698079ad042
		sourceLineageTag: customer_id
		summarizeBy: none
		sourceColumn: customer_id

		annotation SummarizationSetBy = Automatic

	column contract_type
		dataType: string
		lineageTag: 026139a4-e5a5-49fa-89e2-dffdecd2c5d9
		sourceLineageTag: contract_type
		summarizeBy: none
		sourceColumn: contract_type

		annotation SummarizationSetBy = Automatic

	column product_label
		dataType: string
		lineageTag: 484efd57-3aec-424a-81d9-511d267f9b12
		sourceLineageTag: product_label
		summarizeBy: none
		sourceColumn: product_label

		annotation SummarizationSetBy = Automatic

	column premium
		dataType: double
		lineageTag: 7fba4c11-9a9f-4f83-9ffc-f1cc6d97434e
		sourceLineageTag: premium
		summarizeBy: sum
		sourceColumn: premium

		annotation SummarizationSetBy = Automatic

		annotation PBI_FormatHint = {"isGeneralNumber":true}

	column status
		dataType: string
		lineageTag: 803eee31-049f-4daa-b95c-18703d6f55d0
		sourceLineageTag: status
		summarizeBy: none
		sourceColumn: status

		annotation SummarizationSetBy = Automatic

	partition insurance_contracts = entity
		mode: directLake
		source
			entityName: insurance_contracts
			expressionSource: 'DirectLake - Lakehouse_Insurance'
"@
    "insurance_claims" = @"
table insurance_claims
	lineageTag: 455e463e-e6dc-4aea-9ee1-85c0c70f5e3b
	sourceLineageTag: [dbo].[insurance_claims]

	column claim_id
		dataType: string
		lineageTag: 4f038c23-8af5-42ff-a0d9-b35ef81abd60
		sourceLineageTag: claim_id
		summarizeBy: none
		sourceColumn: claim_id

		annotation SummarizationSetBy = Automatic

	column contract_id
		dataType: string
		lineageTag: 48e4876e-0217-4f97-9013-910d110276ba
		sourceLineageTag: contract_id
		summarizeBy: none
		sourceColumn: contract_id

		annotation SummarizationSetBy = Automatic

	column claim_date
		dataType: dateTime
		formatString: General Date
		lineageTag: 58b66ff4-0c04-46c7-95cd-e9d3a7db1115
		sourceLineageTag: claim_date
		summarizeBy: none
		sourceColumn: claim_date

		annotation SummarizationSetBy = Automatic

	column claim_type
		dataType: string
		lineageTag: 73001dcd-3cf0-4192-bf9a-0377ba30dd9f
		sourceLineageTag: claim_type
		summarizeBy: none
		sourceColumn: claim_type

		annotation SummarizationSetBy = Automatic

	column amount
		dataType: double
		lineageTag: 40357a0e-03a5-4fee-a4b8-3b2715db124d
		sourceLineageTag: amount
		summarizeBy: none
		sourceColumn: amount

		annotation SummarizationSetBy = Automatic

		annotation PBI_FormatHint = {"isGeneralNumber":true}

	column status
		dataType: string
		lineageTag: f236f813-86b4-4fbb-8b36-8efa93a9bcf3
		sourceLineageTag: status
		summarizeBy: none
		sourceColumn: status

		annotation SummarizationSetBy = Automatic

	partition insurance_claims = entity
		mode: directLake
		source
			entityName: insurance_claims
			expressionSource: 'DirectLake - Lakehouse_Insurance'
"@
    "security_table" = @"
table security_table
	lineageTag: d9913dcf-5868-4a5c-b3f3-09ae4f5f25c2
	sourceLineageTag: [dbo].[security_table]

	column user_email
		dataType: string
		lineageTag: 6bb960fd-ce56-43ea-a83d-e9a001748c1d
		sourceLineageTag: user_email
		summarizeBy: none
		sourceColumn: user_email

		annotation SummarizationSetBy = Automatic

	column customer_id
		dataType: string
		lineageTag: 7c393ca0-20bd-41ec-829a-ce40269ffcd2
		sourceLineageTag: customer_id
		summarizeBy: none
		sourceColumn: customer_id

		annotation SummarizationSetBy = Automatic

	partition security_table = entity
		mode: directLake
		source
			entityName: security_table
			expressionSource: 'DirectLake - Lakehouse_Insurance'
"@
}

# ── Fonction d'encodage Base64 ────────────────────────────────────────────────
function To-B64 { param([string]$s) [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($s)) }

# ── Construction des parts ────────────────────────────────────────────────────
$parts = @(
    @{ path = "definition.pbism";               payload = (To-B64 $pbism);             payloadType = "InlineBase64" }
    @{ path = "definition/database.tmdl";        payload = (To-B64 $tmdlDatabase);      payloadType = "InlineBase64" }
    @{ path = "definition/model.tmdl";           payload = (To-B64 $tmdlModel);         payloadType = "InlineBase64" }
    @{ path = "definition/expressions.tmdl";     payload = (To-B64 $tmdlExpressions);   payloadType = "InlineBase64" }
    @{ path = "definition/relationships.tmdl";   payload = (To-B64 $tmdlRelationships); payloadType = "InlineBase64" }
    @{ path = "definition/roles/BankingAdvisor.tmdl"; payload = (To-B64 $tmdlBankingAdvisor); payloadType = "InlineBase64" }
    @{ path = "definition/roles/InsuranceUser.tmdl";  payload = (To-B64 $tmdlInsuranceUser);  payloadType = "InlineBase64" }
)
foreach ($tbl in $tmdlTables.Keys) {
    $parts += @{ path = "definition/tables/" + $tbl + ".tmdl"; payload = (To-B64 $tmdlTables[$tbl]); payloadType = "InlineBase64" }
}

$bodyObj = @{
    definition = @{
        format = "TMDL"
        parts  = $parts
    }
}
$bodyJson = $bodyObj | ConvertTo-Json -Depth 10

# ── updateDefinition ──────────────────────────────────────────────────────────
Write-Host "Updating SEM_Insurance definition (TMDL)..."
try {
    $resp = Invoke-WebRequest -Method POST `
        -Uri ("https://api.fabric.microsoft.com/v1/workspaces/" + $wsI + "/semanticModels/" + $smId + "/updateDefinition") `
        -Headers $h -Body $bodyJson -UseBasicParsing

    Write-Host ("HTTP " + $resp.StatusCode)
    $loc = $resp.Headers["Location"]

    if ($resp.StatusCode -eq 200) {
        Write-Host "Updated synchronously!"
    } elseif ($loc) {
        Write-Host ("Polling: " + $loc)
        $elapsed = 0
        do {
            Start-Sleep 10; $elapsed += 10
            $op = Invoke-RestMethod -Uri $loc -Headers @{ Authorization = "Bearer $fabToken" }
            Write-Host ("[" + $elapsed + "s] " + $op.status)
            if ($op.status -in @("Succeeded","Failed","Cancelled")) { break }
        } while ($elapsed -lt 120)
        Write-Host ("Final: " + $op.status)
        if ($op.error) { Write-Host ($op.error | ConvertTo-Json) }
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

Write-Host ""
Write-Host "=== SEM_Insurance updated ==="
Write-Host "Roles:"
Write-Host "  BankingAdvisor : [advisor_email] = USERPRINCIPALNAME()"
Write-Host "  InsuranceUser  : [customer_id] IN bridge + sc_fact_bank_accounts = FALSE()"
Write-Host ""
Write-Host "To test: app.fabric.microsoft.com -> WS-Insurance -> SEM_Insurance -> View as role"
