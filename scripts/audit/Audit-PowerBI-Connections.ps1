# ============================================================
# Script : Audit des creations de connexions Power BI Service
# ============================================================
# Utilise l'API Admin Power BI pour extraire les Activity Logs
# Authentification via Az.Accounts (Device Code par defaut)
# ou Service Principal (non-interactif).
# Appels REST directs -> independant des bugs WAM/MSAL du module
# MicrosoftPowerBIMgmt.
# ============================================================

[CmdletBinding()]
param(
    [ValidateSet('ServicePrincipal','DeviceCode','Interactive')]
    [string]$AuthMode = 'DeviceCode',

    [string]$TenantId     = $env:PBI_TENANT_ID,
    [string]$ClientId     = $env:PBI_CLIENT_ID,
    [string]$ClientSecret = $env:PBI_CLIENT_SECRET,

    [int]$DaysBack = 30
)

$ErrorActionPreference = 'Stop'
$PBIResource = 'https://analysis.windows.net/powerbi/api'
$PBIBaseUrl  = 'https://api.powerbi.com/v1.0/myorg/'

if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Write-Host "Installation du module Az.Accounts..." -ForegroundColor Yellow
    Install-Module -Name Az.Accounts -Scope CurrentUser -Force -AllowClobber
}
Import-Module Az.Accounts

try { Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null } catch {}

Write-Host "Connexion (mode: $AuthMode)..." -ForegroundColor Cyan

switch ($AuthMode) {
    'ServicePrincipal' {
        if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
            throw "Mode ServicePrincipal : TenantId, ClientId et ClientSecret requis (parametres ou env PBI_TENANT_ID / PBI_CLIENT_ID / PBI_CLIENT_SECRET)."
        }
        $secure = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
        $cred   = New-Object System.Management.Automation.PSCredential($ClientId, $secure)
        Connect-AzAccount -ServicePrincipal -Credential $cred -Tenant $TenantId | Out-Null
    }
    'DeviceCode' {
        Write-Host ""
        Write-Host ">>> Un code va s'afficher. Ouvrez https://microsoft.com/devicelogin et saisissez-le." -ForegroundColor Yellow
        Write-Host ""
        $params = @{ UseDeviceAuthentication = $true }
        if ($TenantId) { $params.Tenant = $TenantId }
        Connect-AzAccount @params | Out-Null
    }
    'Interactive' {
        $params = @{}
        if ($TenantId) { $params.Tenant = $TenantId }
        Connect-AzAccount @params | Out-Null
    }
}

$ctx = Get-AzContext
if (-not $ctx) { throw "Connexion echouee." }
Write-Host ("Connecte : {0} (tenant {1})" -f $ctx.Account.Id, $ctx.Tenant.Id) -ForegroundColor Green

