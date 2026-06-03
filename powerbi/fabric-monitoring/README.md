# Power BI Fabric Monitoring

Stack complète de monitoring **tenant Fabric / Power BI** : workspaces, items, capacités, refreshes, activités utilisateurs.

## Service Principal

| Champ | Valeur |
|---|---|
| **App Name** | `SP-Fabric-Monitoring` |
| **AppId / ClientId** | `7d8ad4b8-7e99-41cc-8814-06a94a0a312c` |
| **TenantId** | `11e0a0b7-f122-4870-bca8-812e8f39ab21` |
| **Secret** | stocké dans [secrets/fabric-monitoring-sp.credentials.json](../../secrets/fabric-monitoring-sp.credentials.json) (expire 2028-05-05) |
| **Groupe d'autorisation** | `PBI-Audit-SPs` |

## ⚠️ Action requise — Tenant Settings (Admin Power BI)

Les APIs Fabric Admin et PBI Admin **n'utilisent pas Microsoft Graph**. Elles dépendent de 3 réglages dans le **portail admin Power BI** (`https://app.powerbi.com/admin-portal/tenantSettings`), à activer **pour le groupe `PBI-Audit-SPs`** :

1. **Developer settings** → *Allow service principals to use Power BI APIs* → **Enabled** → *Apply to specific security groups* → `PBI-Audit-SPs`
2. **Developer settings** → *Allow service principals to use Fabric APIs* → **Enabled** → `PBI-Audit-SPs`
3. **Admin API settings** → *Service principals can access read-only admin APIs* → **Enabled** → `PBI-Audit-SPs`

> Les modifications peuvent prendre **jusqu'à 15 minutes** pour se propager. Sans ces 3 réglages, l'extraction renvoie `401 / 403`.

## Pipeline

```
scripts/fabric/New-FabricMonitoringServicePrincipal.ps1   # 1. Création SP (one-shot)
scripts/fabric/Export-FabricMetrics.ps1                   # 2. Extraction (à planifier)
powerbi/fabric-monitoring/PowerBI_Fabric_Monitoring.pbip  # 3. Modèle PBIP
```

### Flux de données

```
Fabric Admin API ─┐
PBI Admin API   ─┼──► CSV (data/fabric/) ──► PBIP (TMDL) ──► Power BI Service
PBI Activity API ┘
```

## Données exportées

| Fichier CSV | API | Contenu |
|---|---|---|
| `fabric_workspaces.csv` | `GET /v1/admin/workspaces?type=Workspace` | Tous les workspaces du tenant |
| `fabric_items.csv` | `GET /v1/admin/items` | Tous les items Fabric (Lakehouse, Notebook, Report, SemanticModel, …) |
| `fabric_capacities.csv` | `GET /v1.0/myorg/admin/capacities` | Capacités F/P/A/EM + admins |
| `fabric_refreshables.csv` | `GET /v1.0/myorg/admin/capacities/refreshables` | Datasets rafraîchis : count, failures, durée |
| `fabric_activities.csv` | `GET /v1.0/myorg/admin/activityevents` | 7 derniers jours d'activité utilisateurs |

## Modèle Power BI

| | |
|---|---|
| **Tables** | 6 (5 faits/dim + `_FabricMeasures`) |
| **Mesures** | 14 |
| **Paramètre** | `DataFolder` (chemin local des CSV) |
| **Mode** | Import |

### Mesures clés

- `Total Workspaces`, `Workspaces Actifs`
- `Total Items`, `Items par Type`
- `Total Capacites`, `Capacites Actives`
- `Total Refreshables`, `Refresh / Jour Moyen`, `Echecs Refresh`, `Taux Echec Refresh %`, `Duree Moyenne Refresh (s)`
- `Total Activites`, `Utilisateurs Distincts`, `Operations Distinctes`

## Utilisation

```powershell
# 1. (Une seule fois) Activer les 3 tenant settings — voir section ci-dessus

# 2. Extraire les données
.\scripts\fabric\Export-FabricMetrics.ps1                      # 7 derniers jours
.\scripts\fabric\Export-FabricMetrics.ps1 -ActivityDays 30     # 30 derniers jours

# 3. Ouvrir le modèle
start .\powerbi\fabric-monitoring\PowerBI_Fabric_Monitoring.pbip
```

## Planification recommandée

| Tâche | Fréquence | Justification |
|---|---|---|
| Workspaces / Items / Capacités | 1×/jour | Métadonnées peu volatiles |
| Refreshables | 4×/jour | Détection rapide d'échecs |
| Activity events | 1×/jour (J-1 complet) | API rétention 30 jours |

Exemple Task Scheduler : déclencheur quotidien 06:00 → `pwsh.exe -File Export-FabricMetrics.ps1 -ActivityDays 1`.

## Sécurité

- ✅ Secret stocké dans `secrets/` (ignoré par git)
- ✅ SP en lecture seule (read-only admin APIs)
- ✅ Pas de permissions Graph (uniquement tenant settings PBI)
- ⚠️ Renouveler le secret avant le 2028-05-05

## Références officielles

- [Fabric Admin REST API](https://learn.microsoft.com/rest/api/fabric/admin/)
- [Power BI Admin API](https://learn.microsoft.com/rest/api/power-bi/admin)
- [Enable service principal authentication for read-only admin APIs](https://learn.microsoft.com/fabric/admin/metadata-scanning-enable-read-only-apis)
- [Embed Power BI content with service principal](https://learn.microsoft.com/power-bi/developer/embedded/embed-service-principal)
