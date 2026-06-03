<#
.SYNOPSIS
    Audit complet d'une instance SSRS : rapports, sources de données, souscriptions, permissions.

.DESCRIPTION
    Étape 1 du guide de migration SSRS. Produit des fichiers CSV/JSON consommables
    pour la planification de la migration et pour la recette finale.

.PARAMETER ReportServerUri
    URL du Web Service SSRS (ex. http://OLD-SSRS/ReportServer).

.PARAMETER OutputFolder
    Dossier de sortie. Sera créé si nécessaire.

.PARAMETER Credential
    Optionnel. Credential PSCredential si exécution depuis un poste hors domaine.

.EXAMPLE
    .\01-Audit-SSRS.ps1 -ReportServerUri "http://OLD-SSRS/ReportServer" -OutputFolder ".\out\ssrs-audit"

.NOTES
    Requiert le module ReportingServicesTools.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]  [string] $ReportServerUri,
    [Parameter(Mandatory = $true)]  [string] $OutputFolder,
    [Parameter(Mandatory = $false)] [pscredential] $Credential
)

$ErrorActionPreference = 'Stop'
Import-Module ReportingServicesTools

if (-not (Test-Path $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null }

$proxyParams = @{ ReportServerUri = $ReportServerUri }
if ($Credential) { $proxyParams.Credential = $Credential }
$proxy = New-RsWebServiceProxy @proxyParams

Write-Host "[1/5] Inventaire des dossiers et rapports..." -ForegroundColor Cyan
$catalog = $proxy.ListChildren("/", $true)

$reports = $catalog | Where-Object { $_.TypeName -eq 'Report' } | ForEach-Object {
    [PSCustomObject]@{
        Path         = $_.Path
        Name         = $_.Name
        CreatedBy    = $_.CreatedBy
        CreationDate = $_.CreationDate
        ModifiedBy   = $_.ModifiedBy
        ModifiedDate = $_.ModifiedDate
        Size         = $_.Size
        TypeName     = $_.TypeName
    }
}
$reports | Export-Csv (Join-Path $OutputFolder "reports.csv") -NoTypeInformation -Encoding utf8

$folders = $catalog | Where-Object { $_.TypeName -eq 'Folder' } | Select-Object Path, Name, CreationDate
$folders | Export-Csv (Join-Path $OutputFolder "folders.csv") -NoTypeInformation -Encoding utf8

Write-Host "[2/5] Inventaire des sources de données partagées..." -ForegroundColor Cyan
$ds = $catalog | Where-Object { $_.TypeName -eq 'DataSource' } | ForEach-Object {
    $def = $proxy.GetDataSourceContents($_.Path)
    [PSCustomObject]@{
        Path             = $_.Path
        Name             = $_.Name
        Extension        = $def.Extension
        ConnectString    = $def.ConnectString
        CredentialRetrieval = $def.CredentialRetrieval
        WindowsCredentials  = $def.WindowsCredentials
        ImpersonateUser     = $def.ImpersonateUser
        UserName            = $def.UserName
    }
}
$ds | Export-Csv (Join-Path $OutputFolder "datasources.csv") -NoTypeInformation -Encoding utf8

Write-Host "[3/5] Inventaire des souscriptions..." -ForegroundColor Cyan
$subs = @()
foreach ($r in $reports) {
    try {
        $rs = $proxy.ListSubscriptions($r.Path)
        foreach ($s in $rs) {
            $subs += [PSCustomObject]@{
                ReportPath        = $r.Path
                SubscriptionID    = $s.SubscriptionID
                Owner             = $s.Owner
                Description       = $s.Description
                Status            = $s.Status
                LastExecuted      = $s.LastExecuted
                EventType         = $s.EventType
                IsDataDriven      = $s.IsDataDriven
                ModifiedBy        = $s.ModifiedBy
                ModifiedDate      = $s.ModifiedDate
            }
        }
    } catch { Write-Warning "Subscriptions KO sur $($r.Path) : $_" }
}
$subs | Export-Csv (Join-Path $OutputFolder "subscriptions.csv") -NoTypeInformation -Encoding utf8

Write-Host "[4/5] Inventaire des permissions..." -ForegroundColor Cyan
$perms = @()
foreach ($item in $catalog) {
    try {
        $inherit = $true
        $policies = $proxy.GetPolicies($item.Path, [ref]$inherit)
        foreach ($p in $policies) {
            foreach ($role in $p.Roles) {
                $perms += [PSCustomObject]@{
                    Path           = $item.Path
                    TypeName       = $item.TypeName
                    GroupUserName  = $p.GroupUserName
                    Role           = $role.Name
                    InheritParent  = $inherit
                }
            }
        }
    } catch { Write-Warning "Policies KO sur $($item.Path) : $_" }
}
$perms | Export-Csv (Join-Path $OutputFolder "permissions.csv") -NoTypeInformation -Encoding utf8

Write-Host "[5/5] Synthèse..." -ForegroundColor Cyan
$summary = [PSCustomObject]@{
    AuditDate        = (Get-Date).ToString("s")
    ReportServerUri  = $ReportServerUri
    FolderCount      = ($folders | Measure-Object).Count
    ReportCount      = ($reports | Measure-Object).Count
    DataSourceCount  = ($ds | Measure-Object).Count
    SubscriptionCount= ($subs | Measure-Object).Count
    PermissionCount  = ($perms | Measure-Object).Count
    TotalReportBytes = ($reports | Measure-Object Size -Sum).Sum
}
$summary | ConvertTo-Json -Depth 4 | Out-File (Join-Path $OutputFolder "audit-summary.json") -Encoding utf8

Write-Host "Audit terminé. Sortie : $OutputFolder" -ForegroundColor Green
$summary | Format-List
