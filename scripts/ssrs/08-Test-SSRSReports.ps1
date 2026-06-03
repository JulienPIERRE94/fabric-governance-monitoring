<#
.SYNOPSIS
    Tests d'exécution automatisés des rapports SSRS critiques.

.DESCRIPTION
    Étape 8 du guide. Pour chaque rapport listé en entrée, déclenche un rendu
    via l'URL Access (HTTP), mesure la durée, contrôle le code HTTP et la taille
    de la réponse. Génère un CSV de résultats.

.PARAMETER ReportServerUri
    URL Web Service SSRS (sans /ReportServer? ; le script construit l'URL Access).

.PARAMETER ReportList
    CSV à 1 colonne 'Path' (chemin SSRS du rapport, ex. /Finance/Reporting/Bilan).
    Colonnes optionnelles : 'Format' (PDF par défaut), 'Parameters' (k=v;k=v).

.PARAMETER OutputFolder
    Dossier où écrire les rendus + le CSV de résultats.

.PARAMETER Credential
    Optionnel.

.EXAMPLE
    .\08-Test-SSRSReports.ps1 -ReportServerUri "http://NEW-SSRS/ReportServer" `
        -ReportList ".\config\critical-reports.csv" -OutputFolder ".\out\test-runs"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]  [string] $ReportServerUri,
    [Parameter(Mandatory = $true)]  [string] $ReportList,
    [Parameter(Mandatory = $true)]  [string] $OutputFolder,
    [Parameter(Mandatory = $false)] [pscredential] $Credential,
    [Parameter(Mandatory = $false)] [int] $TimeoutSec = 300
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null }

# URL Access = remplace /ReportServer par /ReportServer?<path>&rs:Format=...
$rsBase = $ReportServerUri.TrimEnd('/')

$reports = Import-Csv $ReportList
$results = @()
foreach ($r in $reports) {
    $format = if ($r.PSObject.Properties.Name -contains 'Format' -and $r.Format) { $r.Format } else { 'PDF' }
    $extraParams = ""
    if ($r.PSObject.Properties.Name -contains 'Parameters' -and $r.Parameters) {
        foreach ($kv in ($r.Parameters -split ';')) {
            if ($kv -match '^(.+?)=(.+)$') { $extraParams += "&$($matches[1])=$([uri]::EscapeDataString($matches[2]))" }
        }
    }
    $url = "$rsBase`?$([uri]::EscapeUriString($r.Path))&rs:Format=$format&rs:Command=Render$extraParams"
    $safeName = ($r.Path.TrimStart('/').Replace('/','_')) + ".$format"
    $outFile = Join-Path $OutputFolder $safeName

    Write-Host "Test : $($r.Path) ($format)" -ForegroundColor Cyan
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $status = 'OK'; $err = $null; $size = 0; $http = 0
    try {
        $iwrParams = @{ Uri = $url; OutFile = $outFile; UseBasicParsing = $true; TimeoutSec = $TimeoutSec; UseDefaultCredentials = (-not $Credential) }
        if ($Credential) { $iwrParams.Credential = $Credential }
        $resp = Invoke-WebRequest @iwrParams -PassThru
        $http = [int]$resp.StatusCode
        $size = (Get-Item $outFile).Length
        if ($size -le 0) { $status = 'KO'; $err = 'Empty response' }
    } catch {
        $status = 'KO'; $err = $_.Exception.Message
        if ($_.Exception.Response) { $http = [int]$_.Exception.Response.StatusCode }
    }
    $sw.Stop()
    $results += [PSCustomObject]@{
        Path        = $r.Path
        Format      = $format
        HttpStatus  = $http
        Status      = $status
        DurationMs  = $sw.ElapsedMilliseconds
        SizeBytes   = $size
        OutputFile  = $outFile
        Error       = $err
    }
}

$csv = Join-Path $OutputFolder "test-results.csv"
$results | Export-Csv $csv -NoTypeInformation -Encoding utf8

$ok = ($results | Where-Object Status -eq 'OK').Count
$ko = ($results | Where-Object Status -eq 'KO').Count
Write-Host "Résultats : $ok OK / $ko KO -> $csv" -ForegroundColor Green
if ($ko -gt 0) { $results | Where-Object Status -eq 'KO' | Format-Table Path, HttpStatus, Error -AutoSize }
