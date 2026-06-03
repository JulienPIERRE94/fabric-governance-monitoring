# Assigne les vrais utilisateurs aux rôles RLS de SEM_Insurance via Power BI API

$pbiToken = (& az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv)
$h = @{ Authorization = "Bearer $pbiToken"; "Content-Type" = "application/json" }
$wsI  = "cbc321b0-5e65-41c1-a98c-eea5781305b7"
$smId = "5809e89f-eb8c-4cc1-b7a9-bf95809f5b62"

# Vérifie d'abord les rôles existants
Write-Host "=== Rôles actuels ==="
$roles = Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups/$wsI/datasets/$smId/roles" -Headers $h
$roles.value | ForEach-Object { Write-Host "  $($_.name) -> $($_.members.Count) membres" }

# Mapping utilisateurs -> rôles
$assignments = @(
    @{ role = "BankingAdvisor"; email = "hugo.lambert@MngEnvMCAP578215.onmicrosoft.com" }
    @{ role = "BankingAdvisor"; email = "isabelle.fontaine@MngEnvMCAP578215.onmicrosoft.com" }
    @{ role = "InsuranceUser";  email = "sophie.marchand@MngEnvMCAP578215.onmicrosoft.com" }
)

Write-Host "`n=== Assignation des membres aux rôles ==="
foreach ($a in $assignments) {
    $body = @{
        value = @(
            @{
                emailAddress    = $a.email
                principalType   = "User"
            }
        )
    } | ConvertTo-Json -Depth 3

    try {
        $resp = Invoke-RestMethod -Method POST `
            -Uri "https://api.powerbi.com/v1.0/myorg/groups/$wsI/datasets/$smId/roles/$($a.role)/users" `
            -Headers $h -Body $body
        Write-Host "  ✅ $($a.email) -> $($a.role)"
    } catch {
        $err = $_.Exception.Response
        if ($err) {
            $rd = New-Object System.IO.StreamReader($err.GetResponseStream())
            Write-Host "  ❌ $($a.email) -> $($a.role) : $($rd.ReadToEnd())"
        } else {
            Write-Host "  ❌ $($a.email) -> $($a.role) : $($_.Exception.Message)"
        }
    }
}

Write-Host "`n=== Vérification finale ==="
$roles2 = Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups/$wsI/datasets/$smId/roles" -Headers $h
$roles2.value | ForEach-Object {
    Write-Host "`nRôle: $($_.name)"
    $_.members | ForEach-Object { Write-Host "  - $($_.emailAddress)" }
}
