# Re-upload dim_customers + security_table avec de vrais emails du tenant
# Mapping :
#   advisor1@bank.com        -> hugo.lambert@MngEnvMCAP578215.onmicrosoft.com      (BankingAdvisor)
#   advisor2@bank.com        -> isabelle.fontaine@MngEnvMCAP578215.onmicrosoft.com  (BankingAdvisor)
#   insurance_user@pacifica  -> sophie.marchand@MngEnvMCAP578215.onmicrosoft.com    (InsuranceUser)

$olToken  = (& az account get-access-token --resource https://storage.azure.com --query accessToken -o tsv)
$olHdr    = @{ Authorization = "Bearer $olToken"; "x-ms-version" = "2023-01-03" }
$wsI      = "cbc321b0-5e65-41c1-a98c-eea5781305b7"
$lhI      = "317f23e4-0dd7-4ace-9780-2c81c342bd5a"
$olBase   = "https://onelake.dfs.fabric.microsoft.com/$wsI/$lhI/Files"

$a1 = "hugo.lambert@MngEnvMCAP578215.onmicrosoft.com"
$a2 = "isabelle.fontaine@MngEnvMCAP578215.onmicrosoft.com"
$iu = "sophie.marchand@MngEnvMCAP578215.onmicrosoft.com"

$nl = "`n"

$dimCustomers = "customer_id,name,region,segment,advisor_email" + $nl +
"CUS-001,Marie Dupont,Ile-de-France,PREMIUM,$a1" + $nl +
"CUS-002,Jean Martin,Occitanie,STANDARD,$a1" + $nl +
"CUS-003,Sophie Leroy,Auvergne-RA,YOUNG,$a2" + $nl +
"CUS-004,Pierre Bernard,PACA,PREMIUM,$a2" + $nl +
"CUS-005,Isabelle Moreau,Bretagne,STANDARD,$a1" + $nl +
"CUS-006,Thomas Simon,Normandie,YOUNG,$a2" + $nl +
"CUS-007,Claire Laurent,Grand Est,PREMIUM,$a1" + $nl +
"CUS-008,Francois Petit,Hauts-de-Fr,STANDARD,$a2" + $nl +
"CUS-009,Nathalie Garcia,Nouvelle-Aq,STANDARD,$a1" + $nl +
"CUS-010,Luc Roux,Pays de Loire,PREMIUM,$a2"

$security = "user_email,customer_id" + $nl +
"$a1,CUS-001" + $nl +
"$a1,CUS-002" + $nl +
"$a1,CUS-005" + $nl +
"$a1,CUS-007" + $nl +
"$a1,CUS-009" + $nl +
"$a2,CUS-003" + $nl +
"$a2,CUS-004" + $nl +
"$a2,CUS-006" + $nl +
"$a2,CUS-008" + $nl +
"$a2,CUS-010" + $nl +
"$iu,CUS-001" + $nl +
"$iu,CUS-002" + $nl +
"$iu,CUS-004" + $nl +
"$iu,CUS-007" + $nl +
"$iu,CUS-009"

function Upload-Csv {
    param($File, $Csv)
    $url   = "$olBase/$File"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Csv)

    # Create
    Invoke-RestMethod -Method PUT -Uri ($url + "?resource=file") -Headers $olHdr | Out-Null
    # Append
    Invoke-RestMethod -Method PATCH -Uri ($url + "?action=append&position=0") `
        -Headers ($olHdr + @{"Content-Type"="text/plain"}) -Body $bytes | Out-Null
    # Flush
    Invoke-RestMethod -Method PATCH -Uri ($url + "?action=flush&position=" + $bytes.Length) -Headers $olHdr | Out-Null
    Write-Host "  ✅ $File uploadé ($($bytes.Length) bytes)"
}

Write-Host "Upload des CSVs avec vrais emails..."
Upload-Csv -File "dim_customers.csv"    -Csv $dimCustomers
Upload-Csv -File "security_table.csv"   -Csv $security

Write-Host ""
Write-Host "=== Mapping comptes de test ==="
Write-Host "BankingAdvisor #1 : $a1"
Write-Host "  -> Clients : CUS-001 Marie Dupont, CUS-002 Jean Martin, CUS-005 Isabelle Moreau, CUS-007 Claire Laurent, CUS-009 Nathalie Garcia"
Write-Host ""
Write-Host "BankingAdvisor #2 : $a2"
Write-Host "  -> Clients : CUS-003 Sophie Leroy, CUS-004 Pierre Bernard, CUS-006 Thomas Simon, CUS-008 Francois Petit, CUS-010 Luc Roux"
Write-Host ""
Write-Host "InsuranceUser     : $iu"
Write-Host "  -> Clients avec consentement : CUS-001, CUS-002, CUS-004, CUS-007, CUS-009"
Write-Host "  -> balance NON visible (FALSE() sur sc_fact_bank_accounts)"
