# ============================================================
# Export-FabricMetrics.ps1
# ------------------------------------------------------------
# Extrait l'inventaire et l'activite Fabric / Power BI :
#   1. Workspaces (admin scope, tout le tenant)
#   2. Items (Lakehouse, Notebook, Pipeline, SemanticModel, Report,
#      Warehouse, Eventhouse, KQLDatabase, etc.) par workspace
#   3. Capacites (Fabric + PBI Premium)
#   4. Capacity refreshables (datasets refresh schedule)
#   5. Activity events (audit Fabric, derniers N jours)
#
# APIs utilisees :
#   - https://api.fabric.microsoft.com/v1/admin/...    (Fabric scope)
#   - https://api.powerbi.com/v1.0/myorg/admin/...     (PBI scope)
#
# Pre-requis tenant settings :
#   - Allow service principals to use Power BI APIs
#   - Allow service principals to use Fabric APIs
#   - Service principals can access read-only admin APIs
# ============================================================

[CmdletBinding()]
param(
    [string]$CredentialsPath,
    [int]   $ActivityDays = 7,
    [string]$OutputFolder,
    [int]   $ArchiveRetentionDays = 0   # 0 = pas de purge (archive infinie)
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $CredentialsPath) { $CredentialsPath = Join-Path $repoRoot 'secrets\fabric-monitoring-sp.credentials.json' }
if (-not $OutputFolder)    { $OutputFolder    = Join-Path $repoRoot 'data\fabric' }

if (-not (Test-Path $CredentialsPath)) {
    throw "Credentials non trouves : $CredentialsPath`nLancez d'abord .\scripts\fabric\New-FabricMonitoringServicePrincipal.ps1"
}
$cred = Get-Content $CredentialsPath -Raw | ConvertFrom-Json
Write-Host "Tenant   : $($cred.TenantId)" -ForegroundColor Cyan
Write-Host "ClientId : $($cred.ClientId)" -ForegroundColor Cyan

if (-not (Test-Path $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null }

# --- Token helper (par scope) ---
function Get-Token {
    param([string]$Scope)
    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $cred.ClientId
        client_secret = $cred.ClientSecret
        scope         = $Scope
    }
    (Invoke-RestMethod -Method Post `
        -Uri "https://login.microsoftonline.com/$($cred.TenantId)/oauth2/v2.0/token" `
        -Body $body -ContentType 'application/x-www-form-urlencoded').access_token
}

# --- Pagination helper (continuationToken Fabric / nextLink PBI) ---
function Invoke-AdminApi {
    param(
        [string]$Url,
        [string]$Token,
        [ValidateSet('continuationToken','nextLink','none')]
        [string]$Pagination = 'continuationToken'
    )
    $all = New-Object System.Collections.Generic.List[object]
    $next = $Url
    while ($next) {
        try {
            $resp = Invoke-RestMethod -Uri $next -Headers @{ Authorization = "Bearer $Token" }
        } catch {
            $code = $_.Exception.Response.StatusCode.value__
            throw "API $next -> HTTP $code : $($_.Exception.Message)"
        }
        # Fabric admin : { workspaces:[]/items:[]/capacities:[], continuationToken, continuationUri }
        # PBI legacy   : { value:[], '@odata.nextLink' }
        if ($resp.value)        { $all.AddRange([object[]]$resp.value) }
        elseif ($resp.workspaces)  { $all.AddRange([object[]]$resp.workspaces) }
        elseif ($resp.itemEntities){ $all.AddRange([object[]]$resp.itemEntities) }
        elseif ($resp.items)       { $all.AddRange([object[]]$resp.items) }
        elseif ($resp.capacities)  { $all.AddRange([object[]]$resp.capacities) }
        elseif ($resp -is [System.Array] -or $resp.GetType().Name -eq 'Object[]') { $all.AddRange([object[]]$resp) }
        switch ($Pagination) {
            'continuationToken' { $next = $resp.continuationUri }
            'nextLink'          { $next = $resp.'@odata.nextLink' }
            default             { $next = $null }
        }
    }
    return ,$all.ToArray()
}

Write-Host ""
Write-Host "Acquisition des tokens..." -ForegroundColor Cyan
$tokFabric = Get-Token 'https://api.fabric.microsoft.com/.default'
$tokPbi    = Get-Token 'https://analysis.windows.net/powerbi/api/.default'
Write-Host "  OK (Fabric + PBI)" -ForegroundColor Green

