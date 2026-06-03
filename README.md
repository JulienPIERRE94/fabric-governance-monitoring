# CA-GIP — Gouvernance & Partage de données Microsoft Fabric

> **Proof of Concept** — Architecture de partage de données inter-domaines sous Microsoft Fabric  
> Cloisonnement Banque de Détail × Assurance avec OneLake Shortcuts, Direct Lake et RLS

[![Fabric](https://img.shields.io/badge/Microsoft%20Fabric-F2C811?style=flat&logo=microsoftpowerbi&logoColor=black)](https://aka.ms/fabric)
[![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=flat&logo=powershell&logoColor=white)](https://aka.ms/powershell)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## 🎯 Objectif

Démontrer comment des données d'un domaine métier (banque de détail) peuvent **alimenter un modèle analytique d'un autre domaine** (assurance) **sans que les utilisateurs du domaine cible n'aient accès au domaine source**.

### Cas d'usage
- Un **conseiller bancaire** voit ses clients + leurs contrats assurance s'ils ont consenti
- Un **gestionnaire assurance** voit uniquement les clients consentants, jamais les données bancaires
- Les données restent physiquement dans leur workspace d'origine (pas de copie)

## 🏗️ Architecture

```
Domaine Banque (WS-Banking)          Domaine Assurance (WS-Insurance)
══════════════════════════           ══════════════════════════════════
 Lakehouse_Banking                    Lakehouse_Insurance
  ├─ dim_customers       ──Shortcut──► sc_dim_customers
  ├─ fact_bank_accounts  ──Shortcut──► sc_fact_bank_accounts
  └─ bridge_ins_customers──Shortcut──► sc_bridge_ins_customers
                                       ├─ insurance_contracts
                                       ├─ insurance_claims
                                       ├─ security_table
                                       └─ SEM_Insurance
                                            ├─ Rôle BankingAdvisor (RLS)
                                            └─ Rôle InsuranceUser  (RLS)
```

## 📁 Arborescence

```
CA-GIP/
├── docs/
│   ├── Architecture_CrossDomain_DataSharing.md   # Architecture inter-domaines
│   └── ...                                       # Autres docs et guides
├── scripts/
│   ├── fabric/               # Déploiement Fabric (workspaces, lakehouses, SM)
│   │   ├── Deploy-FabricBankingDemo.ps1          # Upload CSVs + notebooks
│   │   ├── Poll-AndShortcuts.ps1                 # Création shortcuts OneLake
│   │   ├── Update-SMRoles.ps1                    # RLS roles via updateDefinition
│   │   ├── Patch-RealEmails.ps1                  # Mise à jour emails test
│   │   └── Verify-SMRoles.ps1                    # Vérification des rôles
│   ├── audit/                # Audit Power BI + Service Principal
│   ├── graph/                # Service Principal Graph + métriques
│   ├── fabric/               # Déploiement Fabric
│   └── docx/                 # Génération livrables Word
├── data/
│   └── samples/              # Jeux de données d'exemple (versionnés)
├── powerbi/
│   ├── api-monitoring/       # Modèle PBIP "PowerBI_API_Monitoring"
│   ├── fabric-monitoring/    # Modèle PBIP "PowerBI_Fabric_Monitoring"
│   └── graph-monitoring/     # Modèle PBIP "PowerBI_Graph_Monitoring"
└── secrets/                  # ⛔ Credentials SP (gitignored)
```

## 🚀 Déploiement rapide du PoC Fabric

### Prérequis
- Azure CLI (`az login` avec un compte admin du tenant)
- Microsoft Fabric avec capacité F/P active
- PowerShell 7+

### Étapes

```powershell
# 1. Déployer les workspaces, lakehouses et uploader les données
.\scripts\fabric\Deploy-FabricBankingDemo.ps1

# 2. Créer les shortcuts OneLake (après exécution des notebooks)
.\scripts\fabric\Poll-AndShortcuts.ps1

# 3. Mettre à jour les rôles RLS du modèle sémantique
.\scripts\fabric\Update-SMRoles.ps1

# 4. Patch emails avec vrais comptes du tenant
.\scripts\fabric\Patch-RealEmails.ps1

# 5. Vérifier les rôles déployés
.\scripts\fabric\Verify-SMRoles.ps1
```

### Comptes de test (à adapter selon votre tenant)

| Compte | Rôle RLS | Accès |
|---|---|---|
| `hugo.lambert@...` | `BankingAdvisor` | Ses 5 clients uniquement |
| `isabelle.fontaine@...` | `BankingAdvisor` | Ses 5 clients uniquement |
| `sophie.marchand@...` | `InsuranceUser` | 5 clients consentants, sans données bancaires |

## Workflow Graph Monitoring

```powershell
# 1. Créer le Service Principal (admin Entra requis pour le consent)
az login
.\scripts\graph\New-GraphMonitoringServicePrincipal.ps1
#   -> secrets\graph-monitoring-sp.credentials.json

# 2. Extraire les métriques Graph -> CSV
.\scripts\graph\Export-GraphMetrics.ps1
#   -> data\graph\graph_users.csv
#   -> data\graph\graph_serviceprincipals.csv
#   -> data\graph\graph_signins.csv (nécessite Entra ID P1/P2)

# 3. Ouvrir le rapport Power BI
start .\powerbi\graph-monitoring\PowerBI_Graph_Monitoring.pbip
```

## Workflow Audit Power BI

```powershell
# 1. Créer le SP d'audit (puis enregistrer le groupe dans le portail PBI Admin)
.\scripts\audit\New-PowerBIAuditServicePrincipal.ps1

# 2. Lancer l'audit
.\scripts\audit\Audit-PowerBI-Connections.ps1 -AuthMode ServicePrincipal
```

## Documentation

- [Mode opératoire Graph API](docs/Mode_Operatoire_Graph_API.md)
- [Guide Gouvernance PBIRS vs Power BI Service](docs/Guide_Gouvernance_PBIRS_vs_PowerBIService.md)
- [Démo Monitoring API Power BI Fabric](docs/Demo_Monitoring_API_PowerBI_Fabric.md)
- [README modèle API Monitoring](docs/PowerBI_API_Monitoring_README.md)
