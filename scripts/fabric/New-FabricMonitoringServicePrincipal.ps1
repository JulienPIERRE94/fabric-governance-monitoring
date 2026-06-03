# ============================================================
# New-FabricMonitoringServicePrincipal.ps1
# ------------------------------------------------------------
# Cree un Service Principal pour le monitoring Microsoft Fabric :
#   1. App Registration "SP-Fabric-Monitoring"
#   2. Service Principal associe
#   3. Client Secret (24 mois)
#   4. Ajout du SP au groupe "PBI-Audit-SPs" (deja autorise dans
#      le portail PBI Admin pour read-only admin APIs)
#
# IMPORTANT
#   Les Fabric/Power BI Admin APIs ne s'appuient PAS sur les
#   permissions Microsoft Graph mais sur les "tenant settings"
#   du portail Power BI. Le groupe "PBI-Audit-SPs" doit deja etre
#   autorise dans :
#     - Allow service principals to use Power BI APIs
#     - Allow service principals to use Fabric APIs
#     - Service principals can access read-only admin APIs
#
# Pre-requis :
#   - Azure CLI connecte (az login)
#   - Le groupe PBI-Audit-SPs existe (cree par
#     New-PowerBIAuditServicePrincipal.ps1)
# ============================================================

[CmdletBinding()]
param(
    [string]$AppName      = 'SP-Fabric-Monitoring',
    [string]$GroupName    = 'PBI-Audit-SPs',
    [int]   $SecretMonths = 24
)

$ErrorActionPreference = 'Stop'

function Run-Az {
    param([string]$Cmd)
    $out = Invoke-Expression "$Cmd 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "az command failed: $Cmd`n$out" }
    return $out
}

# --- Verif Azure CLI ---
$null = Run-Az "az account show --output json"
$tenantId   = (az account show --query tenantId -o tsv)
$signedUser = (az account show --query user.name -o tsv)
Write-Host "Tenant : $tenantId" -ForegroundColor Cyan
Write-Host "Compte : $signedUser" -ForegroundColor Cyan

# --- 1. App Registration ---
Write-Host ""
Write-Host "[1/4] App Registration '$AppName'..." -ForegroundColor Cyan
$existing = az ad app list --display-name $AppName --query "[0]" -o json | ConvertFrom-Json
if ($existing) {
    $appId    = $existing.appId
    Write-Host "  Existante. AppId = $appId" -ForegroundColor Gray
} else {
    $app = az ad app create --display-name $AppName --sign-in-audience AzureADMyOrg -o json | ConvertFrom-Json
    $appId = $app.appId
    Write-Host "  Creee. AppId = $appId" -ForegroundColor Green
}

# --- 2. Service Principal ---
Write-Host ""
Write-Host "[2/4] Service Principal..." -ForegroundColor Cyan
$sp = az ad sp list --filter "appId eq '$appId'" --query "[0]" -o json | ConvertFrom-Json
if (-not $sp) {
    $sp = az ad sp create --id $appId -o json | ConvertFrom-Json
    Write-Host "  Cree. SP ObjectId = $($sp.id)" -ForegroundColor Green
} else {
    Write-Host "  Existant. SP ObjectId = $($sp.id)" -ForegroundColor Gray
}
$spObjectId = $sp.id

# --- 3. Client Secret ---
Write-Host ""
Write-Host "[3/4] Client Secret (validite $SecretMonths mois)..." -ForegroundColor Cyan
$endDate = (Get-Date).AddMonths($SecretMonths).ToString('yyyy-MM-dd')
$secretJson = az ad app credential reset `
    --id $appId `
    --display-name "fabric-mon-secret-$(Get-Date -f yyyyMMdd)" `
    --end-date $endDate `
    --append `
    -o json | ConvertFrom-Json
$clientSecret = $secretJson.password
Write-Host "  Secret genere (expire $endDate)" -ForegroundColor Green

# --- 4. Ajout au groupe PBI-Audit-SPs ---
Write-Host ""
Write-Host "[4/4] Ajout au groupe '$GroupName'..." -ForegroundColor Cyan
$grp = az ad group list --display-name $GroupName --query "[0]" -o json | ConvertFrom-Json
if (-not $grp) {
    Write-Warning "Groupe '$GroupName' introuvable. Creez-le avec New-PowerBIAuditServicePrincipal.ps1, puis ajoutez le SP manuellement, ou relancez ce script."
} else {
    $isMember = az ad group member check --group $grp.id --member-id $spObjectId --query value -o tsv
    if ($isMember -ne 'true') {
        az ad group member add --group $grp.id --member-id $spObjectId | Out-Null
        Write-Host "  SP ajoute au groupe." -ForegroundColor Green
    } else {
        Write-Host "  SP deja membre." -ForegroundColor Gray
    }
}

# --- Sortie ---
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " SERVICE PRINCIPAL FABRIC MONITORING CREE" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "TenantId     : $tenantId"
Write-Host "ClientId     : $appId"
Write-Host "ClientSecret : $clientSecret"
Write-Host "App Name     : $AppName"
Write-Host "Expiration   : $endDate"
Write-Host ""
Write-Host ">>> VERIFIER COTE PORTAIL POWER BI ADMIN <<<" -ForegroundColor Yellow
Write-Host "Tenant settings -> activer (avec groupe '$GroupName') :"
Write-Host "  - Allow service principals to use Power BI APIs"
Write-Host "  - Allow service principals to use Fabric APIs"
Write-Host "  - Service principals can access read-only admin APIs"
Write-Host ""

# --- Sauvegarde credentials avec ACL restreinte ---
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$secretsDir = Join-Path $repoRoot 'secrets'
if (-not (Test-Path $secretsDir)) { New-Item -ItemType Directory -Path $secretsDir | Out-Null }
$credPath = Join-Path $secretsDir 'fabric-monitoring-sp.credentials.json'

@{
    TenantId     = $tenantId
    ClientId     = $appId
    ClientSecret = $clientSecret
    AppName      = $AppName
    Group        = $GroupName
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

# --- Test rapide d'acquisition de token Fabric ---
Write-Host "Test : acquisition d'un token Fabric..." -ForegroundColor Cyan
try {
    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $appId
        client_secret = $clientSecret
        scope         = 'https://api.fabric.microsoft.com/.default'
    }
    $tokenResp = Invoke-RestMethod -Method Post `
        -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
        -Body $body -ContentType 'application/x-www-form-urlencoded'
    if ($tokenResp.access_token) {
        Write-Host "  OK - token Fabric obtenu (expire dans $($tokenResp.expires_in)s)" -ForegroundColor Green
    }
} catch {
    Write-Warning "Acquisition de token echouee (propagation Azure AD : 30-60s) : $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Pour lancer l'extraction :" -ForegroundColor Cyan
Write-Host "  .\scripts\fabric\Export-FabricMetrics.ps1"
