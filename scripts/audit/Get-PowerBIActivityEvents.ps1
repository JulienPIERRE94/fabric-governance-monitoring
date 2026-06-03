<#
.SYNOPSIS
    Collecte les évènements d'activité Power BI / Fabric via l'API Admin GetActivityEvents.

.DESCRIPTION
    Boucle sur les N derniers jours (max 30) et récupère tous les évènements via l'API
    admin/activityevents en utilisant un Service Principal Entra ID.
    Sortie : CSV consolidé exploitable dans Power BI Desktop.

.PARAMETER TenantId
    Tenant ID Entra ID.

.PARAMETER ClientId
    Application (Client) ID du Service Principal autorisé sur l'API admin Power BI.

.PARAMETER ClientSecret
    Secret du Service Principal (préférer Key Vault en production).

.PARAMETER DaysBack
    Nombre de jours à collecter (1 à 30).

.PARAMETER OutputCsv
    Chemin du CSV de sortie.

.EXAMPLE
    .\Get-PowerBIActivityEvents.ps1 -TenantId 'xxx' -ClientId 'yyy' -ClientSecret 'zzz' -DaysBack 7
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [Parameter(Mandatory = $true)]
    [string]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 30)]
    [int]$DaysBack = 7,

    [Parameter(Mandatory = $false)]
    [string]$OutputCsv = ".\PowerBI_ActivityEvents.csv"
)

# 1. Authentification (OAuth2 client_credentials)
$tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
$body = @{
    grant_type    = 'client_credentials'
    client_id     = $ClientId
    client_secret = $ClientSecret
    scope         = 'https://analysis.windows.net/powerbi/api/.default'
}

Write-Host "Authentification Service Principal..." -ForegroundColor Cyan
$tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $body -ContentType 'application/x-www-form-urlencoded'
$accessToken = $tokenResponse.access_token

if (-not $accessToken) {
    throw "Échec d'authentification. Vérifiez TenantId / ClientId / ClientSecret."
}

$headers = @{ Authorization = "Bearer $accessToken" }
$baseUrl = 'https://api.powerbi.com/v1.0/myorg/admin/activityevents'

$allEvents = New-Object System.Collections.Generic.List[Object]

# 2. Boucle jour par jour
for ($i = 1; $i -le $DaysBack; $i++) {
    $day = (Get-Date).AddDays(-$i).Date
    $startDt = $day.ToString('yyyy-MM-ddT00:00:00.000Z')
    $endDt   = $day.ToString('yyyy-MM-ddT23:59:59.999Z')

    Write-Host "Collecte des évènements du $($day.ToString('yyyy-MM-dd')) ..." -ForegroundColor Yellow

    $url = "$baseUrl`?startDateTime='$startDt'&endDateTime='$endDt'"
    $continuationUri = $null
    $pageCount = 0

    do {
        try {
            if ($continuationUri) {
                $response = Invoke-RestMethod -Method Get -Uri $continuationUri -Headers $headers
            } else {
                $response = Invoke-RestMethod -Method Get -Uri $url -Headers $headers
            }
        }
        catch {
            if ($_.Exception.Response.StatusCode.value__ -eq 429) {
                $retry = 60
                Write-Warning "429 Throttling. Pause $retry s..."
                Start-Sleep -Seconds $retry
                continue
            }
            throw
        }

        if ($response.activityEventEntities) {
            foreach ($e in $response.activityEventEntities) {
                $allEvents.Add($e) | Out-Null
            }
        }

        $continuationUri = $response.continuationUri
        $pageCount++
        Start-Sleep -Milliseconds 200
    } while ($continuationUri)

    Write-Host "  → $pageCount page(s) — Total cumulé : $($allEvents.Count)"
}

# 3. Normalisation et export
Write-Host "`nExport CSV..." -ForegroundColor Cyan

$flat = $allEvents | ForEach-Object {
    [PSCustomObject]@{
        Id                  = $_.Id
        CreationTime        = $_.CreationTime
        Operation           = $_.Operation
        UserId              = $_.UserId
        UserType            = $_.UserType
        UserKey             = $_.UserKey
        Activity            = $_.Activity
        ItemName            = $_.ItemName
        WorkSpaceName       = $_.WorkSpaceName
        WorkspaceId         = $_.WorkspaceId
        ObjectId            = $_.ObjectId
        DatasetName         = $_.DatasetName
        DatasetId           = $_.DatasetId
        ReportName          = $_.ReportName
        ReportId            = $_.ReportId
        ReportType          = $_.ReportType
        CapacityId          = $_.CapacityId
        CapacityName        = $_.CapacityName
        ClientIP            = $_.ClientIP
        UserAgent           = $_.UserAgent
        IsSuccess           = $_.IsSuccess
        RequestId           = $_.RequestId
        ActivityId          = $_.ActivityId
        DistributionMethod  = $_.DistributionMethod
        ConsumptionMethod   = $_.ConsumptionMethod
    }
}

$flat | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8 -Delimiter ';'

Write-Host "`n--- RÉSUMÉ ---" -ForegroundColor Green
Write-Host "Évènements collectés : $($allEvents.Count)"
Write-Host "Période : $DaysBack jours"
Write-Host "Fichier : $OutputCsv"

Write-Host "`nTop 10 opérations :" -ForegroundColor Green
$allEvents | Group-Object Operation |
    Sort-Object Count -Descending |
    Select-Object -First 10 Count, Name |
    Format-Table -AutoSize

Write-Host "`nTop 10 utilisateurs :" -ForegroundColor Green
$allEvents | Group-Object UserId |
    Sort-Object Count -Descending |
    Select-Object -First 10 Count, Name |
    Format-Table -AutoSize
