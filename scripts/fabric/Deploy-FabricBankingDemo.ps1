param(
    [string]$WsBankingId   = "5015e396-cb2d-4fbe-8ebf-c87544cf6bfd",
    [string]$WsInsuranceId = "cbc321b0-5e65-41c1-a98c-eea5781305b7",
    [string]$LhBankingId   = "8093805b-3709-454e-9998-015b9faaf3c0",
    [string]$LhInsuranceId = "317f23e4-0dd7-4ace-9780-2c81c342bd5a"
)

Write-Host "Getting tokens..."
$fabToken = (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
$olToken  = (& az account get-access-token --resource https://storage.azure.com --query accessToken -o tsv)
$fabHdr   = @{ Authorization = "Bearer $fabToken"; "Content-Type" = "application/json" }
$olHdr    = @{ Authorization = "Bearer $olToken"; "x-ms-version" = "2023-01-03" }

$olB = "https://onelake.dfs.fabric.microsoft.com/$WsBankingId/$LhBankingId"
$olI = "https://onelake.dfs.fabric.microsoft.com/$WsInsuranceId/$LhInsuranceId"
Write-Host "Tokens OK"

function Upload-Csv {
    param([string]$Base, [hashtable]$Hdr, [string]$File, [string]$Csv)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Csv)
    $url   = $Base + "/Files/data/" + $File
    Invoke-RestMethod -Method PUT -Uri ($url + "?resource=file") -Headers $Hdr | Out-Null
    $h2 = $Hdr.Clone()
    $h2["Content-Type"] = "application/octet-stream"
    Invoke-RestMethod -Method PATCH -Uri ($url + "?action=append&position=0") -Headers $h2 -Body $bytes | Out-Null
    Invoke-RestMethod -Method PATCH -Uri ($url + "?action=flush&position=" + $bytes.Length) -Headers $Hdr | Out-Null
    Write-Host ("  OK " + $File + " (" + $bytes.Length + " bytes)")
}

Write-Host "Creating directories..."
try { Invoke-RestMethod -Method PUT -Uri ($olB + "/Files/data?resource=directory") -Headers $olHdr | Out-Null } catch {}
try { Invoke-RestMethod -Method PUT -Uri ($olI + "/Files/data?resource=directory") -Headers $olHdr | Out-Null } catch {}

$nl = [System.Environment]::NewLine

$dimCustomers = "customer_id,name,region,segment,advisor_email" + $nl +
"CUS-001,Marie Dupont,Ile-de-France,PREMIUM,advisor1@bank.com" + $nl +
"CUS-002,Jean Martin,Occitanie,STANDARD,advisor1@bank.com" + $nl +
"CUS-003,Sophie Leroy,Auvergne-RA,YOUNG,advisor2@bank.com" + $nl +
"CUS-004,Pierre Bernard,PACA,PREMIUM,advisor2@bank.com" + $nl +
"CUS-005,Isabelle Moreau,Bretagne,STANDARD,advisor1@bank.com" + $nl +
"CUS-006,Thomas Simon,Normandie,YOUNG,advisor2@bank.com" + $nl +
"CUS-007,Claire Laurent,Grand Est,PREMIUM,advisor1@bank.com" + $nl +
"CUS-008,Francois Petit,Hauts-de-Fr,STANDARD,advisor2@bank.com" + $nl +
"CUS-009,Nathalie Garcia,Nouvelle-Aq,STANDARD,advisor1@bank.com" + $nl +
"CUS-010,Luc Roux,Pays de Loire,PREMIUM,advisor2@bank.com"

$bankAccounts = "account_id,customer_id,product_type,balance" + $nl +
"ACC-001,CUS-001,CHECKING,12450.0" + $nl +
"ACC-002,CUS-001,SAVINGS,45000.0" + $nl +
"ACC-003,CUS-002,CHECKING,3200.0" + $nl +
"ACC-004,CUS-003,CHECKING,1800.0" + $nl +
"ACC-005,CUS-004,LOAN,-25000.0" + $nl +
"ACC-006,CUS-004,SAVINGS,78000.0" + $nl +
"ACC-007,CUS-005,CHECKING,5600.0" + $nl +
"ACC-008,CUS-006,CHECKING,920.0" + $nl +
"ACC-009,CUS-007,SAVINGS,120000.0" + $nl +
"ACC-010,CUS-008,CHECKING,4100.0" + $nl +
"ACC-011,CUS-009,CHECKING,7800.0" + $nl +
"ACC-012,CUS-010,SAVINGS,95000.0"

$bridge = "bridge_id,customer_id,insurance_consent,sharing_scope" + $nl +
"BRG-001,CUS-001,true,FULL" + $nl +
"BRG-002,CUS-002,true,BASIC" + $nl +
"BRG-003,CUS-004,true,FULL" + $nl +
"BRG-004,CUS-007,true,FULL" + $nl +
"BRG-005,CUS-009,true,BASIC"

$contracts = "contract_id,customer_id,contract_type,product_label,premium,status" + $nl +
"CTR-001,CUS-001,MRH,Multirisque Habitation,380.0,ACTIVE" + $nl +
"CTR-002,CUS-001,AUTO,Assurance Auto,820.0,ACTIVE" + $nl +
"CTR-003,CUS-002,AUTO,Assurance Auto,650.0,ACTIVE" + $nl +
"CTR-004,CUS-004,VIE,Assurance Vie,1200.0,ACTIVE" + $nl +
"CTR-005,CUS-007,PREV,Prevoyance,540.0,ACTIVE" + $nl +
"CTR-006,CUS-009,MRH,Multirisque Habitation,290.0,ACTIVE"

$claims = "claim_id,contract_id,claim_date,claim_type,amount,status" + $nl +
"CLM-001,CTR-001,2024-03-15,Degat des eaux,2400.0,CLOSED" + $nl +
"CLM-002,CTR-002,2024-07-22,Accident auto,8700.0,OPEN" + $nl +
"CLM-003,CTR-003,2025-01-10,Bris de glace,450.0,CLOSED" + $nl +
"CLM-004,CTR-005,2025-05-30,Arret de travail,3200.0,OPEN"

$security = "user_email,customer_id" + $nl +
"advisor1@bank.com,CUS-001" + $nl +
"advisor1@bank.com,CUS-002" + $nl +
"advisor1@bank.com,CUS-005" + $nl +
"advisor1@bank.com,CUS-007" + $nl +
"advisor1@bank.com,CUS-009" + $nl +
"advisor2@bank.com,CUS-003" + $nl +
"advisor2@bank.com,CUS-004" + $nl +
"advisor2@bank.com,CUS-006" + $nl +
"advisor2@bank.com,CUS-008" + $nl +
"advisor2@bank.com,CUS-010" + $nl +
"insurance_user@pacifica.com,CUS-001" + $nl +
"insurance_user@pacifica.com,CUS-002" + $nl +
"insurance_user@pacifica.com,CUS-004" + $nl +
"insurance_user@pacifica.com,CUS-007" + $nl +
"insurance_user@pacifica.com,CUS-009"

Write-Host "Uploading Banking tables..."
Upload-Csv -Base $olB -Hdr $olHdr -File "dim_customers.csv"        -Csv $dimCustomers
Upload-Csv -Base $olB -Hdr $olHdr -File "fact_bank_accounts.csv"   -Csv $bankAccounts
Upload-Csv -Base $olB -Hdr $olHdr -File "bridge_ins_customers.csv" -Csv $bridge

Write-Host "Uploading Insurance tables..."
Upload-Csv -Base $olI -Hdr $olHdr -File "insurance_contracts.csv"  -Csv $contracts
Upload-Csv -Base $olI -Hdr $olHdr -File "insurance_claims.csv"     -Csv $claims
Upload-Csv -Base $olI -Hdr $olHdr -File "security_table.csv"       -Csv $security

function New-FabricNotebook {
    param([string]$WsId, [string]$LhId, [string]$LhName, [string]$NbName, [string[]]$Tables)
    $lines = $Tables | ForEach-Object {
        "df = spark.read.option(" + [char]39 + "header" + [char]39 + "," + [char]39 + "true" + [char]39 + ").option(" + [char]39 + "inferSchema" + [char]39 + "," + [char]39 + "true" + [char]39 + ").csv(" + [char]39 + "Files/data/" + $_ + ".csv" + [char]39 + ")" + $nl +
        "df.write.format(" + [char]39 + "delta" + [char]39 + ").mode(" + [char]39 + "overwrite" + [char]39 + ").saveAsTable(" + [char]39 + $_ + [char]39 + ")" + $nl +
        "print(" + [char]39 + $_ + ": " + [char]39 + " + str(df.count()) + " + [char]39 + " rows" + [char]39 + ")"
    }
    $src = ($lines -join $nl) + $nl + "print(" + [char]39 + "ALL DONE" + [char]39 + ")"

    $cellObj = [ordered]@{
        cell_type       = "code"
        execution_count = $null
        metadata        = @{}
        outputs         = @()
        source          = @($src)
    }
    $nbObj = [ordered]@{
        nbformat       = 4
        nbformat_minor = 5
        metadata       = [ordered]@{
            kernelspec    = @{ display_name = "PySpark"; language = "python"; name = "synapse_pyspark" }
            language_info = @{ name = "python" }
            trident       = @{
                lakehouse = @{
                    default_lakehouse              = $LhId
                    default_lakehouse_name         = $LhName
                    default_lakehouse_workspace_id = $WsId
                }
            }
        }
        cells = @($cellObj)
    }
    $ipynb = $nbObj | ConvertTo-Json -Depth 15 -Compress
    $b64   = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($ipynb))

    $bodyObj = [ordered]@{
        displayName = $NbName
        definition  = @{
            format = "ipynb"
            parts  = @(@{ path = "artifact.content.ipynb"; payload = $b64; payloadType = "InlineBase64" })
        }
    }
    $body = $bodyObj | ConvertTo-Json -Depth 10

    try {
        $r = Invoke-RestMethod -Method POST -Uri ("https://api.fabric.microsoft.com/v1/workspaces/" + $WsId + "/notebooks") -Headers $fabHdr -Body $body
        Write-Host ("  OK " + $NbName + " id=" + $r.id)
        return $r.id
    } catch {
        Write-Host ("  WARN " + $NbName + ": " + $_.Exception.Message)
        return $null
    }
}

