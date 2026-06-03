# ============================================================
# Export-GraphMetrics.ps1
# ------------------------------------------------------------
# Extrait les metriques Microsoft Graph en utilisant le SP cree
# par New-GraphMonitoringServicePrincipal.ps1 et exporte les
# resultats en CSV (et JSON brut) dans .\data\.
#
# Donnees extraites :
#   - users (id, displayName, UPN, mail, jobTitle, dept, enabled)
#   - signIns derniers N jours (par defaut 7)
#   - servicePrincipals
#
# Permissions Application requises (deja accordees par le SP) :
#   User.Read.All, AuditLog.Read.All, Directory.Read.All,
#   Application.Read.All
# ============================================================

[CmdletBinding()]
param(
    [string]$CredentialsPath,
    [int]   $SignInsDays  = 7,
    [string]$OutputFolder
)

# Resolution des chemins par defaut depuis la racine du repo
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $CredentialsPath) { $CredentialsPath = Join-Path $repoRoot 'secrets\graph-monitoring-sp.credentials.json' }
if (-not $OutputFolder)    { $OutputFolder    = Join-Path $repoRoot 'data\graph' }

$ErrorActionPreference = 'Stop'

# --- Chargement credentials ---
if (-not (Test-Path $CredentialsPath)) {
    throw "Credentials non trouves : $CredentialsPath`nLancez d'abord .\New-GraphMonitoringServicePrincipal.ps1"
}
$cred = Get-Content $CredentialsPath -Raw | ConvertFrom-Json
Write-Host "Tenant   : $($cred.TenantId)" -ForegroundColor Cyan
Write-Host "ClientId : $($cred.ClientId)" -ForegroundColor Cyan

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder | Out-Null
}

# --- Acquisition token ---
function Get-GraphToken {
    param($TenantId, $ClientId, $ClientSecret)
    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = 'https://graph.microsoft.com/.default'
    }
    (Invoke-RestMethod -Method Post `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -Body $body -ContentType 'application/x-www-form-urlencoded').access_token
}

# --- Recuperation paginee ---
function Get-GraphAll {
    param([string]$Url, [string]$Token)
    $all = New-Object System.Collections.Generic.List[object]
    $next = $Url
    while ($next) {
        $resp = Invoke-RestMethod -Uri $next -Headers @{
            Authorization      = "Bearer $Token"
            ConsistencyLevel   = 'eventual'
        }
        if ($resp.value) { $all.AddRange([object[]]$resp.value) }
        $next = $resp.'@odata.nextLink'
    }
    return ,$all.ToArray()
}

Write-Host ""
Write-Host "Acquisition du token..." -ForegroundColor Cyan
$token = Get-GraphToken $cred.TenantId $cred.ClientId $cred.ClientSecret
Write-Host "  OK" -ForegroundColor Green

# --- 1. Users ---
Write-Host ""
Write-Host "[1/3] Extraction users..." -ForegroundColor Cyan
$usersUrl = 'https://graph.microsoft.com/v1.0/users?$select=id,displayName,userPrincipalName,mail,jobTitle,department,accountEnabled&$top=999'
$users = Get-GraphAll -Url $usersUrl -Token $token
Write-Host "  $($users.Count) utilisateurs" -ForegroundColor Green
$users | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutputFolder 'graph_users.json') -Encoding UTF8
$users | Select-Object id,displayName,userPrincipalName,mail,jobTitle,department,accountEnabled |
    Export-Csv (Join-Path $OutputFolder 'graph_users.csv') -NoTypeInformation -Encoding UTF8

# --- 2. SignIns ---
Write-Host ""
Write-Host "[2/3] Extraction signIns ($SignInsDays derniers jours)..." -ForegroundColor Cyan
$since = (Get-Date).AddDays(-$SignInsDays).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$filter = [Uri]::EscapeDataString("createdDateTime ge $since")
$signInsUrl = "https://graph.microsoft.com/v1.0/auditLogs/signIns?`$filter=$filter&`$top=1000"
try {
    $signIns = Get-GraphAll -Url $signInsUrl -Token $token
    Write-Host "  $($signIns.Count) sign-ins" -ForegroundColor Green
} catch {
    Write-Warning "Lecture signIns echouee (licence Entra ID P1/P2 requise) : $($_.Exception.Message)"
    $signIns = @()
}
$signIns | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $OutputFolder 'graph_signins.json') -Encoding UTF8
$signIns | Select-Object id,createdDateTime,userPrincipalName,userId,appDisplayName,appId,ipAddress,clientAppUsed,isInteractive |
    Export-Csv (Join-Path $OutputFolder 'graph_signins.csv') -NoTypeInformation -Encoding UTF8

# --- 3. Service Principals ---
Write-Host ""
Write-Host "[3/3] Extraction servicePrincipals..." -ForegroundColor Cyan
$spUrl = 'https://graph.microsoft.com/v1.0/servicePrincipals?$select=id,appId,displayName,servicePrincipalType,accountEnabled,appOwnerOrganizationId&$top=999'
$sps = Get-GraphAll -Url $spUrl -Token $token
Write-Host "  $($sps.Count) service principals" -ForegroundColor Green
$sps | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutputFolder 'graph_serviceprincipals.json') -Encoding UTF8
$sps | Select-Object id,appId,displayName,servicePrincipalType,accountEnabled,appOwnerOrganizationId |
    Export-Csv (Join-Path $OutputFolder 'graph_serviceprincipals.csv') -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " EXPORT TERMINE" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Dossier : $OutputFolder"
Get-ChildItem $OutputFolder | ForEach-Object {
    Write-Host ("  {0,-40} {1,10:N0} octets" -f $_.Name, $_.Length)
}
