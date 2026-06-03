# ============================================================
# New-GraphMonitoringServicePrincipal.ps1
# ------------------------------------------------------------
# Cree un Service Principal pour l'export des metriques
# Microsoft Graph API vers Power BI :
#   1. App Registration "SP-PowerBI-GraphMonitoring"
#   2. Service Principal associe
#   3. Client Secret (24 mois)
#   4. Permissions Microsoft Graph (Application) :
#        - User.Read.All
#        - AuditLog.Read.All
#        - Directory.Read.All
#        - Application.Read.All
#   5. Admin consent (grant) pour le tenant
#
# Pre-requis :
#   - Azure CLI connecte (az login) avec un compte
#     "Global Administrator" ou "Privileged Role Administrator"
#     (necessaire pour 'az ad app permission admin-consent')
#   - Sortie 443 vers login.microsoftonline.com et graph.microsoft.com
# ============================================================

[CmdletBinding()]
param(
    [string]$AppName      = 'SP-PowerBI-GraphMonitoring',
    [int]   $SecretMonths = 24,
    [switch]$SkipAdminConsent
)

$ErrorActionPreference = 'Stop'

# Microsoft Graph resource AppId (constante Azure AD)
$GraphAppId = '00000003-0000-0000-c000-000000000000'

# Permissions Application (role IDs) - cf. https://learn.microsoft.com/graph/permissions-reference
$GraphPermissions = @(
    @{ Name = 'User.Read.All';        Id = 'df021288-bdef-4463-88db-98f22de89214' }
    @{ Name = 'AuditLog.Read.All';    Id = 'b0afded3-3588-46d8-8b3d-9842eff778da' }
    @{ Name = 'Directory.Read.All';   Id = '7ab1d382-f21e-4acd-a863-ba3e13f7da61' }
    @{ Name = 'Application.Read.All'; Id = '9a5d68dd-52b0-4cc2-bd40-abcf44ac3a30' }
)