Write-Host "Creating notebooks..."
$nbBId = New-FabricNotebook -WsId $WsBankingId   -LhId $LhBankingId   -LhName "Lakehouse_Banking"   -NbName "Load_Banking_Tables"   -Tables @("dim_customers","fact_bank_accounts","bridge_ins_customers")
$nbIId = New-FabricNotebook -WsId $WsInsuranceId -LhId $LhInsuranceId -LhName "Lakehouse_Insurance" -NbName "Load_Insurance_Tables" -Tables @("insurance_contracts","insurance_claims","security_table")

function Run-Notebook {
    param([string]$WsId, [string]$NbId, [string]$Label)
    if (-not $NbId) { Write-Host ("  SKIP " + $Label); return }
    Write-Host ("Running " + $Label + "...")
    $runBody = (@{ executionData = @{} } | ConvertTo-Json -Compress)
    try {
        $job   = Invoke-RestMethod -Method POST -Uri ("https://api.fabric.microsoft.com/v1/workspaces/" + $WsId + "/notebooks/" + $NbId + "/jobs/instances?jobType=RunNotebook") -Headers $fabHdr -Body $runBody
        $jobId = $job.id
        if (-not $jobId) { Write-Host "  Submitted async"; return }
        $elapsed = 0
        do {
            Start-Sleep 15; $elapsed += 15
            $s = Invoke-RestMethod -Uri ("https://api.fabric.microsoft.com/v1/workspaces/" + $WsId + "/notebooks/" + $NbId + "/jobs/instances/" + $jobId) -Headers $fabHdr
            Write-Host ("  [" + $elapsed + "s] " + $s.status)
        } while ($s.status -notin @("Succeeded","Failed","Cancelled") -and $elapsed -lt 300)
        Write-Host ("  DONE: " + $s.status)
    } catch {
        Write-Host ("  ERROR: " + $_.Exception.Message)
    }
}

Run-Notebook -WsId $WsBankingId   -NbId $nbBId -Label "Load_Banking_Tables"
Run-Notebook -WsId $WsInsuranceId -NbId $nbIId -Label "Load_Insurance_Tables"

Write-Host "=== DEPLOYMENT COMPLETE ==="
Write-Host ("WS-Banking   : " + $WsBankingId)
Write-Host ("WS-Insurance : " + $WsInsuranceId)
Write-Host ("LH-Banking   : " + $LhBankingId)
Write-Host ("LH-Insurance : " + $LhInsuranceId)
Write-Host "NEXT: Create OneLake shortcuts in LH-Insurance, then Direct Lake Semantic Model + RLS"
