# Démo — Monitoring de l'usage de l'API Power BI / Fabric

**Date :** 29 avril 2026  
**Public :** équipe BI, exploitation, DSI client  
**Durée :** 45 à 60 minutes  
**Livrables :** script PowerShell, modèle Power BI, rapport d'analyse

---

## 1) Objectif de la démo

Démontrer comment :

- collecter les évènements d'usage Power BI / Fabric via l'API admin,
- centraliser les données,
- analyser les volumes, les utilisateurs, les opérations et les anomalies via Power BI,
- préparer une industrialisation (automatisation, alerting, rétention longue).

---

## 2) Architecture cible

```
┌────────────────────────┐
│  Power BI / Fabric     │
│  (Tenant client)       │
└───────────┬────────────┘
            │ API Admin (REST)
            │ /admin/activityevents
            ▼
┌────────────────────────┐
│  Service Principal     │
│  Entra ID              │
└───────────┬────────────┘
            ▼
┌────────────────────────┐
│  Script PowerShell     │
│  (collecte journalière)│
└───────────┬────────────┘
            ▼
┌────────────────────────┐
│  CSV / Storage / Log   │
│  Analytics             │
└───────────┬────────────┘
            ▼
┌────────────────────────┐
│  Modèle Power BI       │
│  (analyse + alerting)  │
└────────────────────────┘
```

---

## 3) Pré-requis

- Tenant Power BI / Fabric avec rôle Admin
- Service Principal Entra ID :
  - autorisé dans **Tenant settings → Allow service principals to use Power BI admin APIs (read-only)**
  - membre du groupe de sécurité associé
- PowerShell 7+
- Power BI Desktop (version récente)
- Accès à l'app **Microsoft Fabric Capacity Metrics** pour le volet capacité

---

## 4) Sources de métriques disponibles

| Source | Contenu | Rétention | Outil |
|---|---|---|---|
| API `admin/activityevents` | Toutes activités utilisateur/API | 30 jours | PowerShell / Python |
| Microsoft 365 Audit Log (Purview) | Audit centralisé `PowerBI` | 90 jours (1 an E5) | Portail Purview |
| Fabric Capacity Metrics App | CU, throttling, top items | 30 jours glissants | App Power BI |
| Azure Monitor / Log Analytics | Logs moteur Premium / Fabric | Configurable | Azure Portal / KQL |
| API admin REST | Inventaire workspaces, refresh, capacités | Live | PowerShell |

---

## 5) Métriques clés à présenter

| Métrique | Source | Valeur |
|---|---|---|
| Nombre d'appels API par jour | activityevents | Volumétrie |
| Top utilisateurs / Top workspaces | activityevents | Adoption |
| Répartition par opération | activityevents | Usage type |
| Refresh datasets (succès/échec) | refreshables | Fiabilité |
| Exports de rapports | activityevents | Conformité données sortantes |
| CU consommés par capacité | Capacity Metrics App | Coût et capacité |
| Throttling 429 | Logs HTTP / App Insights | Saturation API |
| Latence requêtes DAX | Log Analytics | Performance |
| Service Principals actifs | activityevents | Automatisation |

---

## 6) Déroulé de la démo

## 6.1 Étape 1 — Préparation (5 min)

