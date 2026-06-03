<#
.SYNOPSIS
    [OPTIONAL / EXAMPLE] Export / import des permissions SSRS (rôles système et item-level policies).

.DESCRIPTION
    ⚠️ Ce script est fourni à titre d'EXEMPLE. Il n'est pertinent que dans le
    scénario d'une réinstallation propre (la base ReportServer n'est PAS
    restaurée). Dans le chemin recommandé du guide (RESTORE de la base +
    réapplication de la clé de chiffrement), les permissions sont migrées
    automatiquement et ce script n'est pas nécessaire.

    À tester impérativement sur un environnement de non-production avant tout
    usage en production.

    Étape 4 du guide (optionnelle).

.PARAMETER Mode
    Export ou Import.

.PARAMETER ReportServerUri
    URL du Web Service SSRS (source en Export, cible en Import).

.PARAMETER File
    Fichier JSON (sortie en Export, entrée en Import).

.PARAMETER Credential
    Optionnel.

.EXAMPLE
    .\04-Migrate-SSRSPermissions.ps1 -Mode Export -ReportServerUri "http://OLD-SSRS/ReportServer" -File ".\out\permissions.json"
    .\04-Migrate-SSRSPermissions.ps1 -Mode Import -ReportServerUri "http://NEW-SSRS/ReportServer" -File ".\out\permissions.json"
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)] [ValidateSet('Export','Import')] [string] $Mode,
    [Parameter(Mandatory = $true)] [string] $ReportServerUri,
    [Parameter(Mandatory = $true)] [string] $File,
    [Parameter(Mandatory = $false)][pscredential] $Credential
)

$ErrorActionPreference = 'Stop'
Import-Module ReportingServicesTools

$proxyParams = @{ ReportServerUri = $ReportServerUri }
if ($Credential) { $proxyParams.Credential = $Credential }
$proxy = New-RsWebServiceProxy @proxyParams

if ($Mode -eq 'Export') {
    $catalog = $proxy.ListChildren("/", $true)
    $items = @()
    foreach ($it in $catalog) {
        $inherit = $true
        try {
            $policies = $proxy.GetPolicies($it.Path, [ref]$inherit)
            $items += [PSCustomObject]@{
                Path     = $it.Path
                TypeName = $it.TypeName
                Inherit  = $inherit
                Policies = @($policies | ForEach-Object {
                    [PSCustomObject]@{
                        GroupUserName = $_.GroupUserName
                        Roles         = @($_.Roles | ForEach-Object { $_.Name })
                    }
                })
            }
        } catch { Write-Warning "Lecture policies KO sur $($it.Path) : $_" }
    }
    $items | ConvertTo-Json -Depth 6 | Out-File $File -Encoding utf8
    Write-Host "Export terminé : $File ($($items.Count) items)" -ForegroundColor Green
}
else {
    $items = Get-Content $File -Raw | ConvertFrom-Json

    # Récupération des rôles disponibles côté cible
    $availableRoles = @{}
    foreach ($r in $proxy.ListRoles('Catalog', $null)) { $availableRoles[$r.Name] = $r }
    foreach ($r in $proxy.ListRoles('System', $null))  { $availableRoles[$r.Name] = $r }

    foreach ($item in $items) {
        if ($item.Inherit) { continue }   # héritage par défaut, rien à appliquer
        try {
            $policyArray = @()
            foreach ($p in $item.Policies) {
                $policy = New-Object ($proxy.GetType().Namespace + '.Policy')
                $policy.GroupUserName = $p.GroupUserName
                $roleObjs = @()
                foreach ($roleName in $p.Roles) {
                    if ($availableRoles.ContainsKey($roleName)) {
                        $roleObjs += $availableRoles[$roleName]
                    } else { Write-Warning "Rôle absent côté cible : $roleName ($($item.Path))" }
                }
                $policy.Roles = $roleObjs
                $policyArray += $policy
            }
            if ($PSCmdlet.ShouldProcess($item.Path, "SetPolicies")) {
                $proxy.SetPolicies($item.Path, $policyArray)
            }
        } catch { Write-Warning "SetPolicies KO sur $($item.Path) : $_" }
    }
    Write-Host "Import terminé." -ForegroundColor Green
}
