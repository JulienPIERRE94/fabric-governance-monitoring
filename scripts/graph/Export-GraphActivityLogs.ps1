# ============================================================
# Export-GraphActivityLogs.ps1
# ------------------------------------------------------------
# Collecte les Graph Activity Logs (appels API Microsoft Graph)
# via Azure Monitor / Log Analytics ou via l'API directe,
# et exporte les resultats en CSV dans .\data\graph\.
#
# Sources de donnees collectees :
#   1. Graph Activity Logs (via Log Analytics / Azure Monitor)
#      → Appels API : RequestUri, AppId, UserId, Method, Status, Duration
#   2. Audit Logs (directoryAuditLogs) via Graph API
#   3. Sign-in Logs (signIns) via Graph API
#
# Permissions Application requises :
#   AuditLog.Read.All, Reports.Read.All, Directory.Read.All
#
# Pour les Graph Activity Logs (feature preview) :
#   → Activer dans le portail Azure : Entra ID > Monitoring > Diagnostic settings
#   → Exporter vers Log Analytics Workspace
#   → Requete KQL : MicrosoftGraphActivityLogs
# ============================================================

[CmdletBinding()]
param(
    [string]$CredentialsPath,
    [int]   $DaysBack          = 7,
    [string]$OutputFolder,
    [string]$LogAnalyticsWorkspaceId,   # ID du workspace Log Analytics (optionnel)
    [switch]$UseLogAnalytics             # Si present, utilise Log Analytics pour GraphActivityLogs
)

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $CredentialsPath) { $CredentialsPath = Join-Path $repoRoot 'secrets\graph-monitoring-sp.credentials.json' }
if (-not $OutputFolder)    { $OutputFolder    = Join-Path $repoRoot 'data\graph' }

$ErrorActionPreference = 'Stop'

# ─── Chargement credentials ──────────────────────────────────────────────────
if (-not (Test-Path $CredentialsPath)) {
    throw "Credentials non trouves : $CredentialsPath`nLancez d'abord .\New-GraphMonitoringServicePrincipal.ps1"
}
$cred = Get-Content $CredentialsPath -Raw | ConvertFrom-Json
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Export-GraphActivityLogs.ps1" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Tenant   : $($cred.TenantId)" -ForegroundColor Cyan
Write-Host "ClientId : $($cred.ClientId)" -ForegroundColor Cyan
Write-Host "Periode  : $DaysBack derniers jours" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder | Out-Null
}

# ─── Token OAuth2 ────────────────────────────────────────────────────────────
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

