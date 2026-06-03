<#
.SYNOPSIS
    [OPTIONAL / EXAMPLE] Export / import des souscriptions SSRS (planifiées et data-driven).

.DESCRIPTION
    ⚠️ Ce script est fourni à titre d'EXEMPLE et présente le RISQUE LE PLUS
    ÉLEVÉ du kit. Le round-trip JSON via Get-RsSubscription / Set-RsSubscription
    n'est pas officiellement supporté par Microsoft et peut échouer sur des
    souscriptions complexes (data-driven, file share, delivery extensions
    customisées).

    Dans le chemin recommandé du guide (RESTORE de la base + clé), les
    souscriptions sont migrées automatiquement et ce script n'est pas nécessaire.

    À tester impérativement sur un environnement de non-production avant tout
    usage en production.

    Étape 7 du guide (optionnelle).

.PARAMETER Mode
    Export ou Import.

.PARAMETER ReportServerUri
    URL Web Service SSRS.

.PARAMETER File
    Fichier JSON.

.PARAMETER EmailDomainMap
    Optionnel. CSV From,To pour réécrire des domaines/adresses email pendant l'import.

.EXAMPLE
    .\07-Migrate-SSRSSubscriptions.ps1 -Mode Export -ReportServerUri "http://OLD-SSRS/ReportServer" -File ".\out\subs.json"
    .\07-Migrate-SSRSSubscriptions.ps1 -Mode Import -ReportServerUri "http://NEW-SSRS/ReportServer" -File ".\out\subs.json"
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)] [ValidateSet('Export','Import')] [string] $Mode,
    [Parameter(Mandatory = $true)] [string] $ReportServerUri,
    [Parameter(Mandatory = $true)] [string] $File,
    [Parameter(Mandatory = $false)][string] $EmailDomainMap
)

$ErrorActionPreference = 'Stop'
Import-Module ReportingServicesTools

$proxy = New-RsWebServiceProxy -ReportServerUri $ReportServerUri

if ($Mode -eq 'Export') {
    $reports = $proxy.ListChildren("/", $true) | Where-Object { $_.TypeName -eq 'Report' }
    $all = @()
    foreach ($r in $reports) {
        try {
            $subs = Get-RsSubscription -ReportServerUri $ReportServerUri -Path $r.Path -ErrorAction Stop
            foreach ($s in $subs) { $all += $s }
        } catch { Write-Warning "Subs KO $($r.Path) : $_" }
    }
    $all | ConvertTo-Json -Depth 10 | Out-File $File -Encoding utf8
    Write-Host "Export terminé : $($all.Count) souscriptions -> $File" -ForegroundColor Green
}
else {
    $map = @()
    if ($EmailDomainMap -and (Test-Path $EmailDomainMap)) { $map = Import-Csv $EmailDomainMap }

    $subs = Get-Content $File -Raw | ConvertFrom-Json
    foreach ($s in $subs) {
        # Réécriture des emails si demandé
        if ($s.DeliverySettings -and $s.DeliverySettings.ParameterValues) {
            foreach ($pv in $s.DeliverySettings.ParameterValues) {
                if ($pv.Name -in @('TO','CC','BCC') -and $pv.Value) {
                    foreach ($m in $map) { $pv.Value = ($pv.Value -replace [regex]::Escape($m.From), $m.To) }
                }
            }
        }

        $target = $s.Report
        if (-not $target) { Write-Warning "Souscription sans Report : skip"; continue }

        if ($PSCmdlet.ShouldProcess($target, "Set-RsSubscription")) {
            try {
                Set-RsSubscription -ReportServerUri $ReportServerUri -Subscription $s -ErrorAction Stop
            } catch {
                Write-Warning "Import KO sur $target : $_"
            }
        }
    }
    Write-Host "Import terminé." -ForegroundColor Green
    Write-Host "⚠️ Vérifier manuellement les souscriptions data-driven (datasource + requête de paramétrage)." -ForegroundColor Yellow
}
