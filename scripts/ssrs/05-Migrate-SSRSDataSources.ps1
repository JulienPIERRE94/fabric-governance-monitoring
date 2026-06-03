<#
.SYNOPSIS
    [OPTIONAL / EXAMPLE] Migration des sources de données partagées SSRS entre deux instances.

.DESCRIPTION
    ⚠️ Ce script est fourni à titre d'EXEMPLE. Il n'est pertinent que dans le
    scénario d'une réinstallation propre (la base ReportServer n'est PAS
    restaurée). Dans le chemin recommandé du guide, les sources de données
    partagées sont migrées automatiquement avec la base et la clé.

    Limitations : les mots de passe stockés ne peuvent pas être exportés en
    clair ; les datasources en mode 'Store' doivent être ré-authentifiées
    manuellement après import.

    À tester impérativement sur un environnement de non-production avant tout
    usage en production.

    Étape 5 du guide (optionnelle).

.PARAMETER SourceUri
    URL Web Service SSRS source.

.PARAMETER TargetUri
    URL Web Service SSRS cible.

.PARAMETER ConnectionStringMap
    Optionnel. CSV avec colonnes 'From,To' pour transformer les chaînes de connexion.

.PARAMETER OutputFolder
    Dossier de log + dump des datasources nécessitant une saisie manuelle de mot de passe.

.EXAMPLE
    .\05-Migrate-SSRSDataSources.ps1 -SourceUri "http://OLD-SSRS/ReportServer" `
        -TargetUri "http://NEW-SSRS/ReportServer" `
        -ConnectionStringMap ".\config\connstr-mapping.csv" `
        -OutputFolder ".\out\ssrs-ds"
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]  [string] $SourceUri,
    [Parameter(Mandatory = $true)]  [string] $TargetUri,
    [Parameter(Mandatory = $false)] [string] $ConnectionStringMap,
    [Parameter(Mandatory = $false)] [string] $OutputFolder = ".\out\ssrs-ds"
)

$ErrorActionPreference = 'Stop'
Import-Module ReportingServicesTools

if (-not (Test-Path $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null }

$srcProxy = New-RsWebServiceProxy -ReportServerUri $SourceUri
$tgtProxy = New-RsWebServiceProxy -ReportServerUri $TargetUri

$map = @()
if ($ConnectionStringMap -and (Test-Path $ConnectionStringMap)) {
    $map = Import-Csv $ConnectionStringMap
}

function Convert-ConnectString {
    param([string]$s)
    foreach ($m in $map) { $s = $s.Replace($m.From, $m.To) }
    return $s
}

$datasources = $srcProxy.ListChildren("/", $true) | Where-Object { $_.TypeName -eq 'DataSource' }
$needsPassword = @()

foreach ($ds in $datasources) {
    Write-Host "DataSource : $($ds.Path)" -ForegroundColor Cyan
    $def = $srcProxy.GetDataSourceContents($ds.Path)
    $newDef = New-Object ($tgtProxy.GetType().Namespace + '.DataSourceDefinition')
    $newDef.Extension          = $def.Extension
    $newDef.ConnectString      = Convert-ConnectString $def.ConnectString
    $newDef.CredentialRetrieval= $def.CredentialRetrieval
    $newDef.WindowsCredentials = $def.WindowsCredentials
    $newDef.ImpersonateUser    = $def.ImpersonateUser
    $newDef.ImpersonateUserSpecified = $def.ImpersonateUserSpecified
    $newDef.UserName           = $def.UserName
    $newDef.Enabled            = $def.Enabled
    $newDef.EnabledSpecified   = $true

    # S'assurer que le dossier parent existe côté cible
    $parent = Split-Path $ds.Path -Parent
    if (-not $parent) { $parent = "/" }
    if ($parent -ne "/" -and -not ($tgtProxy.ListChildren("/", $true) | Where-Object { $_.Path -eq $parent })) {
        try { New-RsFolder -ReportServerUri $TargetUri -Path (Split-Path $parent -Parent) -FolderName (Split-Path $parent -Leaf) -ErrorAction Stop } catch {}
    }

    if ($PSCmdlet.ShouldProcess($ds.Path, "CreateDataSource on target")) {
        try {
            $existing = $tgtProxy.ListChildren($parent, $false) | Where-Object { $_.Name -eq $ds.Name -and $_.TypeName -eq 'DataSource' }
            if ($existing) {
                $tgtProxy.SetDataSourceContents($ds.Path, $newDef)
            } else {
                $null = $tgtProxy.CreateDataSource($ds.Name, $parent, $true, $newDef, $null)
            }
        } catch { Write-Warning "Création KO $($ds.Path) : $_" ; continue }
    }

    if ($def.CredentialRetrieval -eq 'Store') {
        $needsPassword += [PSCustomObject]@{ Path = $ds.Path; UserName = $def.UserName }
    }
}

if ($needsPassword.Count -gt 0) {
    $csv = Join-Path $OutputFolder "datasources-need-password.csv"
    $needsPassword | Export-Csv $csv -NoTypeInformation -Encoding utf8
    Write-Warning "$($needsPassword.Count) sources de données nécessitent une réinjection manuelle du mot de passe (voir $csv)."
}

Write-Host "Migration des sources de données terminée." -ForegroundColor Green