function Get-MonitorToken {
    param($TenantId, $ClientId, $ClientSecret)
    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = 'https://api.loganalytics.io/.default'
    }
    (Invoke-RestMethod -Method Post `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -Body $body -ContentType 'application/x-www-form-urlencoded').access_token
}

# ─── Pagination Graph API ─────────────────────────────────────────────────────
function Get-GraphAll {
    param([string]$Url, [string]$Token)
    $all  = [System.Collections.Generic.List[object]]::new()
    $next = $Url
    while ($next) {
        $resp = Invoke-RestMethod -Uri $next -Headers @{
            Authorization    = "Bearer $Token"
            ConsistencyLevel = 'eventual'
        }
        if ($resp.value) { $all.AddRange([object[]]$resp.value) }
        $next = $resp.'@odata.nextLink'
    }
    return ,$all.ToArray()
}

# ─── Helpers ─────────────────────────────────────────────────────────────────
function Extract-Endpoint {
    param([string]$RequestUri)
    # Supprime les IDs GUID et remplace par {id}
    $path = ($RequestUri -replace 'https://graph\.microsoft\.com/v[\d.]+', '')
    $path = ($path -replace '\?.*$', '')                                         # enleve querystring
    $path = ($path -replace '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '{id}')
    $path = ($path -replace '\(period=''[^'']*''\)', '')                          # enleve (period='D7')
    return $path.TrimEnd('/')
}

function Get-EndpointCategory {
    param([string]$Uri)
    switch -Regex ($Uri) {
        '/users|/groups|/applications|/servicePrincipals|/directoryRoles' { return 'Identity' }
        '/messages|/sendMail|/mailFolders'                                 { return 'Mail' }
        '/calendars|/events|/contacts'                                     { return 'Calendar' }
        '/drive|/sites'                                                    { return 'Files' }
        '/teams|/chats|/channels'                                          { return 'Teams' }
        '/reports'                                                         { return 'Reports' }
        '/auditLogs|/security'                                             { return 'Security' }
        default                                                            { return 'Other' }
    }
}

# ─── 1. Graph Activity Logs (Log Analytics) ──────────────────────────────────
Write-Host "[1/4] Graph Activity Logs..." -ForegroundColor Cyan

$activityLogs = @()

if ($UseLogAnalytics -and $LogAnalyticsWorkspaceId) {
    Write-Host "  Mode Log Analytics (workspace: $LogAnalyticsWorkspaceId)" -ForegroundColor Gray
    try {
        $monToken = Get-MonitorToken $cred.TenantId $cred.ClientId $cred.ClientSecret
        $kql = @"
MicrosoftGraphActivityLogs
| where TimeGenerated >= ago($($DaysBack)d)
| project
    CallId           = RequestId,
    Timestamp        = TimeGenerated,
    AppId            = AppId,
    UserId           = UserId,
    RequestUri       = RequestUri,
    HttpMethod       = RequestMethod,
    StatusCode       = toint(ResponseStatusCode),
    DurationMs       = toint(DurationMs),
    IpAddress        = IPAddress,
    UserAgent        = UserAgent,
    ResourceTenantId = ResourceTenantId,
    OperationId      = OperationId
| order by Timestamp desc
"@
        $body = @{ query = $kql } | ConvertTo-Json
        $result = Invoke-RestMethod `
            -Uri "https://api.loganalytics.io/v1/workspaces/$LogAnalyticsWorkspaceId/query" `
            -Headers @{ Authorization = "Bearer $monToken"; 'Content-Type' = 'application/json' } `
            -Method Post -Body $body

        $cols = $result.tables[0].columns.name
        foreach ($row in $result.tables[0].rows) {
            $obj = [ordered]@{}
            for ($i = 0; $i -lt $cols.Count; $i++) { $obj[$cols[$i]] = $row[$i] }
            # Enrichissement endpoint
            $obj['Endpoint'] = Extract-Endpoint $obj['RequestUri']
            $activityLogs += [PSCustomObject]$obj
        }
        Write-Host "  $($activityLogs.Count) appels API collectes via Log Analytics" -ForegroundColor Green
    }
    catch {
        Write-Warning "Log Analytics non accessible : $($_.Exception.Message)"
        Write-Warning "Verifiez que MicrosoftGraphActivityLogs est active dans Diagnostic Settings."
    }
}
else {
    Write-Host "  Log Analytics non configure. Utilisation de l'API Graph directement." -ForegroundColor Yellow
    Write-Host "  Note : les Graph Activity Logs complets necessitent Log Analytics." -ForegroundColor Yellow
    Write-Host "  Pour activer : Entra ID > Monitoring > Diagnostic settings > Add setting" -ForegroundColor Yellow
    Write-Host "  Selectionnez 'MicrosoftGraphActivityLogs' et exportez vers Log Analytics." -ForegroundColor Yellow
}

# ─── 2. Audit Logs (directoryAuditLogs) ──────────────────────────────────────
Write-Host ""
Write-Host "[2/4] Audit Logs (directoryAuditLogs)..." -ForegroundColor Cyan
$token = Get-GraphToken $cred.TenantId $cred.ClientId $cred.ClientSecret
$since = (Get-Date).AddDays(-$DaysBack).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

try {
    $filter  = [Uri]::EscapeDataString("activityDateTime ge $since")
    $auditUrl = "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=$filter&`$top=500&`$orderby=activityDateTime desc"
    $audits  = Get-GraphAll -Url $auditUrl -Token $token
    Write-Host "  $($audits.Count) entrees d'audit" -ForegroundColor Green

    $audits | ForEach-Object {
        [PSCustomObject]@{
            id                = $_.id
            activityDateTime  = $_.activityDateTime
            activityDisplayName = $_.activityDisplayName
            category          = $_.category
            operationType     = $_.operationType
            result            = $_.result
            initiatedBy_user  = $_.initiatedBy.user.userPrincipalName
            initiatedBy_app   = $_.initiatedBy.app.displayName
            targetResources   = ($_.targetResources | ForEach-Object { $_.displayName }) -join '; '
        }
    } | Export-Csv (Join-Path $OutputFolder 'graph_audit_logs.csv') -NoTypeInformation -Encoding UTF8
    $audits | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $OutputFolder 'graph_audit_logs.json') -Encoding UTF8
}
catch {
    Write-Warning "Lecture audit logs echouee : $($_.Exception.Message)"
}

