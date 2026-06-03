<#
.SYNOPSIS
    [OPTIONAL / EXAMPLE] Migration des rapports RDL et de l'arborescence de dossiers SSRS.

.DESCRIPTION
    ⚠️ Ce script est fourni à titre d'EXEMPLE. Il n'est pertinent que dans le
    scénario d'une réinstallation propre (la base ReportServer n'est PAS
    restaurée). Dans le chemin recommandé du guide, les rapports sont migrés
    automatiquement avec la base.

    Le téléchargement / upload via Out-RsFolderContent / Write-RsFolderContent
    est fiable. En revanche, le commutateur -RebindDataSources est approximatif
    et ne doit pas être considéré comme robuste — préférer un rebinding manuel
    dans le portail.

    À tester impérativement sur un environnement de non-production avant tout
    usage en production.

    Étape 6 du guide (optionnelle).

.PARAMETER Mode
    Download ou Upload.

.PARAMETER ReportServerUri
    URL Web Service (source en Download, cible en Upload).

.PARAMETER LocalFolder
    Dossier local utilisé pour stocker les fichiers.

.PARAMETER RebindDataSources
    En Upload : pour chaque rapport, rebinde les références aux sources de données
    partagées si une datasource du même chemin existe côté cible.

.EXAMPLE
    .\06-Migrate-SSRSReports.ps1 -Mode Download -ReportServerUri "http://OLD-SSRS/ReportServer" -LocalFolder ".\out\reports"
    .\06-Migrate-SSRSReports.ps1 -Mode Upload   -ReportServerUri "http://NEW-SSRS/ReportServer" -LocalFolder ".\out\reports" -RebindDataSources
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)] [ValidateSet('Download','Upload')] [string] $Mode,
    [Parameter(Mandatory = $true)] [string] $ReportServerUri,
    [Parameter(Mandatory = $true)] [string] $LocalFolder,
    [Parameter(Mandatory = $false)][switch] $RebindDataSources
)

$ErrorActionPreference = 'Stop'
Import-Module ReportingServicesTools

if ($Mode -eq 'Download') {
    if (-not (Test-Path $LocalFolder)) { New-Item -ItemType Directory -Path $LocalFolder -Force | Out-Null }
    Write-Host "Téléchargement de l'arborescence depuis $ReportServerUri ..." -ForegroundColor Cyan
    Out-RsFolderContent -ReportServerUri $ReportServerUri -RsFolder "/" -Destination $LocalFolder -Recurse
    Write-Host "Téléchargement terminé : $LocalFolder" -ForegroundColor Green
}
else {
    Write-Host "Upload depuis $LocalFolder vers $ReportServerUri ..." -ForegroundColor Cyan
    if ($PSCmdlet.ShouldProcess($ReportServerUri, "Write-RsFolderContent /")) {
        Write-RsFolderContent -ReportServerUri $ReportServerUri -Path $LocalFolder -RsFolder "/" -Recurse -OverWrite
    }

    if ($RebindDataSources) {
        Write-Host "Rebinding des datasources partagées..." -ForegroundColor Cyan
        $proxy = New-RsWebServiceProxy -ReportServerUri $ReportServerUri
        $reports = $proxy.ListChildren("/", $true) | Where-Object { $_.TypeName -eq 'Report' }
        $availableDs = $proxy.ListChildren("/", $true) | Where-Object { $_.TypeName -eq 'DataSource' } | ForEach-Object { $_.Path }

        foreach ($r in $reports) {
            try {
                $dsRefs = $proxy.GetItemDataSources($r.Path)
                $changed = $false
                foreach ($ref in $dsRefs) {
                    if ($ref.Item -is [object] -and $ref.Item.GetType().Name -eq 'DataSourceReference') {
                        $target = $ref.Item.Reference
                        if ($availableDs -contains $target) {
                            $changed = $true   # déjà bon, on resubmit pour reset
                        }
                    }
                }
                if ($changed -and $PSCmdlet.ShouldProcess($r.Path, "SetItemDataSources")) {
                    $proxy.SetItemDataSources($r.Path, $dsRefs)
                }
            } catch { Write-Warning "Rebind KO $($r.Path) : $_" }
        }
    }
    Write-Host "Upload terminé." -ForegroundColor Green
}