# --- 1. Workspaces (Fabric admin) ---
Write-Host ""
Write-Host "[1/5] Workspaces..." -ForegroundColor Cyan
$wsUrl = 'https://api.fabric.microsoft.com/v1/admin/workspaces?type=Workspace'
try {
    $workspaces = Invoke-AdminApi -Url $wsUrl -Token $tokFabric -Pagination continuationToken
    Write-Host "  $($workspaces.Count) workspaces" -ForegroundColor Green
} catch {
    Write-Warning "Echec workspaces : $($_.Exception.Message)"
    $workspaces = @()
}
$workspaces | Select-Object id,name,type,state,capacityId |
    Export-Csv (Join-Path $OutputFolder 'fabric_workspaces.csv') -NoTypeInformation -Encoding UTF8
$workspaces | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $OutputFolder 'fabric_workspaces.json') -Encoding UTF8

# --- 2. Items (Fabric admin) - tout le tenant via /v1/admin/items ---
Write-Host ""
Write-Host "[2/5] Items (tout le tenant)..." -ForegroundColor Cyan
$itemsUrl = 'https://api.fabric.microsoft.com/v1/admin/items'
$items = $null
# Retry avec backoff sur 429 (jusqu'a 5 min d'attente cumulee)
$waits = @(15, 30, 60, 120, 180)
foreach ($wait in $waits) {
    try {
        $items = Invoke-AdminApi -Url $itemsUrl -Token $tokFabric -Pagination continuationToken
        Write-Host "  $($items.Count) items" -ForegroundColor Green
        break
    } catch {
        if ($_.Exception.Message -match 'HTTP 429') {
            Write-Warning "  Rate limit (429), attente ${wait}s..."
            Start-Sleep -Seconds $wait
            $tokFabric = Get-Token 'https://api.fabric.microsoft.com/.default'  # refresh token
        } else {
            Write-Warning "Echec items : $($_.Exception.Message)"
            break
        }
    }
}
if ($null -eq $items) {
    Write-Warning "  Items non recuperes (rate limit persistant). Relancez plus tard ou utilisez l'API scanner async."
    $items = @()
}
$items | Select-Object id,type,name,workspaceId,state,description |
    Export-Csv (Join-Path $OutputFolder 'fabric_items.csv') -NoTypeInformation -Encoding UTF8

# --- 3. Capacites (PBI admin) ---
Write-Host ""
Write-Host "[3/5] Capacites..." -ForegroundColor Cyan
$capUrl = 'https://api.powerbi.com/v1.0/myorg/admin/capacities'
try {
    $caps = Invoke-AdminApi -Url $capUrl -Token $tokPbi -Pagination none
    Write-Host "  $($caps.Count) capacites" -ForegroundColor Green
} catch {
    Write-Warning "Echec capacites : $($_.Exception.Message)"
    $caps = @()
}
$caps | Select-Object id,displayName,sku,state,region,admins |
    ForEach-Object {
        [pscustomobject]@{
            id          = $_.id
            displayName = $_.displayName
            sku         = $_.sku
            state       = $_.state
            region      = $_.region
            admins      = ($_.admins -join ';')
        }
    } |
    Export-Csv (Join-Path $OutputFolder 'fabric_capacities.csv') -NoTypeInformation -Encoding UTF8
$caps | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $OutputFolder 'fabric_capacities.json') -Encoding UTF8

# --- 4. Refreshables (semantic models avec refresh planifie) ---
Write-Host ""
Write-Host "[4/5] Refreshables..." -ForegroundColor Cyan
$refUrl = 'https://api.powerbi.com/v1.0/myorg/admin/capacities/refreshables?$top=200&$expand=capacity,group'
try {
    $refreshables = Invoke-AdminApi -Url $refUrl -Token $tokPbi -Pagination nextLink
    Write-Host "  $($refreshables.Count) refreshables" -ForegroundColor Green
} catch {
    Write-Warning "Echec refreshables : $($_.Exception.Message)"
    $refreshables = @()
}
$refreshablesNorm = $refreshables | ForEach-Object {
    [pscustomobject]@{
        id                     = $_.id
        name                   = $_.name
        kind                   = $_.kind
        startTime              = $_.startTime
        endTime                = $_.endTime
        refreshCount            = $_.refreshCount
        refreshFailures        = $_.refreshFailures
        averageDuration        = $_.averageDuration
        medianDuration         = $_.medianDuration
        refreshesPerDay        = $_.refreshesPerDay
        capacityId             = $_.capacity.id
        capacityName           = $_.capacity.displayName
        workspaceId            = $_.group.id
        workspaceName          = $_.group.name
        configuredById         = $_.configuredBy -join ';'
    }
}
$refreshablesNorm | Export-Csv (Join-Path $OutputFolder 'fabric_refreshables.csv') -NoTypeInformation -Encoding UTF8

