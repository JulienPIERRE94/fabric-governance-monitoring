# Microsoft Graph API Monitoring — Architecture & Design

> **Version** : 1.0 — June 2026  
> **Auteur** : CA-GIP Data & AI Architecture Team  
> **Périmètre** : Surveillance des appels API Microsoft Graph à l'échelle du tenant

---

## 📋 Table des Matières

1. [Contexte et Objectifs](#contexte-et-objectifs)
2. [Sources de Données](#sources-de-données)
3. [Architecture Fabric](#architecture-fabric)
4. [Logique de Transformation](#logique-de-transformation)
5. [Modèle Sémantique Power BI](#modèle-sémantique-power-bi)
6. [Mesures DAX](#mesures-dax)
7. [Données Exemple](#données-exemple)
8. [Dashboards Power BI](#dashboards-power-bi)
9. [Cas d'Usage Métier](#cas-dusage-métier)
10. [Plan d'Implémentation](#plan-dimplémentation)
11. [Contraintes et Bonnes Pratiques](#contraintes-et-bonnes-pratiques)

---

## 1. Contexte et Objectifs

### Problématique
Une organisation utilisant Microsoft 365 et Azure génère des **millions d'appels API Microsoft Graph** chaque jour : Power BI qui rafraîchit des rapports, des applications mobiles qui lisent les contacts, des scripts qui synchronisent des utilisateurs, etc.  
Sans monitoring, il est impossible de répondre aux questions suivantes :

- Quelle application consomme le plus d'API Graph ?
- Qui appelle des endpoints sensibles (`/auditLogs`, `/directoryRoles`) ?
- Quel est le taux d'erreur de nos intégrations ?
- Y a-t-il des appels excessifs ou anormaux (DoS interne, bug de pagination) ?

### Objectifs
| # | Objectif | Indicateur clé |
|---|----------|----------------|
| 1 | Surveiller le volume et la fréquence des appels API | Total API Calls / jour |
| 2 | Analyser les performances des intégrations | Avg/P95 Duration (ms) |
| 3 | Détecter les erreurs et anomalies | Error Rate (%), 401/403 |
| 4 | Auditer les accès aux ressources sensibles | Appels sur /auditLogs, /security |
| 5 | Gouvernance des applications | Apps inutilisées, permissions excessives |

---

## 2. Sources de Données

### 2.1 Graph Activity Logs ⭐ (Source principale)

| Propriété | Valeur |
|-----------|--------|
| **API / Export** | Azure Monitor > Diagnostic Settings > `MicrosoftGraphActivityLogs` |
| **Table Log Analytics** | `MicrosoftGraphActivityLogs` |
| **Latence** | ~15 minutes |
| **Rétention** | 30 jours (Log Analytics) / illimitée si archivé Fabric |
| **Licence** | Entra ID P1 ou P2 |

**Champs disponibles :**
```
RequestId       – identifiant unique de l'appel
TimeGenerated   – horodatage UTC
AppId           – ID de l'application appelante
UserId          – ID de l'utilisateur (vide si app-only)
RequestUri      – URI complète de l'appel
RequestMethod   – GET / POST / PATCH / DELETE
ResponseStatusCode – HTTP status code
DurationMs      – durée de traitement côté Microsoft
IPAddress       – adresse IP du client
UserAgent       – user agent string
ResourceTenantId – tenant cible
OperationId     – corrélation avec d'autres logs
```

### 2.2 Audit Logs — `auditLogs/directoryAudits`

| Propriété | Valeur |
|-----------|--------|
| **API** | `GET /v1.0/auditLogs/directoryAudits` |
| **Contenu** | Actions administratives (création user, attribution rôle, etc.) |
| **Différence vs Activity Logs** | Ne couvre PAS tous les appels API, seulement les actions à fort impact |
| **Rétention** | 30 jours (Entra P1), 90 jours (Entra P2) |
| **Permission** | `AuditLog.Read.All` |

### 2.3 Sign-in Logs — `auditLogs/signIns`

| Propriété | Valeur |
|-----------|--------|
| **API** | `GET /v1.0/auditLogs/signIns` |
| **Contenu** | Authentifications utilisateurs et applications |
| **Différence vs Activity Logs** | Couvre les authentifications, pas les appels API individuels |
| **Rétention** | 30 jours (Entra P1) |
| **Permission** | `AuditLog.Read.All` |

### 2.4 Usage Reports API

| Propriété | Valeur |
|-----------|--------|
| **API** | `GET /v1.0/reports/get*` |
| **Contenu** | Statistiques agrégées (Teams, SharePoint, Exchange) |
| **Granularité** | Journalière / hebdomadaire / mensuelle |
| **Permission** | `Reports.Read.All` |

### Comparatif des sources

| Critère | Activity Logs | Audit Logs | Sign-in Logs | Usage Reports |
|---------|:---:|:---:|:---:|:---:|
| Granularité appel API | ✅ | ❌ | ❌ | ❌ |
| Identité appelante | ✅ | ✅ | ✅ | ⚠️ anonymisé |
| Performance (durée) | ✅ | ❌ | ❌ | ❌ |
| Codes HTTP | ✅ | ❌ | ✅ (partiel) | ❌ |
| Volume de données | +++++ | ++ | +++ | + |
| Licence requise | P1/P2 | P1/P2 | P1/P2 | M365 E3 |

---

## 3. Architecture Fabric

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     INGESTION                                            │
│                                                                          │
│  Entra ID               Azure Monitor               Graph API           │
│  ┌──────────┐          ┌─────────────────┐         ┌────────────────┐  │
│  │ Activity │──export──│ Log Analytics   │         │ /auditLogs     │  │
│  │  Logs    │          │ Workspace       │         │ /signIns       │  │
│  └──────────┘          └────────┬────────┘         │ /users         │  │
│                                 │ Eventstream       │ /servicePrinc. │  │
│                                 ▼                   └───────┬────────┘  │
│                         Fabric Eventstream                  │ PS script │
│                                 │                           │           │
└─────────────────────────────────┼───────────────────────────┼───────────┘
                                  │                           │
┌─────────────────────────────────▼───────────────────────────▼───────────┐
│                  LAKEHOUSE : GraphMonitoring_Lakehouse                   │
│                                                                          │
│  BRONZE (raw)              SILVER (clean)          GOLD (aggregated)    │
│  ┌─────────────────┐      ┌──────────────────┐    ┌─────────────────┐  │
│  │ raw_activity_   │─────▶│ silver_api_calls │───▶│ gold_api_calls  │  │
│  │ logs/           │      │ (parsed endpoint │    │ _daily          │  │
│  │   YYYY/MM/DD/   │      │  enriched fields)│    │ (vol, perf,err) │  │
│  ├─────────────────┤      ├──────────────────┤    ├─────────────────┤  │
│  │ raw_audit_logs/ │─────▶│ silver_audit     │───▶│ gold_audit      │  │
│  ├─────────────────┤      ├──────────────────┤    │ _summary        │  │
│  │ raw_signins/    │─────▶│ silver_signins   │    ├─────────────────┤  │
│  ├─────────────────┤      ├──────────────────┤    │ gold_endpoint   │  │
│  │ raw_users/      │─────▶│ Dim_User         │    │ _rankings       │  │
│  │ raw_servicePr./ │─────▶│ Dim_Application  │    └─────────────────┘  │
│  └─────────────────┘      │ Dim_Endpoint     │                         │
│                            └──────────────────┘                         │
└──────────────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼
                    ┌──────────────────────────────┐
                    │   SEMANTIC MODEL (Power BI)   │
                    │   PowerBI_Graph_Monitoring    │
                    │                               │
                    │   Fact_API_Calls              │
                    │   Dim_Application             │
                    │   Dim_User                    │
                    │   Dim_Endpoint                │
                    │   Dim_Time                    │
                    └──────────────┬────────────────┘
                                   │
                    ┌──────────────▼────────────────┐
                    │         DASHBOARDS             │
                    │  · Executive Dashboard        │
                    │  · Technical Dashboard        │
                    │  · Security Dashboard         │
                    └───────────────────────────────┘
```

### Lakehouse Layers

#### Bronze — Données brutes
- Format : **Parquet** (partitionné par `year/month/day`)
- Pas de transformation, exactement comme reçu
- Conservation : **365 jours**
- Tables Delta : `bronze_activity_logs`, `bronze_audit_logs`, `bronze_signins`

#### Silver — Données nettoyées
- `Endpoint` extrait de `RequestUri` (GUID remplacés par `{id}`)
- `EndpointCategory` calculée (Identity / Mail / Teams / Files / etc.)
- Champs nuls normalisés (UserId vide → `"app-only"`)
- Déduplication sur `CallId`
- Tables Delta : `silver_api_calls`, `silver_audit_logs`, `silver_signins`

#### Gold — Données agrégées
- `gold_api_calls_daily` : agrégat jour × app × endpoint (volume, erreurs, durée avg/p95)
- `gold_endpoint_rankings` : top endpoints par volume et par taux d'erreur
- `gold_app_governance` : apps sans appels récents, apps avec taux d'erreur élevé
- Optimisé pour Power BI DirectQuery ou Import

---

## 4. Logique de Transformation

### Extraction d'Endpoint depuis RequestUri

```python
# Spark / PySpark (Silver layer)
import re
from pyspark.sql import functions as F
from pyspark.sql.functions import udf
from pyspark.sql.types import StringType

def extract_endpoint(uri: str) -> str:
    if not uri:
        return None
    # Supprimer le préfixe Graph
    path = re.sub(r'https://graph\.microsoft\.com/v[\d.]+', '', uri)
    # Supprimer la querystring
    path = re.sub(r'\?.*$', '', path)
    # Remplacer GUIDs par {id}
    path = re.sub(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '{id}', path)
    # Nettoyer (period='D7'), etc.
    path = re.sub(r"\(period='[^']*'\)", '', path)
    return path.rstrip('/')

extract_endpoint_udf = udf(extract_endpoint, StringType())
```

### Classification des Endpoints

```python
def classify_endpoint(uri: str) -> str:
    if not uri: return 'Unknown'
    patterns = [
        (r'/users|/groups|/applications|/servicePrincipals|/directoryRoles', 'Identity'),
        (r'/messages|/sendMail|/mailFolders',                                 'Mail'),
        (r'/calendars|/events|/contacts',                                     'Calendar'),
        (r'/drive|/sites',                                                    'Files'),
        (r'/teams|/chats|/channels',                                          'Teams'),
        (r'/reports',                                                         'Reports'),
        (r'/auditLogs|/security',                                             'Security'),
    ]
    for pattern, category in patterns:
        if re.search(pattern, uri):
            return category
    return 'Other'
```

### Calcul des métriques Silver → Gold

```sql
-- Gold : agrégat journalier
CREATE OR REPLACE TABLE gold_api_calls_daily AS
SELECT
    DATE(Timestamp)                          AS CallDate,
    AppId,
    Endpoint,
    EndpointCategory,
    HttpMethod,
    COUNT(*)                                 AS TotalCalls,
    SUM(CASE WHEN StatusCode >= 400 THEN 1 ELSE 0 END) AS ErrorCount,
    AVG(DurationMs)                          AS AvgDurationMs,
    PERCENTILE_APPROX(DurationMs, 0.95)      AS P95DurationMs,
    COUNT(DISTINCT UserId)                   AS DistinctUsers
FROM silver_api_calls
GROUP BY 1, 2, 3, 4, 5;
```

---

## 5. Modèle Sémantique Power BI

### Schéma en étoile

```
                    ┌──────────────────┐
                    │   Dim_Time       │
                    │ ────────────── │
                    │ Date (PK)        │
                    │ Year             │
                    │ Month / MonthName│
                    │ Day / DayOfWeek  │
                    │ Quarter          │
                    │ YearMonth        │
                    │ IsWeekend        │
                    └────────┬─────────┘
                             │ *:1
          ┌──────────────────┼───────────────────┐
          │                  │                   │
   ┌──────┴──────┐   ┌──────▼──────┐   ┌───────┴──────┐
   │Dim_Application│  │Fact_API_Calls│  │  Dim_User    │
   │ ──────────── │  │ ─────────── │  │ ──────────── │
   │AppId (PK)    │  │CallId (PK)   │  │UserId (PK)   │
   │AppDisplayName│  │Timestamp     │  │UserPrincipalN│
   │ServicePrinc. │  │AppId (FK)    │  │DisplayName   │
   │AppOwnerTenant│  │UserId (FK)   │  │Department    │
   │IsExternal    │  │RequestUri    │  │JobTitle      │
   └──────────────┘  │Endpoint (FK) │  │AccountEnabled│
                     │HttpMethod    │  └──────────────┘
   ┌──────────────┐  │StatusCode    │
   │Dim_Endpoint  │  │DurationMs    │
   │ ──────────── │  │IpAddress     │
   │Endpoint (PK) │  │UserAgent     │
   │Category      │  │TimestampDate │
   │SubCategory   │  │IsError (calc)│
   │ApiVersion    │  │EndpointCat.  │
   │IsWriteOp.    │  │  (calc)      │
   │Description   │  └─────────────┘
   └──────────────┘
```

### Tables — Schémas complets

#### Fact_API_Calls
| Colonne | Type | Description |
|---------|------|-------------|
| `CallId` | string (PK) | Identifiant unique de l'appel API (= RequestId Log Analytics) |
| `Timestamp` | datetime | Horodatage UTC de l'appel |
| `AppId` | string (FK) | ID de l'application (lien → Dim_Application) |
| `UserId` | string (FK) | ID de l'utilisateur ; vide si app-only (lien → Dim_User) |
| `RequestUri` | string | URI complète de l'appel Graph |
| `Endpoint` | string (FK) | Endpoint normalisé (lien → Dim_Endpoint) |
| `HttpMethod` | string | GET / POST / PATCH / PUT / DELETE |
| `StatusCode` | int | Code HTTP de réponse (200, 201, 204, 400, 401, 403, 404, 429, 500…) |
| `DurationMs` | int | Durée de traitement en millisecondes |
| `IpAddress` | string | Adresse IP source du client |
| `UserAgent` | string | User-Agent HTTP |
| `ResourceTenantId` | string | Tenant ID de la ressource ciblée |
| `OperationId` | string | ID de corrélation inter-logs |
| `TimestampDate` *(calc)* | date | Date extraite de Timestamp (clé vers Dim_Time) |
| `IsError` *(calc)* | boolean | TRUE si StatusCode ≥ 400 |
| `EndpointCategory` *(calc)* | string | Catégorie déduite de RequestUri |

#### Dim_Application
| Colonne | Type | Description |
|---------|------|-------------|
| `AppId` | string (PK) | Application (client) ID |
| `AppDisplayName` | string | Nom affiché de l'application |
| `ServicePrincipalType` | string | Application / ManagedIdentity / Legacy |
| `AppOwnerTenantId` | string | Tenant propriétaire |
| `IsExternal` | boolean | TRUE si l'app appartient à un autre tenant |

#### Dim_User
| Colonne | Type | Description |
|---------|------|-------------|
| `UserId` | string (PK) | Object ID Entra ID de l'utilisateur |
| `UserPrincipalName` | string | UPN (email) |
| `DisplayName` | string | Nom affiché |
| `Department` | string | Département / service |
| `JobTitle` | string | Fonction |
| `AccountEnabled` | boolean | Compte actif ou désactivé |

#### Dim_Endpoint
| Colonne | Type | Description |
|---------|------|-------------|
| `Endpoint` | string (PK) | Pattern d'endpoint normalisé (ex: `/users/{id}/messages`) |
| `Category` | string | Catégorie principale (Identity / Mail / Teams / Files / Calendar / Reports / Security) |
| `SubCategory` | string | Sous-catégorie (Users / Groups / Messages / Channels…) |
| `ApiVersion` | string | v1.0 / beta |
| `IsWriteOperation` | boolean | TRUE si l'endpoint permet des mutations |
| `Description` | string | Description fonctionnelle |

#### Dim_Time
| Colonne | Type | Description |
|---------|------|-------------|
| `Date` | date (PK) | Date (clé de jointure depuis Fact_API_Calls[TimestampDate]) |
| `Year` | int | Année |
| `Month` | int | Mois (1-12) |
| `MonthName` | string | Nom du mois |
| `Day` | int | Jour du mois (1-31) |
| `Hour` | int | Heure (0-23) |
| `DayOfWeek` | int | Jour de la semaine (1=Lundi, ISO) |
| `DayOfWeekName` | string | Nom du jour |
| `IsWeekend` | boolean | TRUE si Samedi ou Dimanche |
| `Quarter` | int | Trimestre (1-4) |
| `YearMonth` | string | Format `YYYY-MM` |
| `YearQuarter` | string | Format `YYYY-Q1` |

### Relationships

| Relation | From | To | Cardinalité | Direction |
|----------|----|--|-------------|-----------|
| Appels → Applications | `Fact_API_Calls[AppId]` | `Dim_Application[AppId]` | Many-to-One | → |
| Appels → Utilisateurs | `Fact_API_Calls[UserId]` | `Dim_User[UserId]` | Many-to-One | → |
| Appels → Endpoints | `Fact_API_Calls[Endpoint]` | `Dim_Endpoint[Endpoint]` | Many-to-One | → |
| Appels → Temps | `Fact_API_Calls[TimestampDate]` | `Dim_Time[Date]` | Many-to-One | → |

> **Note** : Toutes les relations sont **Many-to-One** avec filtrage dans un seul sens (Dim → Fact).  
> La relation `UserId` est **nullable** car les appels app-only n'ont pas d'UserId.

---

## 6. Mesures DAX

### Volume

```dax
Total API Calls =
COUNTROWS(Fact_API_Calls)

Total API Calls (App Only) =
CALCULATE(COUNTROWS(Fact_API_Calls), Fact_API_Calls[UserId] = "")

Total API Calls (Delegated) =
CALCULATE(COUNTROWS(Fact_API_Calls), Fact_API_Calls[UserId] <> "")

Distinct Applications =
DISTINCTCOUNT(Fact_API_Calls[AppId])

Distinct Users Calling API =
DISTINCTCOUNT(Fact_API_Calls[UserId])

Distinct Endpoints Called =
DISTINCTCOUNT(Fact_API_Calls[Endpoint])
```

### Performance

```dax
Avg Duration (ms) =
AVERAGE(Fact_API_Calls[DurationMs])

P95 Duration (ms) =
PERCENTILEINC(Fact_API_Calls[DurationMs], 0.95)

Max Duration (ms) =
MAX(Fact_API_Calls[DurationMs])
```

### Erreurs & Sécurité

```dax
Total Errors =
CALCULATE(COUNTROWS(Fact_API_Calls), Fact_API_Calls[StatusCode] >= 400)

Error Rate (%) =
DIVIDE(
    CALCULATE(COUNTROWS(Fact_API_Calls), Fact_API_Calls[StatusCode] >= 400),
    COUNTROWS(Fact_API_Calls)
)

Total Forbidden (403) =
CALCULATE(COUNTROWS(Fact_API_Calls), Fact_API_Calls[StatusCode] = 403)

Total Unauthorized (401) =
CALCULATE(COUNTROWS(Fact_API_Calls), Fact_API_Calls[StatusCode] = 401)
```

### Mutations (Write Operations)

```dax
Write Calls (POST/PUT/PATCH/DELETE) =
CALCULATE(
    COUNTROWS(Fact_API_Calls),
    Fact_API_Calls[HttpMethod] IN {"POST", "PUT", "PATCH", "DELETE"}
)

Write Rate (%) =
DIVIDE(
    CALCULATE(
        COUNTROWS(Fact_API_Calls),
        Fact_API_Calls[HttpMethod] IN {"POST", "PUT", "PATCH", "DELETE"}
    ),
    COUNTROWS(Fact_API_Calls)
)
```

### Time Intelligence

```dax
API Calls WoW Change =
VAR CurrentPeriod = [Total API Calls]
VAR PreviousPeriod =
    CALCULATE([Total API Calls], DATEADD(Dim_Time[Date], -7, DAY))
RETURN DIVIDE(CurrentPeriod - PreviousPeriod, PreviousPeriod)

Calls Last 7 Days =
CALCULATE(
    [Total API Calls],
    DATESINPERIOD(Dim_Time[Date], LASTDATE(Dim_Time[Date]), -7, DAY)
)
```

### Anomalie & Gouvernance

```dax
Calls per Day (Avg) =
AVERAGEX(VALUES(Dim_Time[Date]), [Total API Calls])

Anomaly Score (vs Avg) =
VAR DailyAvg = [Calls per Day (Avg)]
VAR Today    = [Total API Calls]
RETURN IF(DailyAvg = 0, BLANK(), DIVIDE(Today - DailyAvg, DailyAvg))

Apps with Errors =
CALCULATE(
    DISTINCTCOUNT(Fact_API_Calls[AppId]),
    Fact_API_Calls[StatusCode] >= 400
)
```

### Colonnes Calculées (Fact_API_Calls)

```dax
-- Clé de jointure vers Dim_Time
TimestampDate =
DATE(YEAR([Timestamp]), MONTH([Timestamp]), DAY([Timestamp]))

-- Flag erreur rapide
IsError =
IF([StatusCode] >= 400, TRUE(), FALSE())

-- Catégorie sans jointure (fallback si Dim_Endpoint non peuplé)
EndpointCategory =
SWITCH(
    TRUE(),
    CONTAINSSTRING([RequestUri], "/users"),          "Identity",
    CONTAINSSTRING([RequestUri], "/groups"),         "Identity",
    CONTAINSSTRING([RequestUri], "/applications"),   "Identity",
    CONTAINSSTRING([RequestUri], "/messages"),       "Mail",
    CONTAINSSTRING([RequestUri], "/calendars"),      "Calendar",
    CONTAINSSTRING([RequestUri], "/drive"),          "Files",
    CONTAINSSTRING([RequestUri], "/teams"),          "Teams",
    CONTAINSSTRING([RequestUri], "/chats"),          "Teams",
    CONTAINSSTRING([RequestUri], "/reports"),        "Reports",
    CONTAINSSTRING([RequestUri], "/auditLogs"),      "Security",
    "Other"
)
```

---

## 7. Données Exemple

### Fact_API_Calls (20 lignes sample)

| CallId | Timestamp | AppId | UserId | Endpoint | HttpMethod | StatusCode | DurationMs |
|--------|-----------|-------|--------|----------|-----------|-----------|-----------|
| call-001 | 2026-06-01 08:12 | app-001 | alice | /users | GET | 200 | 123 |
| call-002 | 2026-06-01 08:15 | app-001 | bob | /users/{id}/messages | GET | 200 | 456 |
| call-003 | 2026-06-01 08:20 | app-002 | alice | /groups | GET | 200 | 89 |
| call-004 | 2026-06-01 08:25 | app-002 | *(app-only)* | /reports/getTeamsUserActivityCounts | GET | 200 | 234 |
| call-005 | 2026-06-01 09:01 | app-003 | claire | /me/drive/root/children | GET | **403** | 67 |
| call-006 | 2026-06-01 09:15 | app-001 | alice | /users/{id} | PATCH | 204 | 345 |
| call-007 | 2026-06-01 09:30 | app-004 | david | /teams/{id}/channels | GET | 200 | 567 |
| call-008 | 2026-06-01 10:05 | app-003 | bob | /me/calendars | GET | 200 | 178 |
| call-009 | 2026-06-01 10:22 | app-002 | claire | /users | GET | **401** | 45 |
| call-010 | 2026-06-01 10:45 | app-004 | *(app-only)* | /applications | GET | 200 | 312 |

### Dim_Application (4 apps)

| AppId | AppDisplayName | ServicePrincipalType | IsExternal |
|-------|----------------|---------------------|-----------|
| app-001 | PowerBI Service | Application | FALSE |
| app-002 | Graph Explorer | Application | FALSE |
| app-003 | Contoso Mobile App | Application | FALSE |
| app-004 | Teams Integration Bot | Application | FALSE |

### Dim_User (4 utilisateurs)

| UserId | UserPrincipalName | Department | JobTitle |
|--------|------------------|-----------|---------|
| alice | alice.dupont@contoso.com | IT | Data Engineer |
| bob | bob.martin@contoso.com | Finance | Financial Analyst |
| claire | claire.bernard@contoso.com | HR | HR Manager |
| david | david.leroy@contoso.com | Sales | Sales Director |

---

## 8. Dashboards Power BI

### Dashboard 1 — Executive Overview
| Visuel | Mesure(s) | Description |
|--------|-----------|-------------|
| KPI Card | Total API Calls | Volume total sur la période |
| KPI Card | Error Rate (%) | Taux d'erreur global |
| KPI Card | API Calls WoW Change | Variation semaine sur semaine |
| Line Chart | Total API Calls / jour | Tendance temporelle |
| Bar Chart | Total API Calls par AppDisplayName | Top applications |
| Donut Chart | Total API Calls par EndpointCategory | Répartition par domaine fonctionnel |

### Dashboard 2 — Technical Performance
| Visuel | Mesure(s) | Description |
|--------|-----------|-------------|
| Matrix | Avg Duration par Endpoint | Endpoints les plus lents |
| Scatter Plot | TotalCalls vs Error Rate par App | Quadrant risque/volume |
| Bar Chart | P95 Duration par AppDisplayName | Variance de performance |
| Table | Top 10 endpoints par volume + durée avg | Détail technique |
| Line Chart | Write Rate (%) par jour | Tendance des mutations |

### Dashboard 3 — Security & Compliance
| Visuel | Mesure(s) | Description |
|--------|-----------|-------------|
| KPI Card | Total Forbidden (403) | Accès refusés |
| KPI Card | Total Unauthorized (401) | Tokens expirés / invalides |
| Table | Appels 403/401 par AppId + Endpoint | Détail sécurité |
| Map / Matrix | IpAddress par Department | Origines géographiques |
| Bar Chart | Write Calls par App | Applications qui modifient des données |
| Conditional Table | Anomaly Score | Jours avec volume anormal |

---

## 9. Cas d'Usage Métier

### 9.1 Analyse de Consommation API
**Question** : Quelle application génère le plus d'appels Graph ?  
**Réponse** : `Total API Calls` segmenté par `Dim_Application[AppDisplayName]`  
**Action** : Identifier les applications sur-optimisées (ex: pagination inefficace)

### 9.2 Suivi des Performances
**Question** : Nos intégrations respectent-elles les SLA de latence ?  
**Réponse** : `Avg Duration (ms)` et `P95 Duration (ms)` par endpoint  
**Seuil d'alerte** : P95 > 2000 ms → investigation requise

### 9.3 Détection d'Anomalies de Sécurité
**Patterns suspects** :
- Volume de 403 élevé pour une app → permissions insuffisantes ou révoquées
- Appels répétés sur `/auditLogs` par une app non référencée → investigation
- Volume nettement supérieur à la moyenne (`Anomaly Score > 200%`) → possible DoS interne

### 9.4 Gouvernance des Applications
**Question** : Quelles applications n'ont pas appelé l'API depuis 30 jours ?  
**Mesure** : `CALCULATE([Total API Calls], Calls Last 30 Days)`  
**Action** : Révoquer les permissions des apps inactives (principe du moindre privilège)

---

## 10. Plan d'Implémentation

### Étape 1 — Enregistrement de l'application
```powershell
# Dans le tenant Azure AD
# Portal > Entra ID > App registrations > New registration
# Nom : "GraphMonitoring-SP"
# Permissions requises (Application) :
#   - AuditLog.Read.All
#   - Reports.Read.All
#   - Directory.Read.All
#   - Application.Read.All
# Accorder le consentement administrateur
.\scripts\graph\New-GraphMonitoringServicePrincipal.ps1
```

### Étape 2 — Activation des Graph Activity Logs
```
Portal Azure > Microsoft Entra ID
  > Monitoring > Diagnostic settings
  > Add diagnostic setting
  > Cocher : MicrosoftGraphActivityLogs
  > Destination : Log Analytics Workspace
  > Sauvegarder
```
> ⚠️ Nécessite une licence **Entra ID P1 ou P2**

### Étape 3 — Collecte des données
```powershell
# Collecte sign-ins + audit logs + enrichissement dimensions
.\scripts\graph\Export-GraphMetrics.ps1 -SignInsDays 7

# Collecte Graph Activity Logs (si Log Analytics configuré)
.\scripts\graph\Export-GraphActivityLogs.ps1 `
    -UseLogAnalytics `
    -LogAnalyticsWorkspaceId "YOUR-WORKSPACE-ID" `
    -DaysBack 7
```

### Étape 4 — Ingestion Fabric
```python
# Notebook Fabric — Ingestion Bronze
from notebookutils import mssparkutils
spark.read.csv("abfss://graphmonitoring@onelake.dfs.fabric.microsoft.com/...") \
     .write.format("delta").mode("append") \
     .save("Tables/bronze_activity_logs")
```

### Étape 5 — Transformation Silver / Gold
```python
# Notebook Fabric — Transformation
from pyspark.sql import functions as F
df_silver = df_bronze \
    .withColumn("Endpoint", extract_endpoint_udf(F.col("RequestUri"))) \
    .withColumn("EndpointCategory", classify_endpoint_udf(F.col("RequestUri"))) \
    .dropDuplicates(["CallId"])
df_silver.write.format("delta").mode("overwrite").saveAsTable("silver_api_calls")
```

### Étape 6 — Chargement du modèle Power BI
```
1. Ouvrir PowerBI_Graph_Monitoring.pbip dans Power BI Desktop
2. Paramétrer DataFolder → chemin vers data/graph/
3. Refresh du modèle
4. Publier vers Fabric / Power BI Service
5. Configurer une actualisation planifiée (quotidienne)
```

---

## 11. Contraintes et Bonnes Pratiques

### Scalabilité
| Contrainte | Recommandation |
|------------|----------------|
| Large tenant (>10k users) | Utiliser Log Analytics + Eventstream, éviter le pull direct |
| Volume > 1M appels/jour | Passer en Gold layer + DirectQuery partiel |
| Historique > 30 jours | Archiver en Fabric Lakehouse (Log Analytics = 30 jours par défaut) |

### Sécurité
- Les credentials (`ClientSecret`) doivent être stockés dans **Azure Key Vault**, jamais en clair
- Le service principal de monitoring doit avoir **uniquement des permissions en lecture**
- Chiffrer les CSV dans `data/graph/` ou les stocker uniquement dans Fabric Lakehouse

### Éviter la Duplication
- Bronze → Silver : déduplication sur `CallId`
- Partitionnement par date pour les inserts incrémentaux
- Utiliser Delta Lake avec Z-ORDER sur `AppId, Timestamp` pour optimiser les filtres

### Optimisation Power BI
- Import mode pour Dim_* (petites tables)
- Import + aggregations pour Fact_API_Calls (tables Gold pré-agrégées)
- DirectQuery uniquement si données en temps réel requises
- CALENDARAUTO() pour Dim_Time (s'adapte automatiquement aux dates de Fact_API_Calls)

---

*Ce document décrit l'architecture cible. Pour l'implémentation dans un tenant de production, adapter les paramètres de rétention, sécurité et volumétrie selon les politiques internes.*
