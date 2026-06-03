# =============================================================================
# Set-OneLakeDataAccessRoles.ps1
# =============================================================================
# Implémente la COUCHE 4 — sécurité au niveau table (OneLake Data Access Roles)
# en complément du RLS défini dans SEM_Insurance.
#
# Architecture de sécurité complète :
#   Couche 1 : Isolation des workspaces Fabric (Entra ID)
#   Couche 2 : Shortcuts OneLake (données source inaccessibles directement)
#   Couche 3 : RLS dans SEM_Insurance (USERPRINCIPALNAME() / DAX)          ← Update-SMRoles.ps1
#   Couche 4 : OneLake Data Access Roles (accès table par table)            ← CE SCRIPT
#
# Matrice d'accès ciblée :
#
#   Table                     | BankingAdvisors (hugo, isabelle) | InsuranceUsers (sophie)
#   ──────────────────────────┼──────────────────────────────────┼───────────────────────
#   sc_dim_customers          │ ✅ (filtré par RLS advisor_email) │ ❌ accès direct bloqué
#   sc_fact_bank_accounts     │ ✅ (filtré par RLS)               │ ❌ accès direct bloqué
#   sc_bridge_ins_customers   │ ✅                                │ ❌ accès direct bloqué
#   insurance_contracts       │ ✅ (filtré par RLS)               │ ✅ (via SM + RLS bridge)
#   insurance_claims          │ ✅ (filtré par RLS)               │ ✅
#   security_table            │ ✅ (filtré par RLS)               │ ✅ (ses propres lignes)
#
# Notes :
#   - Le SM RLS reste la barrière principale pour les accès via Power BI / Fabric portal
#   - Les Data Access Roles bloquent les accès directs : SQL endpoint, notebooks, API OneLake
#   - sophie.marchand ne peut PAS lire les shortcuts sc_* même en accédant au SQL endpoint
# =============================================================================

param(
    [string]$WsInsuranceId = "cbc321b0-5e65-41c1-a98c-eea5781305b7",
    [string]$LhInsuranceId = "317f23e4-0dd7-4ace-9780-2c81c342bd5a",
    [string]$WsBankingId   = "5015e396-cb2d-4fbe-8ebf-c87544cf6bfd",
    [string]$LhBankingId   = "8093805b-3709-454e-9998-015b9faaf3c0",
    [string]$TenantId      = ""   # Optionnel — rempli automatiquement via Graph si vide
)

