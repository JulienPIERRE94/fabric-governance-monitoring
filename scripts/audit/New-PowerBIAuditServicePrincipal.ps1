# ============================================================
# New-PowerBIAuditServicePrincipal.ps1
# ------------------------------------------------------------
# Cree un Service Principal pour l'audit Power BI :
#   1. App Registration "PBI-Audit-Connections"
#   2. Client Secret (24 mois)
#   3. Service Principal associe
#   4. Groupe de securite "PBI-Audit-SPs" contenant le SP
#
# ETAPE MANUELLE A FAIRE APRES (UI Power BI Admin Portal) :
#   Settings > Admin portal > Tenant settings :
#     - Activer "Allow service principals to use Power BI APIs"
#       -> Specific security groups -> Ajouter "PBI-Audit-SPs"
#     - Activer "Service principals can access read-only admin APIs"
#       -> Specific security groups -> Ajouter "PBI-Audit-SPs"
# ============================================================

[CmdletBinding()]
param(
    [string]$AppName     = 'PBI-Audit-Connections',
    [string]$GroupName   = 'PBI-Audit-SPs',
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
$tenantId = (az account show --query tenantId -o tsv)
Write-Host "Tenant : $tenantId" -ForegroundColor Cyan

# --- 1. App Registration (idempotent) ---
Write-Host ""
Write-Host "[1/4] App Registration '$AppName'..." -ForegroundColor Cyan
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
    --display-name "audit-secret-$(Get-Date -f yyyyMMdd)" `
    --end-date $endDate `
    --append `
    -o json | ConvertFrom-Json
$clientSecret = $secretJson.password
Write-Host "  Secret genere (expire $endDate)" -ForegroundColor Green

# --- 4. Groupe de securite (idempotent) ---
Write-Host ""
Write-Host "[4/4] Groupe de securite '$GroupName'..." -ForegroundColor Cyan
$grp = az ad group list --display-name $GroupName --query "[0]" -o json | ConvertFrom-Json
if (-not $grp) {
    $grp = az ad group create --display-name $GroupName --mail-nickname ($GroupName -replace '[^a-zA-Z0-9]','') -o json | ConvertFrom-Json
    Write-Host "  Cree. ObjectId = $($grp.id)" -ForegroundColor Green
} else {
    Write-Host "  Existant. ObjectId = $($grp.id)" -ForegroundColor Gray
}

# Ajout du SP au groupe (idempotent)
$isMember = az ad group member check --group $grp.id --member-id $spObjectId --query value -o tsv
if ($isMember -ne 'true') {
    az ad group member add --group $grp.id --member-id $spObjectId | Out-Null
    Write-Host "  SP ajoute au groupe." -ForegroundColor Green
} else {
    Write-Host "  SP deja membre." -ForegroundColor Gray
}

# --- Sortie ---
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " SERVICE PRINCIPAL CREE" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "TenantId     : $tenantId"
Write-Host "ClientId     : $appId"
Write-Host "ClientSecret : $clientSecret"
Write-Host "Group        : $GroupName ($($grp.id))"
Write-Host ""
Write-Host ">>> ETAPE MANUELLE OBLIGATOIRE <<<" -ForegroundColor Yellow
Write-Host "1. https://app.powerbi.com -> Settings (roue) -> Admin portal -> Tenant settings"
Write-Host "2. Activer ces 2 reglages et y ajouter le groupe '$GroupName' :"
Write-Host "   - Allow service principals to use Power BI APIs"
Write-Host "   - Service principals can access read-only admin APIs"
Write-Host "3. Sauvegarder. Propagation : 15 min max."
Write-Host ""

# Sauvegarde dans un fichier credentials securise (lecture admin uniquement)
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$secretsDir = Join-Path $repoRoot 'secrets'
if (-not (Test-Path $secretsDir)) { New-Item -ItemType Directory -Path $secretsDir | Out-Null }
$credPath = Join-Path $secretsDir 'pbi-audit-sp.credentials.json'
@{
    TenantId     = $tenantId
    ClientId     = $appId
    ClientSecret = $clientSecret
    Group        = $GroupName
    GroupId      = $grp.id
    Created      = (Get-Date).ToString('s')
    SecretExpiry = $endDate
} | ConvertTo-Json | Set-Content -Path $credPath -Encoding UTF8

# ACL : restreindre a Administrators + utilisateur courant
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
Write-Host "Pour lancer l'audit ensuite :" -ForegroundColor Cyan
Write-Host "  `$c = Get-Content '$credPath' | ConvertFrom-Json"
Write-Host "  `$env:PBI_TENANT_ID = `$c.TenantId"
Write-Host "  `$env:PBI_CLIENT_ID = `$c.ClientId"
Write-Host "  `$env:PBI_CLIENT_SECRET = `$c.ClientSecret"
Write-Host "  .\Audit-PowerBI-Connections.ps1 -AuthMode ServicePrincipal"