# --- 4b. Snapshot historique des refreshables ---
# L'API renvoie des compteurs cumules / agreges. Pour capturer l'evolution, on
# ajoute un snapshot horodate par refreshable a chaque execution (append simple).
Write-Host ""
Write-Host "[4b/5] Snapshot refreshables..." -ForegroundColor Cyan
$snapshotPath = Join-Path $OutputFolder 'fabric_refreshables_history.csv'
$snapshotTime = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
$snapshot = $refreshablesNorm | ForEach-Object {
    [pscustomobject]@{
        SnapshotTime           = $snapshotTime
        id                     = $_.id
        name                   = $_.name
        kind                   = $_.kind
        startTime              = $_.startTime
        endTime                = $_.endTime
        refreshCount           = $_.refreshCount
        refreshFailures        = $_.refreshFailures
        averageDuration        = $_.averageDuration
        medianDuration         = $_.medianDuration
        refreshesPerDay        = $_.refreshesPerDay
        capacityId             = $_.capacityId
        capacityName           = $_.capacityName
        workspaceId            = $_.workspaceId
        workspaceName          = $_.workspaceName
    }
}

if (Test-Path $snapshotPath) {
    # Append sans header
    $snapshot | ConvertTo-Csv -NoTypeInformation |
        Select-Object -Skip 1 |
        Add-Content -Path $snapshotPath -Encoding UTF8
    $existingCount = (Get-Content $snapshotPath | Measure-Object -Line).Lines - 1
    Write-Host "  +$($snapshot.Count) snapshots ajoutes (total ~$existingCount lignes)" -ForegroundColor Green
} else {
    $snapshot | Export-Csv -Path $snapshotPath -NoTypeInformation -Encoding UTF8
    Write-Host "  Creation : $($snapshot.Count) snapshots" -ForegroundColor Green
}

# Optionnel : retention sur l'historique des refreshables
if ($PSBoundParameters.ContainsKey('ArchiveRetentionDays') -and $ArchiveRetentionDays -gt 0) {
    $cutoff = (Get-Date).AddDays(-$ArchiveRetentionDays)
    $all = Import-Csv $snapshotPath
    $kept = $all | Where-Object {
        try { [datetime]$_.SnapshotTime -ge $cutoff } catch { $true }
    }
    if ($kept.Count -lt $all.Count) {
        $kept | Export-Csv $snapshotPath -NoTypeInformation -Encoding UTF8
        Write-Host "  Purge > $ArchiveRetentionDays j : $($all.Count - $kept.Count) supprimes, $($kept.Count) restants" -ForegroundColor Yellow
    }
}

# --- 5. Activity events (PBI/Fabric audit, par tranches d'1 jour) ---
Write-Host ""
Write-Host "[5/5] Activity events ($ActivityDays derniers jours)..." -ForegroundColor Cyan
$activities = New-Object System.Collections.Generic.List[object]
for ($d = $ActivityDays; $d -ge 1; $d--) {
    $day  = (Get-Date).AddDays(-$d).Date
    $from = $day.ToString('yyyy-MM-ddT00:00:00.000Z')
    $to   = $day.ToString('yyyy-MM-ddT23:59:59.999Z')
    $url  = "https://api.powerbi.com/v1.0/myorg/admin/activityevents?startDateTime='$from'&endDateTime='$to'"
    Write-Host "  $($day.ToString('yyyy-MM-dd')) ..." -NoNewline
    try {
        $resp = Invoke-RestMethod -Uri $url -Headers @{ Authorization = "Bearer $tokPbi" }
        $page = 0
        while ($resp) {
            if ($resp.activityEventEntities) {
                foreach ($e in $resp.activityEventEntities) { $activities.Add($e) }
            }
            $page++
            if ($resp.continuationUri) {
                $resp = Invoke-RestMethod -Uri $resp.continuationUri -Headers @{ Authorization = "Bearer $tokPbi" }
            } else { break }
        }
        Write-Host " $($activities.Count) cumul" -ForegroundColor Green
    } catch {
        Write-Host " ECHEC ($($_.Exception.Message))" -ForegroundColor Yellow
    }
}
Write-Host "  Total : $($activities.Count) evenements" -ForegroundColor Green