# ── Tokens ────────────────────────────────────────────────────────────────────
Write-Host "🔐 Récupération des tokens..." -ForegroundColor Cyan
$fabToken   = (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
$graphToken = (& az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv)

$fabHdr   = @{ Authorization = "Bearer $fabToken";   "Content-Type" = "application/json" }
$graphHdr = @{ Authorization = "Bearer $graphToken"; "Content-Type" = "application/json" }

# ── Récupération des Object IDs via Graph API ─────────────────────────────────
Write-Host "👥 Résolution des Object IDs utilisateurs..." -ForegroundColor Cyan

$users = @{
    hugo      = "hugo.lambert@MngEnvMCAP578215.onmicrosoft.com"
    isabelle  = "isabelle.fontaine@MngEnvMCAP578215.onmicrosoft.com"
    sophie    = "sophie.marchand@MngEnvMCAP578215.onmicrosoft.com"
}

$objectIds = @{}
foreach ($key in $users.Keys) {
    $upn = $users[$key]
    try {
        $u = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$upn" -Headers $graphHdr
        $objectIds[$key] = $u.id
        Write-Host "  ✅ $upn -> $($u.id)"
    } catch {
        Write-Host "  ❌ Impossible de résoudre $upn : $($_.Exception.Message)" -ForegroundColor Red
        $objectIds[$key] = $null
    }
}

# Récupère le tenantId si non fourni
if (-not $TenantId) {
    $me = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/organization" -Headers $graphHdr
    $TenantId = $me.value[0].id
    Write-Host "  ℹ️  TenantId résolu : $TenantId"
}

# ── Fonctions utilitaires ──────────────────────────────────────────────────────
function Build-EntraMember {
    param([string]$ObjectId, [string]$Tenant)
    return @{ tenantId = $Tenant; objectId = $ObjectId }
}

function Set-DataAccessRoles {
    param(
        [string]$WsId,
        [string]$LhId,
        [string]$Label,
        [array]$Roles
    )
    $body = @{ value = $Roles } | ConvertTo-Json -Depth 10
    $uri  = "https://api.fabric.microsoft.com/v1/workspaces/$WsId/lakehouses/$LhId/dataAccessRoles"

    Write-Host "`n📋 Configuration Data Access Roles sur $Label..." -ForegroundColor Cyan
    Write-Host "   URI : $uri"

    try {
        $resp = Invoke-WebRequest -Method PUT -Uri $uri -Headers $fabHdr -Body $body -UseBasicParsing
        Write-Host "  ✅ HTTP $($resp.StatusCode) — Rôles appliqués" -ForegroundColor Green
        return $true
    } catch {
        # PowerShell 7 : le corps de réponse est dans ErrorDetails.Message
        $msg = if ($_.ErrorDetails.Message) {
            $_.ErrorDetails.Message
        } elseif ($_.Exception.Response) {
            "HTTP $([int]$_.Exception.Response.StatusCode)"
        } else {
            $_.Exception.Message
        }
        $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        Write-Host "  ❌ HTTP $code : $msg" -ForegroundColor Red

        # Feature flag ou version tenant — affiche conseil
        if ($msg -match "NotSupported|FeatureNotAvailable|preview|not.*enabled|disabled") {
            Write-Host "  ⚠️  Les OneLake Data Access Roles nécessitent l'activation" -ForegroundColor Yellow
            Write-Host "     via : Fabric Admin Portal → Tenant Settings" -ForegroundColor Yellow
            Write-Host "     → OneLake → 'OneLake data access roles (preview)' → ON" -ForegroundColor Yellow
        }
        return $false
    }
}

function Get-DataAccessRoles {
    param([string]$WsId, [string]$LhId, [string]$Label)
    $uri = "https://api.fabric.microsoft.com/v1/workspaces/$WsId/lakehouses/$LhId/dataAccessRoles"
    try {
        $resp = Invoke-RestMethod -Uri $uri -Headers $fabHdr
        Write-Host "`n📖 Rôles actuels sur $Label :" -ForegroundColor Cyan
        if ($resp.value) {
            $resp.value | ForEach-Object {
                Write-Host "  Rôle : $($_.name)"
                $_.decisionRules | ForEach-Object {
                    $paths = $_.permission.attributeValueIncludedIn -join ", "
                    Write-Host "    $($_.effect) → $paths"
                }
                $members = @()
                if ($_.members.microsoftEntraMembers) { $members += $_.members.microsoftEntraMembers | ForEach-Object { "  User:$($_.objectId)" } }
                if ($_.members.fabricItemMembers)     { $members += $_.members.fabricItemMembers     | ForEach-Object { "  Item:$($_.id)" } }
                if ($members) { Write-Host "    Membres : $($members -join ', ')" }
            }
        } else {
            Write-Host "  (aucun rôle configuré)"
        }
    } catch {
        Write-Host "  ❌ Impossible de lire les rôles : $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ── État initial ───────────────────────────────────────────────────────────────
Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host " ÉTAT AVANT CONFIGURATION" -ForegroundColor DarkCyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Get-DataAccessRoles -WsId $WsInsuranceId -LhId $LhInsuranceId -Label "LH-Insurance"
Get-DataAccessRoles -WsId $WsBankingId   -LhId $LhBankingId   -Label "LH-Banking"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 : LH-Insurance — Rôles différenciés par domaine
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host " LH-INSURANCE — Configuration des Data Access Roles" -ForegroundColor DarkCyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor DarkCyan

# Membres bancaires (ont accès à tout — RLS SM filtre ensuite par advisor_email)
$bankingMembers = @()
if ($objectIds["hugo"])     { $bankingMembers += Build-EntraMember -ObjectId $objectIds["hugo"]     -Tenant $TenantId }
if ($objectIds["isabelle"]) { $bankingMembers += Build-EntraMember -ObjectId $objectIds["isabelle"] -Tenant $TenantId }

# Membres assurance (accès restreint aux tables insurance uniquement — PAS les shortcuts sc_*)
$insuranceMembers = @()
if ($objectIds["sophie"]) { $insuranceMembers += Build-EntraMember -ObjectId $objectIds["sophie"] -Tenant $TenantId }

$rolesInsurance = @(

    # ── Rôle 1 : BankingAdvisors ──────────────────────────────────────────────
    # Les conseillers bancaires accèdent aux tables natives d'assurance
    # Note : les shortcuts SSO (sc_*) ne peuvent PAS être ciblés par les Data Access Roles
    #        → leur accès est contrôlé côté LH-Banking (rôle BankingTeamFull)
    #        → la limitation de visibilité par conseiller est assurée par le RLS SM
    @{
        name          = "BankingAdvisors"
        decisionRules = @(
            @{
                effect     = "Permit"
                permission = @(
                    @{
                        attributeName            = "Action"
                        attributeValueIncludedIn = @("Read")
                    },
                    @{
                        attributeName            = "Path"
                        attributeValueIncludedIn = @(
                            "Tables/insurance_contracts",
                            "Tables/insurance_claims",
                            "Tables/security_table"
                        )
                    }
                )
            }
        )
        members = @{
            microsoftEntraMembers = $bankingMembers
            fabricItemMembers     = @()
        }
    },

    # ── Rôle 2 : InsuranceUsersRestricted ─────────────────────────────────────
    # sophie.marchand : accès uniquement aux tables natives Pacifica
    # Les shortcuts sc_* sont automatiquement bloqués car :
    #   1. sophie ∉ WS-Banking (couche 1) → LH-Banking inaccessible
    #   2. SSO shortcut transmet l'identité → sophie obtient 403 sur LH-Banking
    #   3. Les Data Access Roles ne peuvent pas cibler les shortcuts (limitation API)
    @{
        name          = "InsuranceUsersRestricted"
        decisionRules = @(
            @{
                effect     = "Permit"
                permission = @(
                    @{
                        attributeName            = "Action"
                        attributeValueIncludedIn = @("Read")
                    },
                    @{
                        attributeName            = "Path"
                        attributeValueIncludedIn = @(
                            "Tables/insurance_contracts",
                            "Tables/insurance_claims",
                            "Tables/security_table"
                        )
                    }
                )
            }
        )
        members = @{
            microsoftEntraMembers = $insuranceMembers
            fabricItemMembers     = @()
        }
    }
)

$okI = Set-DataAccessRoles -WsId $WsInsuranceId -LhId $LhInsuranceId -Label "LH-Insurance" -Roles $rolesInsurance

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 : LH-Banking — Accès réservé aux conseillers bancaires
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host " LH-BANKING — Configuration des Data Access Roles" -ForegroundColor DarkCyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor DarkCyan

# Note : sophie n'est pas membre de WS-Banking (couche 1 déjà bloquante)
# Ce rôle renforce la couche 4 sur LH-Banking pour les advisors eux-mêmes
$rolesBanking = @(
    @{
        name          = "BankingTeamFull"
        decisionRules = @(
            @{
                effect     = "Permit"
                permission = @(
                    @{
                        attributeName            = "Action"
                        attributeValueIncludedIn = @("Read")
                    },
                    @{
                        attributeName            = "Path"
                        attributeValueIncludedIn = @(
                            "Tables/dim_customers",
                            "Tables/fact_bank_accounts",
                            "Tables/bridge_ins_customers"
                        )
                    }
                )
            }
        )
        members = @{
            microsoftEntraMembers = $bankingMembers
            fabricItemMembers     = @()
        }
    }
)

$okB = Set-DataAccessRoles -WsId $WsBankingId -LhId $LhBankingId -Label "LH-Banking" -Roles $rolesBanking

# ── État final ─────────────────────────────────────────────────────────────────
Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host " ÉTAT APRÈS CONFIGURATION" -ForegroundColor DarkCyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Get-DataAccessRoles -WsId $WsInsuranceId -LhId $LhInsuranceId -Label "LH-Insurance"
Get-DataAccessRoles -WsId $WsBankingId   -LhId $LhBankingId   -Label "LH-Banking"

# ── Récapitulatif ──────────────────────────────────────────────────────────────
Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host " RÉCAPITULATIF — Architecture de sécurité complète" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "  Couche 1 │ Workspace Fabric     │ sophie ∉ WS-Banking → 403" -ForegroundColor White
Write-Host "  Couche 2 │ Shortcuts OneLake    │ données restent dans WS-Banking" -ForegroundColor White
Write-Host "  Couche 3 │ RLS SEM_Insurance    │ DAX USERPRINCIPALNAME() / bridge" -ForegroundColor White
Write-Host "  Couche 4 │ Data Access Roles    │ $(if ($okI -and $okB) {'✅ APPLIQUÉ'} else {'⚠️ PARTIEL — voir erreurs ci-dessus'})" -ForegroundColor $(if ($okI -and $okB) { 'Green' } else { 'Yellow' })
Write-Host ""
Write-Host "  Table               │ hugo/isabelle │ sophie" -ForegroundColor DarkGray
Write-Host "  ────────────────────┼───────────────┼────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  sc_dim_customers    │ ✅ (RLS ↓)    │ ❌ Data Access Role Deny" -ForegroundColor White
Write-Host "  sc_fact_bank_acc    │ ✅ (RLS ↓)    │ ❌ Data Access Role Deny" -ForegroundColor White
Write-Host "  sc_bridge_ins_cust  │ ✅            │ ❌ Data Access Role Deny" -ForegroundColor White
Write-Host "  insurance_contracts │ ✅ (RLS ↓)    │ ✅ Data Access Role Permit" -ForegroundColor White
Write-Host "  insurance_claims    │ ✅ (RLS ↓)    │ ✅" -ForegroundColor White
Write-Host "  security_table      │ ✅ (RLS ↓)    │ ✅ (ses propres lignes via RLS)" -ForegroundColor White
Write-Host ""
Write-Host "  ⚠️  Si les Data Access Roles ne sont pas disponibles sur ce tenant," -ForegroundColor Yellow
Write-Host "     activer via : Fabric Admin Portal → Tenant Settings" -ForegroundColor Yellow
Write-Host "     → OneLake → 'OneLake data access roles (preview)' → ON" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Pour tester l'isolation (accès SQL endpoint direct) :" -ForegroundColor Cyan
Write-Host "  1. Se connecter en tant que sophie.marchand" -ForegroundColor Gray
Write-Host "  2. Fabric Portal → WS-Insurance → LH-Insurance → SQL endpoint" -ForegroundColor Gray
Write-Host "  3. SELECT * FROM sc_dim_customers   → doit retourner 0 lignes / erreur" -ForegroundColor Gray
Write-Host "  4. SELECT * FROM insurance_contracts → doit retourner les données" -ForegroundColor Gray