function Get-PBIToken {
    $t = Get-AzAccessToken -ResourceUrl $PBIResource -WarningAction SilentlyContinue
    if ($t.Token -is [System.Security.SecureString]) {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($t.Token)
        try { return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
    return $t.Token
}

$script:Token           = Get-PBIToken
$script:Headers         = @{ Authorization = "Bearer $script:Token" }
$script:TokenAcquiredAt = Get-Date

$StartDate = (Get-Date).AddDays(-[Math]::Min($DaysBack,30)).ToString("yyyy-MM-dd")
$EndDate   = (Get-Date).ToString("yyyy-MM-dd")

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Recherche des activites de connexion" -ForegroundColor Cyan
Write-Host " Periode : $StartDate -> $EndDate" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$ConnectionActivities = @(
    "SetScheduledRefresh","GetDatasources","UpdateDatasources","BindToGateway",
    "SetAllConnections","CreateGateway","AddGatewayClusterDatasource",
    "UpdateGatewayClusterDatasource","DeleteGatewayClusterDatasource",
    "AddGatewayClusterUser","DeleteGatewayClusterUser",
    "SetGatewayClusterDatasourceCredentials","TakeOverDatasource",
    "CreateConnection","UpdateConnection","DeleteConnection",
    "ShareConnection","UnshareConnection",
    "CreateCloudDatasource","UpdateCloudDatasource","DeleteCloudDatasource"
)

$AllResults = New-Object System.Collections.Generic.List[object]

function Add-ActivityRows {
    param($Entities)
    foreach ($e in $Entities) {
        $AllResults.Add([pscustomobject]@{
            Date           = $e.CreationTime
            Utilisateur    = $e.UserId
            Activite       = $e.Activity
            Dataset        = $e.DatasetName
            DatasetId      = $e.DatasetId
            Workspace      = $e.WorkSpaceName
            WorkspaceId    = $e.WorkspaceId
            GatewayId      = $e.GatewayId
            DatasourceType = $e.DatasourceType
            ConnectionName = $e.ConnectionName
            IP             = $e.ClientIP
            UserAgent      = $e.UserAgent
        })
    }
}

function Invoke-PBI {
    param([string]$RelativeOrAbsoluteUrl)
    if (((Get-Date) - $script:TokenAcquiredAt).TotalMinutes -gt 45) {
        $script:Token           = Get-PBIToken
        $script:Headers         = @{ Authorization = "Bearer $script:Token" }
        $script:TokenAcquiredAt = Get-Date
    }
    $u = if ($RelativeOrAbsoluteUrl -match '^https?://') { $RelativeOrAbsoluteUrl } else { $PBIBaseUrl + $RelativeOrAbsoluteUrl }
    return Invoke-RestMethod -Uri $u -Headers $script:Headers -Method Get
}

$CurrentDate = [DateTime]::ParseExact($StartDate, "yyyy-MM-dd", $null)
$End         = [DateTime]::ParseExact($EndDate,   "yyyy-MM-dd", $null)

while ($CurrentDate -le $End) {
    $DateStr = $CurrentDate.ToString("yyyy-MM-dd")
    Write-Host "  Recuperation des logs du $DateStr..." -ForegroundColor Gray -NoNewline
    try {
        foreach ($activity in $ConnectionActivities) {
            $filter = [uri]::EscapeDataString("Activity eq '$activity'")
            $sd = "%27${DateStr}T00:00:00.000Z%27"
            $ed = "%27${DateStr}T23:59:59.999Z%27"
            $url = "admin/activityevents?startDateTime=$sd&endDateTime=$ed&`$filter=$filter"

            $result = Invoke-PBI $url
            if ($result.activityEventEntities.Count -gt 0) { Add-ActivityRows $result.activityEventEntities }

            while ($result.continuationUri) {
                Start-Sleep -Milliseconds 200
                $result = Invoke-PBI $result.continuationUri
                if ($result.activityEventEntities.Count -gt 0) { Add-ActivityRows $result.activityEventEntities }
            }
        }
        Write-Host " OK" -ForegroundColor Green
    }
    catch {
        $msg = $_.Exception.Message
        try {
            if ($_.Exception.Response) {
                $stream = $_.Exception.Response.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $body = $reader.ReadToEnd()
                    if ($body) { $msg = "$msg | $body" }
                }
            } elseif ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $msg = "$msg | $($_.ErrorDetails.Message)"
            }
        } catch {}
        Write-Host " Erreur: $msg" -ForegroundColor Red
    }
    $CurrentDate = $CurrentDate.AddDays(1)
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " RESULTATS : $($AllResults.Count) evenements trouves" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

if ($AllResults.Count -gt 0) {
    Write-Host "--- Resume par utilisateur ---" -ForegroundColor Yellow
    $AllResults | Group-Object Utilisateur |
        Select-Object @{N='Utilisateur';E={$_.Name}}, Count,
            @{N='Activites';E={($_.Group | Select-Object -ExpandProperty Activite -Unique) -join ", "}} |
        Sort-Object Count -Descending | Format-Table -AutoSize

    Write-Host "--- Resume par activite ---" -ForegroundColor Yellow
    $AllResults | Group-Object Activite |
        Select-Object @{N='Activite';E={$_.Name}}, Count,
            @{N='Utilisateurs';E={($_.Group | Select-Object -ExpandProperty Utilisateur -Unique) -join ", "}} |
        Sort-Object Count -Descending | Format-Table -AutoSize

    Write-Host "--- Detail des evenements ---" -ForegroundColor Yellow
    $AllResults | Sort-Object Date -Descending |
        Format-Table Date, Utilisateur, Activite, Dataset, Workspace, GatewayId, DatasourceType -AutoSize

    $CsvPath = Join-Path $PSScriptRoot "PowerBI_Connection_Audit_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $AllResults | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
    Write-Host ""
    Write-Host "Resultats exportes dans : $CsvPath" -ForegroundColor Green
}
else {
    Write-Host "Aucun evenement de connexion trouve sur cette periode." -ForegroundColor Yellow
    Write-Host "Verifiez que le compte/SP a les droits Admin Power BI." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " FIN DE L'AUDIT" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