$activities | ForEach-Object {
    [pscustomobject]@{
        Id              = $_.Id
        CreationTime    = $_.CreationTime
        Operation       = $_.Operation
        UserId          = $_.UserId
        UserType        = $_.UserType
        UserAgent       = $_.UserAgent
        Activity        = $_.Activity
        ItemName        = $_.ItemName
        WorkspaceId     = $_.WorkspaceId
        WorkSpaceName   = $_.WorkSpaceName
        CapacityId      = $_.CapacityId
        ObjectId        = $_.ObjectId
        DatasetName     = $_.DatasetName
        ReportName      = $_.ReportName
        ClientIP        = $_.ClientIP
    }
} | Export-Csv (Join-Path $OutputFolder 'fabric_activities.csv') -NoTypeInformation -Encoding UTF8

# --- 5b. Archive cumulative des activites ---
# Strategy : merge sur Id (cle naturelle de l'event) -> dedup automatique
Write-Host ""
Write-Host "[5b/5] Archive cumulative des activites..." -ForegroundColor Cyan
$archivePath = Join-Path $OutputFolder 'fabric_activities_archive.csv'

$normalized = $activities | ForEach-Object {
    [pscustomobject]@{
        Id              = $_.Id
        CreationTime    = $_.CreationTime
        Operation       = $_.Operation
        UserId          = $_.UserId
        UserType        = $_.UserType
        UserAgent       = $_.UserAgent
        Activity        = $_.Activity
        ItemName        = $_.ItemName
        WorkspaceId     = $_.WorkspaceId
        WorkSpaceName   = $_.WorkSpaceName
        CapacityId      = $_.CapacityId
        ObjectId        = $_.ObjectId
        DatasetName     = $_.DatasetName
        ReportName      = $_.ReportName
        ClientIP        = $_.ClientIP
    }
}

if (Test-Path $archivePath) {
    $existing = Import-Csv $archivePath
    Write-Host "  Archive existante : $($existing.Count) lignes"
} else {
    $existing = @()
    Write-Host "  Pas d'archive existante (creation)"
}

# Index par Id pour dedup en O(N)
$index = @{}
foreach ($e in $existing) {
    if ($e.Id -and -not $index.ContainsKey($e.Id)) { $index[$e.Id] = $e }
}
$beforeMerge = $index.Count
$added = 0
foreach ($n in $normalized) {
    if ($n.Id -and -not $index.ContainsKey($n.Id)) {
        $index[$n.Id] = $n
        $added++
    }
}

$merged = $index.Values | Sort-Object CreationTime
$merged | Export-Csv $archivePath -NoTypeInformation -Encoding UTF8

Write-Host "  Avant merge : $beforeMerge lignes" -ForegroundColor DarkGray
Write-Host "  Nouveaux    : $added lignes ajoutees" -ForegroundColor Green
Write-Host "  Total       : $($merged.Count) lignes" -ForegroundColor Green

# Optionnel : retention (purge > N jours)
if ($PSBoundParameters.ContainsKey('ArchiveRetentionDays') -and $ArchiveRetentionDays -gt 0) {
    $cutoff = (Get-Date).AddDays(-$ArchiveRetentionDays)
    $kept = $merged | Where-Object {
        try { [datetime]$_.CreationTime -ge $cutoff } catch { $true }
    }
    if ($kept.Count -lt $merged.Count) {
        $kept | Export-Csv $archivePath -NoTypeInformation -Encoding UTF8
        Write-Host "  Purge > $ArchiveRetentionDays j : $($merged.Count - $kept.Count) lignes supprimees, $($kept.Count) restantes" -ForegroundColor Yellow
    }
}

# --- Synthese ---
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " EXPORT FABRIC TERMINE" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Dossier : $OutputFolder"
Get-ChildItem $OutputFolder | Sort-Object Name | ForEach-Object {
    Write-Host ("  {0,-35} {1,12:N0} octets" -f $_.Name, $_.Length)
}