function Run-Az {
    param([string]$Cmd)
    $out = Invoke-Expression "$Cmd 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "az command failed: $Cmd`n$out" }
    return $out
}

# --- Verif Azure CLI ---
$null = Run-Az "az account show --output json"
$tenantId    = (az account show --query tenantId -o tsv)
$signedUser  = (az account show --query user.name -o tsv)
Write-Host "Tenant : $tenantId" -ForegroundColor Cyan
Write-Host "Compte : $signedUser" -ForegroundColor Cyan

# --- 1. App Registration (idempotent) ---
Write-Host ""
Write-Host "[1/5] App Registration '$AppName'..." -ForegroundColor Cyan
$existing = az ad app list --display-name $AppName --query "[0]" -o json | ConvertFrom-Json
if ($existing) {
    $appId    = $existing.appId
    $appObjId = $existing.id
    Write-Host "  Existante. AppId = $appId" -ForegroundColor Gray
} else {
    $app = az ad app create --display-name $AppName --sign-in-audience AzureADMyOrg -o json | ConvertFrom-Json
    $appId    = $app.appId
    $appObjId = $app.id
    Write-Host "  Creee. AppId = $appId" -ForegroundColor Green
}

# --- 2. Service Principal (idempotent) ---
Write-Host ""
Write-Host "[2/5] Service Principal..." -ForegroundColor Cyan
$sp = az ad sp list --filter "appId eq '$appId'" --query "[0]" -o json | ConvertFrom-Json
if (-not $sp) {
    $sp = az ad sp create --id $appId -o json | ConvertFrom-Json
    Write-Host "  Cree. SP ObjectId = $($sp.id)" -ForegroundColor Green
} else {
    Write-Host "  Existant. SP ObjectId = $($sp.id)" -ForegroundColor Gray
}
$spObjectId = $sp.id

# --- 3. Permissions Microsoft Graph ---
Write-Host ""
Write-Host "[3/5] Ajout des permissions Microsoft Graph (Application)..." -ForegroundColor Cyan
foreach ($p in $GraphPermissions) {
    Write-Host "  - $($p.Name)"
    az ad app permission add `
        --id $appId `
        --api $GraphAppId `
        --api-permissions "$($p.Id)=Role" `
        --only-show-errors 2>$null | Out-Null
}
Write-Host "  Permissions declarees." -ForegroundColor Green

# --- 4. Client Secret ---
Write-Host ""
Write-Host "[4/5] Client Secret (validite $SecretMonths mois)..." -ForegroundColor Cyan
$endDate = (Get-Date).AddMonths($SecretMonths).ToString('yyyy-MM-dd')
$secretJson = az ad app credential reset `
    --id $appId `
    --display-name "graph-secret-$(Get-Date -f yyyyMMdd)" `
    --end-date $endDate `
    --append `
    -o json | ConvertFrom-Json
$clientSecret = $secretJson.password
Write-Host "  Secret genere (expire $endDate)" -ForegroundColor Green

# --- 5. Admin consent ---
Write-Host ""
Write-Host "[5/5] Admin consent (grant tenant)..." -ForegroundColor Cyan
if ($SkipAdminConsent) {
    Write-Host "  Ignore (-SkipAdminConsent). A faire manuellement dans le portail." -ForegroundColor Yellow
} else {
    try {
        az ad app permission admin-consent --id $appId 2>$null
        if ($LASTEXITCODE -ne 0) { throw "admin-consent a echoue" }
        Write-Host "  Consent accorde pour le tenant." -ForegroundColor Green
    } catch {
        Write-Warning "Admin consent automatique impossible : $($_.Exception.Message)"
        Write-Host "  -> A faire dans Entra ID > App registrations > $AppName > API permissions > 'Grant admin consent'" -ForegroundColor Yellow
    }
}

# --- Sortie ---
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " SERVICE PRINCIPAL GRAPH MONITORING CREE" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "TenantId     : $tenantId"
Write-Host "ClientId     : $appId"
Write-Host "ClientSecret : $clientSecret"
Write-Host "App Name     : $AppName"
Write-Host "Expiration   : $endDate"
Write-Host ""
Write-Host "Permissions Graph (Application) :" -ForegroundColor Cyan
$GraphPermissions | ForEach-Object { Write-Host "  - $($_.Name)" }
Write-Host ""

# --- Sauvegarde credentials avec ACL restreinte ---
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$secretsDir = Join-Path $repoRoot 'secrets'
if (-not (Test-Path $secretsDir)) { New-Item -ItemType Directory -Path $secretsDir | Out-Null }
$credPath = Join-Path $secretsDir 'graph-monitoring-sp.credentials.json'
@{
    TenantId     = $tenantId
    ClientId     = $appId
    ClientSecret = $clientSecret
    AppName      = $AppName
    Permissions  = ($GraphPermissions | ForEach-Object { $_.Name })
    Created      = (Get-Date).ToString('s')
    SecretExpiry = $endDate
} | ConvertTo-Json | Set-Content -Path $credPath -Encoding UTF8

try {
    $acl = Get-Acl $credPath
    $acl.SetAccessRuleProtection($true, $false)
    $rules = @(
        New-Object System.Security.AccessControl.FileSystemAccessRule('BUILTIN\Administrators','FullControl','Allow'),
        New-Object System.Security.AccessControl.FileSystemAccessRule("$env:USERDOMAIN\$env:USERNAME",'FullControl','Allow'),
        New-Object System.Security.AccessControl.FileSystemAccessRule('NT AUTHORITY\SYSTEM','FullControl','Allow')
    )
    foreach ($r in $rules) { $acl.AddAccessRule($r) }
    Set-Acl -Path $credPath -AclObject $acl
} catch { Write-Warning "ACL non appliquee : $($_.Exception.Message)" }

Write-Host "Credentials sauvegardes (ACL restreinte) : $credPath" -ForegroundColor Green
Write-Host ""

# --- Test rapide d'acquisition de token ---
Write-Host "Test : acquisition d'un token Graph..." -ForegroundColor Cyan
try {
    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $appId
        client_secret = $clientSecret
        scope         = 'https://graph.microsoft.com/.default'
    }
    $tokenResp = Invoke-RestMethod -Method Post `
        -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
        -Body $body -ContentType 'application/x-www-form-urlencoded'
    if ($tokenResp.access_token) {
        Write-Host "  OK - token obtenu (expire dans $($tokenResp.expires_in)s)" -ForegroundColor Green

        # Test d'appel Graph (peut echouer si consent non encore propage : ~1-2 min)
        try {
            $hdr = @{ Authorization = "Bearer $($tokenResp.access_token)" }
            $u = Invoke-RestMethod -Uri 'https://graph.microsoft.com/v1.0/users?$top=1' -Headers $hdr
            Write-Host "  OK - appel /users reussi ($($u.value.Count) utilisateur lu)" -ForegroundColor Green
        } catch {
            Write-Warning "Appel /users a echoue (propagation du consent : reessayer dans 1-2 min). $($_.Exception.Message)"
        }
    }
} catch {
    Write-Warning "Acquisition de token echouee : $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Pour utiliser dans Power BI (Mode_Operatoire_Graph_API.md) :" -ForegroundColor Cyan
Write-Host "  TenantId     = $tenantId"
Write-Host "  ClientId     = $appId"
Write-Host "  ClientSecret = (voir $credPath)"
Write-Host ""
Write-Host "Pour utiliser en PowerShell :" -ForegroundColor Cyan
Write-Host "  `$c = Get-Content '$credPath' | ConvertFrom-Json"
Write-Host "  `$body = @{ grant_type='client_credentials'; client_id=`$c.ClientId; client_secret=`$c.ClientSecret; scope='https://graph.microsoft.com/.default' }"
Write-Host "  `$tok  = (Invoke-RestMethod -Method Post -Uri \"https://login.microsoftonline.com/`$(`$c.TenantId)/oauth2/v2.0/token\" -Body `$body).access_token"
Write-Host "  Invoke-RestMethod -Uri 'https://graph.microsoft.com/v1.0/users' -Headers @{ Authorization = \"Bearer `$tok\" }"