# ─── 3. Sign-in Logs ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[3/4] Sign-in Logs (auditLogs/signIns)..." -ForegroundColor Cyan
try {
    $filter2  = [Uri]::EscapeDataString("createdDateTime ge $since")
    $signInUrl = "https://graph.microsoft.com/v1.0/auditLogs/signIns?`$filter=$filter2&`$top=1000"
    $signIns  = Get-GraphAll -Url $signInUrl -Token $token
    Write-Host "  $($signIns.Count) sign-ins" -ForegroundColor Green

    $signIns | Select-Object id,createdDateTime,userPrincipalName,userId,appDisplayName,appId,ipAddress,clientAppUsed,isInteractive,status |
        Export-Csv (Join-Path $OutputFolder 'graph_signins.csv') -NoTypeInformation -Encoding UTF8
    $signIns | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $OutputFolder 'graph_signins.json') -Encoding UTF8
}
catch {
    Write-Warning "Lecture signIns echouee (licence Entra ID P1/P2 requise) : $($_.Exception.Message)"
}

# ─── 4. Dimension enrichment — Applications & Endpoints ──────────────────────
Write-Host ""
Write-Host "[4/4] Enrichissement dimensions..." -ForegroundColor Cyan

# Dim_Application depuis servicePrincipals
$spUrl = 'https://graph.microsoft.com/v1.0/servicePrincipals?$select=id,appId,displayName,servicePrincipalType,accountEnabled,appOwnerOrganizationId&$top=999'
try {
    $sps = Get-GraphAll -Url $spUrl -Token $token
    Write-Host "  $($sps.Count) service principals (Dim_Application)" -ForegroundColor Green
    $sps | Select-Object @{n='AppId';e={$_.appId}}, @{n='AppDisplayName';e={$_.displayName}},
        @{n='ServicePrincipalType';e={$_.servicePrincipalType}},
        @{n='AppOwnerTenantId';e={$_.appOwnerOrganizationId}},
        @{n='IsExternal';e={ $_.appOwnerOrganizationId -ne $cred.TenantId }} |
        Export-Csv (Join-Path $OutputFolder 'graph_dim_application.csv') -NoTypeInformation -Encoding UTF8
}
catch { Write-Warning "Lecture servicePrincipals echouee : $($_.Exception.Message)" }

# Dim_User depuis users
$usersUrl = 'https://graph.microsoft.com/v1.0/users?$select=id,displayName,userPrincipalName,mail,jobTitle,department,accountEnabled&$top=999'
try {
    $users = Get-GraphAll -Url $usersUrl -Token $token
    Write-Host "  $($users.Count) utilisateurs (Dim_User)" -ForegroundColor Green
    $users | Select-Object @{n='UserId';e={$_.id}}, @{n='UserPrincipalName';e={$_.userPrincipalName}},
        @{n='DisplayName';e={$_.displayName}}, @{n='Department';e={$_.department}},
        @{n='JobTitle';e={$_.jobTitle}}, @{n='AccountEnabled';e={$_.accountEnabled}} |
        Export-Csv (Join-Path $OutputFolder 'graph_dim_user.csv') -NoTypeInformation -Encoding UTF8
}
catch { Write-Warning "Lecture users echouee : $($_.Exception.Message)" }

# Export Activity Logs CSV
if ($activityLogs.Count -gt 0) {
    $activityLogs | Export-Csv (Join-Path $OutputFolder 'graph_activity_logs.csv') -NoTypeInformation -Encoding UTF8
    $activityLogs | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutputFolder 'graph_activity_logs.json') -Encoding UTF8
    Write-Host "  Activity logs exportes : $($activityLogs.Count) lignes" -ForegroundColor Green
}
else {
    Write-Host "  Aucun activity log collecte. Le fichier sample reste inchange." -ForegroundColor Yellow
}

# ─── Bilan ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " EXPORT TERMINE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Dossier : $OutputFolder"
Get-ChildItem $OutputFolder -Filter '*.csv' | ForEach-Object {
    $rows = (Import-Csv $_.FullName | Measure-Object).Count
    Write-Host ("  {0,-45} {1,6} lignes" -f $_.Name, $rows)
}

Write-Host ""
Write-Host "Prochaines etapes :" -ForegroundColor Yellow
Write-Host "  1. Ouvrir PowerBI_Graph_Monitoring.pbip dans Power BI Desktop" -ForegroundColor White
Write-Host "  2. Rafraichir le modele (les CSV seront charges automatiquement)" -ForegroundColor White
Write-Host "  3. Verifier que DataFolder pointe vers : $OutputFolder" -ForegroundColor White