- Créer un Service Principal Entra ID
- L'autoriser dans les Tenant settings Power BI
- Stocker secret dans Azure Key Vault (ou variable d'environnement pour la démo)

## 6.2 Étape 2 — Collecte (10 min)

Lancer le script `Get-PowerBIActivityEvents.ps1` :

```powershell
.\Get-PowerBIActivityEvents.ps1 `
    -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' `
    -ClientId 'yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy' `
    -ClientSecret 'zzzzzzzz' `
    -DaysBack 7 `
    -OutputCsv '.\PowerBI_ActivityEvents.csv'
```

Démontrer en console :

- Authentification OAuth2
- Boucle jour par jour avec pagination (continuationUri)
- Gestion du throttling 429
- Résumé : top opérations, top utilisateurs

## 6.3 Étape 3 — Modèle Power BI (15 min)

- Connexion CSV via Power Query (voir M-script du modèle)
- Création de `DimDate`
- Ajout des mesures DAX (table `_Measures`)
- Construction des pages :
  - Vue d'ensemble
  - Top consommateurs
  - API et automatisation
  - Fiabilité
  - Capacités Fabric

## 6.4 Étape 4 — Capacity Metrics (10 min)

- Ouvrir la **Fabric Capacity Metrics App**
- Présenter :
  - CU consommés (interactive vs background)
  - Throttling
  - Top items consommateurs
  - Détection d'un dataset gourmand

## 6.5 Étape 5 — Industrialisation (10 min)

- Planification du script (Task Scheduler / Azure Automation / Azure Function timer)
- Stockage long terme : Azure Storage ou Log Analytics
- Alerting : Azure Monitor sur seuils (pic anormal, taux d'échec, throttling)
- Rétention historique au-delà des 30 jours natifs API

---

## 7) Mesures DAX clés (rappel)

```DAX
Total Évènements = COUNTROWS(ActivityEvents)

Total Utilisateurs Distincts = DISTINCTCOUNT(ActivityEvents[UserId])

Taux Succès =
DIVIDE(
    CALCULATE([Total Évènements], ActivityEvents[IsSuccess] = TRUE()),
    [Total Évènements]
)

Refresh Datasets =
CALCULATE([Total Évènements], ActivityEvents[OperationCategory] = "Refresh")

Appels Service Principal =
CALCULATE([Total Évènements], ActivityEvents[UserType] = "ServicePrincipal")

Pic Détecté =
VAR _avg = [Moyenne Mobile 7j]
VAR _today = [Total Évènements]
RETURN IF(_today > _avg * 1.5, "🔴 Pic", "✅ Normal")
```

---

## 8) Bonnes pratiques

- Service Principal dédié, secret en Key Vault, rotation 90 jours
- Centraliser dans Log Analytics pour KQL + alertes
- Conserver l'historique au-delà des 30 jours natifs
- Croiser activité (qui/quoi/quand) avec capacité (combien ça coûte)
- Documenter les Service Principals autorisés et leur usage
- Mettre des seuils d'alerte explicites (taux d'échec > 5 %, throttling, pics)

## Mauvaises pratiques

- Compte nominatif pour automatiser la collecte
- Stockage du secret en clair dans le script
- Aucune rétention au-delà de 30 jours
- Analyse uniquement « volume » sans corréler à la capacité
- Aucun alerting sur les pics ou les échecs

---

## 9) Limites et points d'attention

- API admin : ~200 req/h sur certains endpoints → respecter la pagination + Retry-After
- 30 jours de rétention seulement côté API → automatiser sinon perte de données
- Les évènements peuvent arriver avec un léger décalage (jusqu'à 1h)
- Les appels Embed / Export ont des limites spécifiques (50/min, 50/h)
- L'audit Purview est plus complet pour la conformité

---

## 10) Liens de référence

- API GetActivityEvents : https://learn.microsoft.com/en-us/rest/api/power-bi/admin/get-activity-events
- Tracking user activities : https://learn.microsoft.com/en-us/power-bi/enterprise/service-admin-auditing
- Fabric Capacity Metrics : https://learn.microsoft.com/en-us/fabric/enterprise/metrics-app
- Workspace monitoring (Premium/Fabric) : https://learn.microsoft.com/en-us/fabric/admin/monitoring-workspace
- Service Principal Power BI : https://learn.microsoft.com/en-us/power-bi/enterprise/service-premium-service-principal
- API Throttling : https://learn.microsoft.com/en-us/power-bi/developer/embedded/embedded-troubleshoot

---

## 11) Livrables fournis

| Fichier | Rôle |
|---|---|
| `Get-PowerBIActivityEvents.ps1` | Collecte des évènements via l'API admin |
| `PowerBI_Demo_Modele_Mesures.md` | Modèle Power Query + DAX + structure du rapport |
| `Demo_Monitoring_API_PowerBI_Fabric.docx` | Document de présentation de la démo |

---

*Document préparé le 29 avril 2026.*
