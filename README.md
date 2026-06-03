# fabric-governance-monitoring

> **Monitoring, gouvernance et partage de données avec Microsoft Fabric & Power BI**
> Scripts PowerShell + modèles sémantiques PBIP prêts à déployer

[![Fabric](https://img.shields.io/badge/Microsoft%20Fabric-F2C811?style=flat&logo=microsoftpowerbi&logoColor=black)](https://aka.ms/fabric)
[![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=flat&logo=powershell&logoColor=white)](https://aka.ms/powershell)
[![Power BI](https://img.shields.io/badge/Power%20BI-F2C811?style=flat&logo=powerbi&logoColor=black)](https://powerbi.microsoft.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## 🎯 Vue d'ensemble

Ce repository regroupe **trois solutions de monitoring et gouvernance** pour les environnements Microsoft Fabric / Power BI, ainsi qu'un **PoC de partage de données inter-domaines** avec Row-Level Security.

| Solution | Description | Données collectées |
|----------|-------------|-------------------|
| 📊 **Fabric Monitoring** | Supervision des capacités et workspaces Fabric | Activités, capacités, workspaces, refreshables |
| 🔍 **API Monitoring** | Audit des appels à l'API Power BI | Events d'activité, connexions, datasets |
| 🌐 **Graph Monitoring** | Surveillance des usages Microsoft Graph | Users, sign-ins, service principals, activity logs |
| 🏦 **Banking/Insurance PoC** | Partage inter-domaines avec RLS Fabric | Démonstration cloisonnement Banking × Insurance |

---

## 🏗️ Architecture globale

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SOURCES DE DONNÉES                                  │
│                                                                             │
│  Microsoft Graph API    Power BI REST API    Microsoft Fabric REST API      │
│  (Users, SignIns,       (Activity Events,    (Workspaces, Capacities,       │
│   ServicePrincipals,     Connections,         Items, Refreshables,          │
│   ActivityLogs)          Datasets)            Activities)                   │
└──────────┬──────────────────────┬─────────────────────┬────────────────────┘
           │                      │                      │
           ▼                      ▼                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│              EXTRACTION  (PowerShell + Service Principals)                  │
│                                                                             │
│  Export-GraphMetrics.ps1        Get-PowerBIActivityEvents.ps1              │
│  Export-GraphActivityLogs.ps1   Audit-PowerBI-Connections.ps1              │
│  Export-FabricMetrics.ps1                                                  │
└──────────────────────────────────┬──────────────────────────────────────────┘
                                   │  CSV / JSON
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              data/                                          │
│   data/graph/              data/fabric/          data/samples/              │
│   ├─ graph_users.csv       ├─ fabric_activities  └─ ActivityEvents_Sample   │
│   ├─ graph_signins.csv     ├─ fabric_capacities                             │
│   ├─ graph_servicepr.csv   ├─ fabric_workspaces                             │
│   ├─ graph_dim_*.csv       ├─ fabric_items                                  │
│   └─ graph_audit_logs.csv  └─ fabric_refreshables                           │
└──────────────────────────────────┬──────────────────────────────────────────┘
                                   │  PBIP (TMDL + Semantic Model)
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      MODÈLES SÉMANTIQUES POWER BI                           │
│                                                                             │
│  PowerBI_Graph_Monitoring        PowerBI_Fabric_Monitoring                  │
│  ├─ Fact_API_Calls  (étoile)     ├─ Fact_Activities                        │
│  ├─ Dim_Application              ├─ Dim_Workspace                           │
│  ├─ Dim_User                     ├─ Dim_Item                                │
│  ├─ Dim_Endpoint                 └─ 30+ mesures DAX                         │
│  ├─ Dim_Time                                                                │
│  ├─ GraphUsers / SignIns / SP    PowerBI_API_Monitoring                     │
│  └─ 35 mesures DAX               ├─ ActivityEvents                          │
│                                  └─ Connexions / Datasets                   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Architecture PoC Banking × Insurance (RLS inter-domaines)

```
Workspace WS-Banking                    Workspace WS-Insurance
══════════════════════════              ══════════════════════════════════
 Lakehouse_Banking                       Lakehouse_Insurance
  ├─ dim_customers       ──Shortcut──►   sc_dim_customers
  ├─ fact_bank_accounts  ──Shortcut──►   sc_fact_bank_accounts
  └─ bridge_ins_customers──Shortcut──►   sc_bridge_ins_customers
                                          ├─ insurance_contracts
                                          ├─ insurance_claims
                                          ├─ security_table
                                          └─ SEM_Insurance
                                               ├─ Rôle: BankingAdvisor (RLS)
                                               └─ Rôle: InsuranceUser  (RLS)

✅ Les données restent physiquement dans WS-Banking (pas de copie).
✅ Les shortcuts OneLake évitent toute duplication.
✅ Le RLS est appliqué côté Insurance uniquement.
```

### Schéma étoile — PowerBI_Graph_Monitoring

```
         Dim_Time
            │
Dim_User ──►│◄── Fact_API_Calls ──► Dim_Application
            │         │
         Dim_Time  Dim_Endpoint

Tables brutes : GraphUsers · GraphSignIns · GraphServicePrincipals
Mesures DAX   : _GraphMeasures (35 mesures)
```

---

## 📁 Structure du repository

```
fabric-governance-monitoring/
│
├── powerbi/
│   ├── graph-monitoring/              # Monitoring Microsoft Graph
│   │   ├── PowerBI_Graph_Monitoring.pbip
│   │   └── PowerBI_Graph_Monitoring.SemanticModel/
│   │       ├── model.tmdl             # Relations, culture, annotations
│   │       ├── database.tmdl          # compatibilityLevel
│   │       ├── expressions.tmdl       # Paramètres M (DataFolder, credentials)
│   │       └── tables/                # 9 tables TMDL
│   ├── fabric-monitoring/             # Monitoring Fabric
│   └── api-monitoring/                # Monitoring API Power BI
│
├── scripts/
│   ├── graph/                         # Collecte Graph API
│   │   ├── New-GraphMonitoringServicePrincipal.ps1
│   │   ├── Export-GraphMetrics.ps1
│   │   └── Export-GraphActivityLogs.ps1
│   ├── fabric/                        # Déploiement et monitoring Fabric
│   │   ├── Deploy-FabricBankingDemo.ps1
│   │   ├── Export-FabricMetrics.ps1
│   │   ├── Create-OneLakeShortcuts.ps1
│   │   ├── Assign-RLSMembers.ps1
│   │   └── ...
│   ├── audit/                         # Audit Power BI
│   │   ├── New-PowerBIAuditServicePrincipal.ps1
│   │   ├── Get-PowerBIActivityEvents.ps1
│   │   └── Audit-PowerBI-Connections.ps1
│   └── docx/                          # Génération livrables Word
│
├── data/
│   ├── graph/                         # CSV extraits Graph API
│   ├── fabric/                        # CSV extraits Fabric API
│   └── samples/                       # Données sample pour tests offline
│
├── docs/                              # Documentation technique
│   ├── Architecture_Fabric_Banking_Insurance_Demo.md
│   ├── Architecture_GraphAPI_Monitoring.md
│   ├── Mode_Operatoire_Graph_API.md
│   └── ...
│
└── secrets/                           # ⛔ Gitignored — credentials SP locaux
```

---

## ✅ Prérequis

### Outils requis

| Outil | Version minimale | Installation |
|-------|-----------------|--------------|
| PowerShell | 7.2+ | [aka.ms/powershell](https://aka.ms/powershell) |
| Azure CLI | 2.50+ | [aka.ms/azurecli](https://aka.ms/azurecli) |
| Power BI Desktop | Juin 2024+ | [Microsoft Store](https://aka.ms/pbidesktop) |
| Git | 2.x | [git-scm.com](https://git-scm.com) |

### Permissions Azure / Fabric requises

| Module | Permissions nécessaires |
|--------|------------------------|
| **Graph Monitoring** | `User.Read.All`, `AuditLog.Read.All`, `Directory.Read.All`, `Application.Read.All` |
| **Fabric Monitoring** | Rôle **Fabric Admin** ou **Capacity Admin** |
| **API Monitoring** | Rôle **Power BI Admin** + groupe de sécurité dans le portail admin |
| **Banking/Insurance PoC** | Admin sur les workspaces Fabric + droits de création |

> ⚠️ **Entra ID P1/P2 requis** pour collecter les Sign-In Logs.
> Sans cette licence, `graph_signins.csv` reste vide mais le modèle fonctionne normalement.

---

## 🚀 Déploiement

### 0. Cloner le repository

```powershell
git clone https://github.com/JulienPIERRE94/fabric-governance-monitoring.git
cd fabric-governance-monitoring
```

---

### 🌐 Module Graph Monitoring

```powershell
# 1. Créer le Service Principal (nécessite Global Admin pour le consent)
az login
.\scripts\graph\New-GraphMonitoringServicePrincipal.ps1
# → secrets/graph-monitoring-sp.credentials.json

# 2. Extraire les métriques
.\scripts\graph\Export-GraphMetrics.ps1 -SignInsDays 30
# → data/graph/graph_users.csv
# → data/graph/graph_serviceprincipals.csv

# 3. Extraire les activity logs
.\scripts\graph\Export-GraphActivityLogs.ps1 -DaysBack 30
# → data/graph/graph_audit_logs.csv
# → data/graph/graph_dim_application.csv  (505 apps)
# → data/graph/graph_dim_user.csv         (32 users)

# 4. Ouvrir le rapport
Start-Process .\powerbi\graph-monitoring\PowerBI_Graph_Monitoring.pbip
# → Cliquer "Actualiser" dans Power BI Desktop
```

> 💡 Pour les Graph Activity Logs complets :
> **Entra ID > Monitoring > Diagnostic Settings** → activer `MicrosoftGraphActivityLogs` → Log Analytics

---

### 📊 Module Fabric Monitoring

```powershell
# 1. Créer le Service Principal Fabric
.\scripts\fabric\New-FabricMonitoringServicePrincipal.ps1
# → secrets/fabric-monitoring-sp.credentials.json

# 2. Exporter les métriques
.\scripts\fabric\Export-FabricMetrics.ps1
# → data/fabric/*.csv

# 3. Ouvrir le rapport
Start-Process .\powerbi\fabric-monitoring\PowerBI_Fabric_Monitoring.pbip
```

---

### 🔍 Module API Monitoring

```powershell
# 1. Créer le SP d'audit (puis enregistrer le groupe dans le portail Admin PBI)
.\scripts\audit\New-PowerBIAuditServicePrincipal.ps1

# 2. Extraire les événements d'activité
.\scripts\audit\Get-PowerBIActivityEvents.ps1 -DaysBack 30
# → data/samples/PowerBI_ActivityEvents_Sample.csv

# 3. Ouvrir le rapport
Start-Process .\powerbi\api-monitoring\PowerBI_API_Monitoring.pbip
```

---

### 🏦 PoC Banking × Insurance

```powershell
# 1. S'authentifier
az login

# 2. Déployer workspaces, lakehouses et données
.\scripts\fabric\Deploy-FabricBankingDemo.ps1

# 3. Exécuter les notebooks Fabric (chargement Delta)
.\scripts\fabric\Run-FabricNotebooks.ps1

# 4. Créer les shortcuts OneLake (Banking → Insurance)
.\scripts\fabric\Create-OneLakeShortcuts.ps1

# 5. Créer le modèle sémantique + rôles RLS
.\scripts\fabric\Create-SemanticModel.ps1

# 6. Assigner les membres aux rôles
.\scripts\fabric\Assign-RLSMembers.ps1

# 7. Vérifier
.\scripts\fabric\Verify-SMRoles.ps1
```

#### Comptes de test

| Compte | Rôle RLS | Ce qu'il voit |
|--------|----------|---------------|
| `hugo.lambert@tenant` | `BankingAdvisor` | Ses clients + leurs contrats assurance si consentement |
| `isabelle.fontaine@tenant` | `BankingAdvisor` | Ses clients uniquement |
| `sophie.marchand@tenant` | `InsuranceUser` | Clients consentants — **jamais** les données bancaires |

---

## ⚙️ Paramètre DataFolder

Chaque modèle sémantique expose un paramètre `DataFolder` pointant vers les CSV.
**À adapter après clonage** dans Power BI Desktop :

**Accueil → Transformer les données → Paramètres de requête → `DataFolder`**

---

## 📋 Limitations connues

| Limitation | Contournement |
|------------|---------------|
| Sign-In Logs nécessitent Entra ID P1/P2 | Modèle fonctionnel avec fichier vide (headers seulement) |
| Graph Activity Logs nécessitent Log Analytics | 20 lignes sample incluses pour les démos |
| Fabric API nécessite une capacité F/P active | CSV sample disponibles pour tests offline |

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [Architecture Banking/Insurance](docs/Architecture_Fabric_Banking_Insurance_Demo.md) | Architecture complète du PoC RLS |
| [Architecture Graph Monitoring](docs/Architecture_GraphAPI_Monitoring.md) | Architecture monitoring Graph API |
| [Mode opératoire Graph API](docs/Mode_Operatoire_Graph_API.md) | Guide pas-à-pas |
| [Demo Monitoring API Fabric](docs/Demo_Monitoring_API_PowerBI_Fabric.md) | Guide démo |
| [Gouvernance PBIRS vs PBI Service](docs/Guide_Gouvernance_PBIRS_vs_PowerBIService.md) | Comparatif gouvernance |

---

## 🔐 Sécurité

- Le dossier `secrets/` est **gitignored** — ne jamais committer de credentials
- Les Service Principals utilisent des secrets avec expiration (2 ans par défaut)
- Les permissions sont **Application-level** (pas delegated) pour les scripts automatisés
- Les rôles RLS sont définis en DAX dans les modèles sémantiques Fabric

---

## 📄 Licence

[MIT](LICENSE) — Julien PIERRE, 2026
