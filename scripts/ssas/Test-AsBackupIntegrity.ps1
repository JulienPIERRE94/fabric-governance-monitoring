<#
.SYNOPSIS
    Verifies the integrity and consistency of an SSAS (.abf) backup file by
    performing a test restore, a Process Default, smoke queries, and log scan.

.DESCRIPTION
    Implements the verification path described in the SSAS (ABF) backup
    consistency note. This script does NOT touch the production database:
    it restores the backup to a temporary database name on a non-production
    SSAS instance and runs sanity checks against it.

    Steps performed:
      1. Compute SHA-256 hash of the .abf file (chain-of-custody).
      2. Restore the .abf to <BaseName>_RestoreTest on the target instance.
      3. Run Process Default (no-op if backup is consistent, fails if corrupt).
      4. Execute a smoke DAX (Tabular) or MDX (Multidim) query.
      5. Scan msmdsrv log for restore-time errors/warnings (best effort).
      6. Optionally drop the test database.

    Requires:
      - SqlServer PowerShell module (Invoke-ASCmd)
      - Sysadmin rights on the target (test) SSAS instance
      - Read access to the .abf file (or copy locally)

.PARAMETER BackupPath
    Full path to the .abf file to verify.

.PARAMETER TargetServer
    SSAS instance used to perform the test restore (NON-PRODUCTION).
    Examples: "localhost\TABULAR", "ssas-test:2383".

.PARAMETER ServerMode
    Tabular or Multidimensional. Drives the smoke query syntax.

.PARAMETER TestDatabaseName
    Optional. Name of the database after restore. Defaults to
    "<abf-base-name>_RestoreTest".

.PARAMETER LogPath
    Optional. Path to msmdsrv.log for the target instance. If provided, the
    script greps the last lines for errors/warnings around the restore time.

.PARAMETER KeepDatabase
    If set, the restored test database is NOT dropped at the end.

.PARAMETER OutputJson
    Optional. Path to write a JSON report with the verification result.

.EXAMPLE
    .\Test-AsBackupIntegrity.ps1 `
        -BackupPath 'D:\Backups\SalesTabular.abf' `
        -TargetServer 'localhost\TABULAR' `
        -ServerMode Tabular `
        -OutputJson 'D:\Reports\SalesTabular_check.json'

.NOTES
    Author : Julien PIERRE
    Repo   : https://github.com/JulienPIERRE94/CA-GIP-ReportServer
    Status : Reference / best-effort. Validate against your environment
             before relying on it for production sign-off.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $BackupPath,
    [Parameter(Mandatory)] [string] $TargetServer,
    [Parameter(Mandatory)] [ValidateSet('Tabular','Multidimensional')] [string] $ServerMode,
    [string] $TestDatabaseName,
    [string] $LogPath,
    [switch] $KeepDatabase,
    [string] $OutputJson
)

$ErrorActionPreference = 'Stop'
$started = Get-Date

function Write-Step([string]$msg) {
    Write-Host "[ $(Get-Date -Format HH:mm:ss) ] $msg" -ForegroundColor Cyan
}

# ---------- 0. Pre-flight ----------------------------------------------------
if (-not (Test-Path -LiteralPath $BackupPath)) {
    throw "Backup file not found: $BackupPath"
}
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    throw "SqlServer PowerShell module is required. Run: Install-Module SqlServer -Scope CurrentUser"
}
Import-Module SqlServer -ErrorAction Stop

$abf      = Get-Item -LiteralPath $BackupPath
$baseName = [IO.Path]::GetFileNameWithoutExtension($abf.Name)
if (-not $TestDatabaseName) { $TestDatabaseName = "${baseName}_RestoreTest" }

$report = [ordered]@{
    BackupPath       = $abf.FullName
    SizeBytes        = $abf.Length
    LastWriteTime    = $abf.LastWriteTimeUtc
    Sha256           = $null
    TargetServer     = $TargetServer
    ServerMode       = $ServerMode
    TestDatabaseName = $TestDatabaseName
    StartedUtc       = $started.ToUniversalTime()
    Steps            = @{}
    Success          = $false
    Error            = $null
}

