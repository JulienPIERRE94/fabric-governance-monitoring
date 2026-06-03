<#
.SYNOPSIS
    Sauvegarde des bases ReportServer/ReportServerTempDB, de la clé de chiffrement
    et des fichiers de configuration SSRS.

.DESCRIPTION
    Étape 2 du guide. À exécuter sur le serveur SSRS source (ou un poste avec accès
    SQL + accès UNC au dossier de sauvegarde + accès aux fichiers de config locaux).

.PARAMETER SqlInstance
    Instance SQL hébergeant les bases ReportServer.

.PARAMETER BackupFolder
    Dossier UNC ou local où déposer les .bak, la clé .snk et les fichiers config.

.PARAMETER EncryptionKeyPassword
    Mot de passe (SecureString) pour protéger la clé exportée.

.PARAMETER SsrsServer
    Nom du serveur SSRS local pour rskeymgmt. Par défaut $env:COMPUTERNAME.

.PARAMETER SsrsInstance
    Nom de l'instance SSRS (par défaut MSSQLSERVER ou SSRS pour SSRS standalone).

.PARAMETER SsrsConfigPath
    Chemin local des fichiers de configuration SSRS à archiver.

.EXAMPLE
    $pwd = Read-Host -AsSecureString "Mot de passe clé"
    .\02-Backup-SSRS.ps1 -SqlInstance "OLD-SQL01" -BackupFolder "\\BACKUP\SSRS\20260505" -EncryptionKeyPassword $pwd
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]  [string] $SqlInstance,
    [Parameter(Mandatory = $true)]  [string] $BackupFolder,
    [Parameter(Mandatory = $true)]  [securestring] $EncryptionKeyPassword,
    [Parameter(Mandatory = $false)] [string] $SsrsServer = $env:COMPUTERNAME,
    [Parameter(Mandatory = $false)] [string] $SsrsInstance = "SSRS",
    [Parameter(Mandatory = $false)] [string] $SsrsConfigPath = "$env:ProgramFiles\Microsoft SQL Server Reporting Services\SSRS\ReportServer"
)

$ErrorActionPreference = 'Stop'
Import-Module SqlServer

if (-not (Test-Path $BackupFolder)) { New-Item -ItemType Directory -Path $BackupFolder -Force | Out-Null }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"

foreach ($db in @('ReportServer','ReportServerTempDB')) {
    $bak = Join-Path $BackupFolder "$db`_$stamp.bak"
    Write-Host "Sauvegarde $db -> $bak" -ForegroundColor Cyan
    $sql = @"
BACKUP DATABASE [$db]
TO DISK = N'$bak'
WITH COMPRESSION, CHECKSUM, INIT, FORMAT,
     NAME = N'$db Full Backup $stamp';
"@
    Invoke-Sqlcmd -ServerInstance $SqlInstance -Query $sql -QueryTimeout 0
}

# Export de la clé de chiffrement
$keyFile = Join-Path $BackupFolder "rskey_$stamp.snk"
$plain = [System.Net.NetworkCredential]::new('', $EncryptionKeyPassword).Password
Write-Host "Export de la clé de chiffrement -> $keyFile" -ForegroundColor Cyan
$rsKeyMgmt = Join-Path "$env:ProgramFiles\Microsoft SQL Server Reporting Services\Shared Tools" "rskeymgmt.exe"
if (-not (Test-Path $rsKeyMgmt)) {
    # Fallback : recherche dans le PATH
    $rsKeyMgmt = "rskeymgmt.exe"
}
& $rsKeyMgmt -e -f $keyFile -p $plain -i $SsrsInstance -s $SsrsServer
if ($LASTEXITCODE -ne 0) { throw "rskeymgmt -e a échoué (code $LASTEXITCODE)" }

# Copie des fichiers de configuration
$configBackup = Join-Path $BackupFolder "config_$stamp"
New-Item -ItemType Directory -Path $configBackup -Force | Out-Null
foreach ($f in @('rsreportserver.config','rssvrpolicy.config','rsmgrpolicy.config','RSReportServer.config')) {
    $src = Join-Path $SsrsConfigPath $f
    if (Test-Path $src) { Copy-Item $src $configBackup -Force }
}
$binSrc = Join-Path $SsrsConfigPath "bin"
if (Test-Path $binSrc) {
    Copy-Item $binSrc (Join-Path $configBackup "bin") -Recurse -Force
}

# Manifest
[PSCustomObject]@{
    BackupDate     = (Get-Date).ToString("s")
    SqlInstance    = $SqlInstance
    SsrsServer     = $SsrsServer
    SsrsInstance   = $SsrsInstance
    BackupFolder   = $BackupFolder
    EncryptionKey  = $keyFile
    ConfigBackup   = $configBackup
} | ConvertTo-Json | Out-File (Join-Path $BackupFolder "backup-manifest_$stamp.json") -Encoding utf8

Write-Host "Sauvegarde terminée." -ForegroundColor Green
