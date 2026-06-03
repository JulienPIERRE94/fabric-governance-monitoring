<#
.SYNOPSIS
    Restauration des bases ReportServer/ReportServerTempDB et réimport de la clé
    de chiffrement sur la nouvelle instance SSRS.

.DESCRIPTION
    Étape 3 du guide. À exécuter APRÈS l'installation et la configuration initiale
    de SSRS sur le nouveau serveur (Report Server Configuration Manager pointant
    vers la nouvelle base SQL).

.PARAMETER SqlInstance
    Instance SQL cible.

.PARAMETER BackupFolder
    Dossier contenant les .bak et la clé .snk.

.PARAMETER ReportServerBak
    Optionnel. Nom du fichier .bak ReportServer (défaut : dernier trouvé).

.PARAMETER TempDbBak
    Optionnel. Nom du fichier .bak ReportServerTempDB (défaut : dernier trouvé).

.PARAMETER EncryptionKeyFile
    Fichier .snk exporté à l'étape 2.

.PARAMETER EncryptionKeyPassword
    Mot de passe (SecureString) de la clé.

.PARAMETER SsrsServer
    Nom du nouveau serveur SSRS.

.PARAMETER SsrsInstance
    Nom de l'instance SSRS (par défaut SSRS).

.PARAMETER DataPath
    Optionnel. Chemin physique pour les .mdf si le serveur cible a une arbo différente.

.PARAMETER LogPath
    Optionnel. Chemin physique pour les .ldf.

.EXAMPLE
    $pwd = Read-Host -AsSecureString
    .\03-Restore-SSRS.ps1 -SqlInstance "NEW-SQL01" -BackupFolder "\\BACKUP\SSRS\20260505" `
        -EncryptionKeyFile "\\BACKUP\SSRS\20260505\rskey_20260505_120000.snk" `
        -EncryptionKeyPassword $pwd -SsrsServer "NEW-SSRS"
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]  [string] $SqlInstance,
    [Parameter(Mandatory = $true)]  [string] $BackupFolder,
    [Parameter(Mandatory = $false)] [string] $ReportServerBak,
    [Parameter(Mandatory = $false)] [string] $TempDbBak,
    [Parameter(Mandatory = $true)]  [string] $EncryptionKeyFile,
    [Parameter(Mandatory = $true)]  [securestring] $EncryptionKeyPassword,
    [Parameter(Mandatory = $true)]  [string] $SsrsServer,
    [Parameter(Mandatory = $false)] [string] $SsrsInstance = "SSRS",
    [Parameter(Mandatory = $false)] [string] $DataPath,
    [Parameter(Mandatory = $false)] [string] $LogPath
)

$ErrorActionPreference = 'Stop'
Import-Module SqlServer

function Resolve-LatestBak {
    param([string]$Folder, [string]$Pattern)
    Get-ChildItem -Path $Folder -Filter $Pattern | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

if (-not $ReportServerBak) {
    $ReportServerBak = (Resolve-LatestBak $BackupFolder "ReportServer_*.bak").FullName
}
if (-not $TempDbBak) {
    $TempDbBak = (Resolve-LatestBak $BackupFolder "ReportServerTempDB_*.bak").FullName
}

Write-Host "ReportServer .bak : $ReportServerBak" -ForegroundColor Cyan
Write-Host "TempDb       .bak : $TempDbBak"      -ForegroundColor Cyan

function Restore-SsrsDb {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$DbName, [string]$BakFile)

    $relocate = ""
    if ($DataPath -and $LogPath) {
        $files = Invoke-Sqlcmd -ServerInstance $SqlInstance -Query "RESTORE FILELISTONLY FROM DISK = N'$BakFile';"
        $moves = foreach ($f in $files) {
            $target = if ($f.Type -eq 'L') { Join-Path $LogPath ([IO.Path]::GetFileName($f.PhysicalName)) }
                      else                  { Join-Path $DataPath ([IO.Path]::GetFileName($f.PhysicalName)) }
            "  MOVE N'$($f.LogicalName)' TO N'$target'"
        }
        $relocate = ",`n" + ($moves -join ",`n")
    }

    $sql = @"
USE [master];
ALTER DATABASE [$DbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
RESTORE DATABASE [$DbName]
FROM DISK = N'$BakFile'
WITH REPLACE, RECOVERY$relocate;
ALTER DATABASE [$DbName] SET MULTI_USER;
"@
    if ($PSCmdlet.ShouldProcess($DbName, "RESTORE DATABASE")) {
        Write-Host "Restauration $DbName ..." -ForegroundColor Yellow
        try {
            Invoke-Sqlcmd -ServerInstance $SqlInstance -Query $sql -QueryTimeout 0
        } catch {
            # Si la base n'existe pas encore, retenter sans single_user
            Write-Warning "Tentative sans SINGLE_USER : $_"
            $sql2 = "RESTORE DATABASE [$DbName] FROM DISK = N'$BakFile' WITH REPLACE, RECOVERY$relocate;"
            Invoke-Sqlcmd -ServerInstance $SqlInstance -Query $sql2 -QueryTimeout 0
        }
    }
}

Restore-SsrsDb -DbName 'ReportServer'        -BakFile $ReportServerBak
Restore-SsrsDb -DbName 'ReportServerTempDB'  -BakFile $TempDbBak

# Réimport de la clé de chiffrement
$plain = [System.Net.NetworkCredential]::new('', $EncryptionKeyPassword).Password
$rsKeyMgmt = Join-Path "$env:ProgramFiles\Microsoft SQL Server Reporting Services\Shared Tools" "rskeymgmt.exe"
if (-not (Test-Path $rsKeyMgmt)) { $rsKeyMgmt = "rskeymgmt.exe" }

if ($PSCmdlet.ShouldProcess($SsrsServer, "rskeymgmt -a (apply key)")) {
    Write-Host "Application de la clé de chiffrement sur $SsrsServer ($SsrsInstance)..." -ForegroundColor Yellow
    & $rsKeyMgmt -a -f $EncryptionKeyFile -p $plain -i $SsrsInstance -s $SsrsServer
    if ($LASTEXITCODE -ne 0) { throw "rskeymgmt -a a échoué (code $LASTEXITCODE)" }
}

Write-Host "Restauration terminée. Redémarrer le service SSRS pour prise en compte." -ForegroundColor Green
Write-Host "  Restart-Service -Name 'SQLServerReportingServices'" -ForegroundColor DarkGray