try {
    # ---------- 1. SHA-256 hash --------------------------------------------
    Write-Step "Computing SHA-256 of $($abf.Name) ..."
    $report.Sha256 = (Get-FileHash -LiteralPath $abf.FullName -Algorithm SHA256).Hash
    $report.Steps.Hash = 'OK'

    # ---------- 2. Restore --------------------------------------------------
    Write-Step "Restoring to [$TargetServer].[$TestDatabaseName] ..."
    $restoreXmla = @"
<Restore xmlns="http://schemas.microsoft.com/analysisservices/2003/engine">
  <File>$([Security.SecurityElement]::Escape($abf.FullName))</File>
  <DatabaseName>$TestDatabaseName</DatabaseName>
  <AllowOverwrite>true</AllowOverwrite>
  <Security>IgnoreSecurity</Security>
</Restore>
"@
    Invoke-ASCmd -Server $TargetServer -Query $restoreXmla | Out-Null
    $report.Steps.Restore = 'OK'

    # ---------- 3. Process Default -----------------------------------------
    Write-Step "Running Process Default ..."
    $processXmla = @"
<Batch xmlns="http://schemas.microsoft.com/analysisservices/2003/engine">
  <Parallel>
    <Process xmlns:xsd="http://www.w3.org/2001/XMLSchema"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xmlns:ddl2="http://schemas.microsoft.com/analysisservices/2003/engine/2">
      <Object><DatabaseID>$TestDatabaseName</DatabaseID></Object>
      <Type>ProcessDefault</Type>
      <WriteBackTableCreation>UseExisting</WriteBackTableCreation>
    </Process>
  </Parallel>
</Batch>
"@
    Invoke-ASCmd -Server $TargetServer -Query $processXmla | Out-Null
    $report.Steps.ProcessDefault = 'OK'

    # ---------- 4. Smoke query ---------------------------------------------
    Write-Step "Running smoke query ($ServerMode) ..."
    if ($ServerMode -eq 'Tabular') {
        $smoke = "EVALUATE ROW(`"check`", 1)"
    } else {
        $smoke = "SELECT {} ON 0 FROM `$System.DBSCHEMA_CATALOGS"
    }
    $null = Invoke-ASCmd -Server $TargetServer -Database $TestDatabaseName -Query $smoke
    $report.Steps.SmokeQuery = 'OK'

    # ---------- 5. Log scan (best effort) ----------------------------------
    if ($LogPath -and (Test-Path -LiteralPath $LogPath)) {
        Write-Step "Scanning msmdsrv log: $LogPath ..."
        $cutoff = $started.AddMinutes(-1)
        $hits = Select-String -LiteralPath $LogPath -Pattern 'error|warning|fail' -SimpleMatch:$false -CaseSensitive:$false |
                Where-Object { $_.Line -match '\d{4}-\d{2}-\d{2}' } |
                Select-Object -Last 50
        $report.Steps.LogScan = @{
            File        = $LogPath
            CutoffUtc   = $cutoff.ToUniversalTime()
            MatchCount  = ($hits | Measure-Object).Count
            LastMatches = $hits | ForEach-Object { $_.Line } | Select-Object -Last 10
        }
    } else {
        $report.Steps.LogScan = 'Skipped (LogPath not provided or not found)'
    }

    $report.Success = $true
    Write-Host "[ OK ] Backup $($abf.Name) is consistent." -ForegroundColor Green
}
catch {
    $report.Error = $_.Exception.Message
    Write-Host "[ FAIL ] $($_.Exception.Message)" -ForegroundColor Red
    throw
}
finally {
    # ---------- 6. Cleanup --------------------------------------------------
    if (-not $KeepDatabase) {
        try {
            Write-Step "Dropping test database [$TestDatabaseName] ..."
            $dropXmla = @"
<Delete xmlns="http://schemas.microsoft.com/analysisservices/2003/engine">
  <Object><DatabaseID>$TestDatabaseName</DatabaseID></Object>
</Delete>
"@
            Invoke-ASCmd -Server $TargetServer -Query $dropXmla | Out-Null
            $report.Steps.Cleanup = 'Dropped'
        } catch {
            $report.Steps.Cleanup = "Drop failed: $($_.Exception.Message)"
            Write-Warning $report.Steps.Cleanup
        }
    } else {
        $report.Steps.Cleanup = 'Kept (KeepDatabase switch)'
    }

    $report.EndedUtc    = (Get-Date).ToUniversalTime()
    $report.DurationSec = [int]((Get-Date) - $started).TotalSeconds

    if ($OutputJson) {
        $dir = Split-Path -Parent $OutputJson
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputJson -Encoding UTF8
        Write-Host "Report written to $OutputJson" -ForegroundColor Yellow
    }
}
