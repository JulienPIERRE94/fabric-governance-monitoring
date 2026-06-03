# ============================================================
# Register-FabricMonitoringSchedule.ps1
# ------------------------------------------------------------
# Cree une tache planifiee Windows pour executer
# Export-FabricMetrics.ps1 toutes les heures.
#
# Necessite : droits administrateur (lancement en mode elevated)
# ============================================================

[CmdletBinding()]
param(
    [string]$TaskName        = "CA-GIP-FabricMonitoring",
    [string]$TaskDescription = "Extraction horaire metriques Fabric (workspaces, items, capacites, refreshables, activity events)",
    [int]   $ActivityDays    = 1,
    [switch]$Unregister
)

$ErrorActionPreference = 'Stop'

# Verifier elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "Ce script doit etre execute en tant qu'administrateur. Relancez PowerShell en mode 'Run as Administrator'."
}

if ($Unregister) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Tache '$TaskName' supprimee." -ForegroundColor Yellow
    } else {
        Write-Host "Aucune tache '$TaskName' trouvee." -ForegroundColor DarkGray
    }
    return
}

$repoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $repoRoot 'scripts\fabric\Export-FabricMetrics.ps1'
$logFolder  = Join-Path $repoRoot 'logs'
$logFile    = Join-Path $logFolder 'fabric-monitoring.log'

if (-not (Test-Path $scriptPath)) { throw "Script introuvable : $scriptPath" }
if (-not (Test-Path $logFolder))  { New-Item -ItemType Directory -Path $logFolder -Force | Out-Null }

# Selectionner le PowerShell disponible (preference pour pwsh 7+, sinon Windows PowerShell 5.1)
$pwshExe = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwshExe) { $pwshExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" }

Write-Host "Tache         : $TaskName"
Write-Host "Script        : $scriptPath"
Write-Host "PowerShell    : $pwshExe"
Write-Host "Log           : $logFile"
Write-Host "ActivityDays  : $ActivityDays (par execution)"
Write-Host "Compte        : $env:USERDOMAIN\$env:USERNAME"
Write-Host ""

# Action : pwsh -Command (-File ne supporte pas la redirection *>>)
$cmd = "try { & `"$scriptPath`" -ActivityDays $ActivityDays *>&1 | Tee-Object -FilePath `"$logFile`" -Append } catch { `$_ | Out-File `"$logFile`" -Append; exit 1 }"
$argList = "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`""
$action  = New-ScheduledTaskAction -Execute $pwshExe -Argument $argList -WorkingDirectory $repoRoot
# Trigger : toutes les heures, demarrage immediat (apres registration), indefini
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) `
    -RepetitionInterval (New-TimeSpan -Hours 1) `
    -RepetitionDuration ([TimeSpan]::FromDays(3650))

# Settings : run only when user logged on / battery / etc.
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30) `
    -MultipleInstances IgnoreNew `
    -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 5)

# Principal : compte courant, niveau le plus eleve
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest

# Supprimer la tache si elle existe
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Write-Host "Tache existante : suppression..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Enregistrer
Register-ScheduledTask -TaskName $TaskName `
    -Description $TaskDescription `
    -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " TACHE PLANIFIEE CREEE" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
$task = Get-ScheduledTask -TaskName $TaskName
$info = Get-ScheduledTaskInfo -TaskName $TaskName
Write-Host "Nom            : $($task.TaskName)"
Write-Host "Etat           : $($task.State)"
Write-Host "Prochain run   : $($info.NextRunTime)"
Write-Host "Frequence      : toutes les heures"
Write-Host ""
Write-Host "Commandes utiles :"
Write-Host "  Lancer maintenant  : Start-ScheduledTask -TaskName '$TaskName'"
Write-Host "  Voir statut        : Get-ScheduledTaskInfo -TaskName '$TaskName'"
Write-Host "  Voir log           : Get-Content '$logFile' -Tail 50"
Write-Host "  Desactiver         : Disable-ScheduledTask -TaskName '$TaskName'"
Write-Host "  Supprimer          : .\scripts\fabric\Register-FabricMonitoringSchedule.ps1 -Unregister"
