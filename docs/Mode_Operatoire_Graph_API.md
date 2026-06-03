# Mode opératoire — Connexion Power BI à Microsoft Graph API

**Date :** 30 avril 2026  
**Public :** équipe BI, RSSI, exploitation  
**Objectif :** récupérer des données Microsoft Graph (utilisateurs, sign-ins, service principals, etc.) directement dans Power BI, avec authentification Service Principal et refresh planifié.

---

## 1) Vue d'ensemble

```
┌─────────────────┐     OAuth2     ┌──────────────────┐
│  Power BI       │ ──────────────▶│  Entra ID        │
│  (Power Query)  │ ◀── token ─────│  (login.MS.com)  │
└────────┬────────┘                └──────────────────┘
         │ Bearer token
         ▼
┌─────────────────┐
│  Microsoft Graph│
│  graph.MS.com   │
└─────────────────┘
```

---

## 2) Pré-requis

| Élément | Détail |
|---|---|
| Tenant Entra ID | Avec droits d'admin pour le consent |
| App Registration | Service Principal dédié |
| Permissions Graph | Permissions **Application** (pas Délégué) |
| Power BI Desktop | Version récente |
| Réseau | Sortie 443 vers `login.microsoftonline.com` et `graph.microsoft.com` |

---

## 3) Étape 1 — Créer l'App Registration

1. Portail Azure → **Microsoft Entra ID → App registrations → New registration**
2. Nom : `SP-PowerBI-GraphMonitoring`
3. Account types : **Single tenant**
4. Redirect URI : laisser vide
5. Cliquer **Register**
6. Noter :
   - **Application (client) ID**
   - **Directory (tenant) ID**

---

## 4) Étape 2 — Configurer les permissions

1. Sur l'app → **API permissions → Add a permission → Microsoft Graph → Application permissions**
2. Sélectionner les permissions nécessaires :

| Permission | Usage |
|---|---|
| User.Read.All | Lister les utilisateurs |
| AuditLog.Read.All | Sign-ins, audit logs |
| Directory.Read.All | Annuaire |
| Application.Read.All | Service Principals |
| Reports.Read.All | Rapports d'usage M365 |

3. Cliquer **Grant admin consent for <tenant>** (requis)

---

## 5) Étape 3 — Créer le secret

1. **Certificates & secrets → Client secrets → New client secret**
2. Description : `PBI-Graph-Refresh`
3. Expiration : **180 jours** (rotation à planifier)
4. **Copier la VALUE immédiatement** (elle ne sera plus jamais affichée)
5. Stocker dans un coffre (Key Vault, gestionnaire de secrets entreprise)

---

## 6) Étape 4 — Configurer Power BI Desktop

### 6.1 Créer les paramètres

**Transform Data → Manage Parameters → New** :

| Nom | Type | Valeur |
|---|---|---|
| TenantId | Text | (votre tenant) |
| ClientId | Text | (votre client id) |
| ClientSecret | Text | (votre secret) |

### 6.2 Créer la fonction d'authentification

**Transform Data → Home → New Source → Blank Query → Advanced Editor** :

```m
let
    fn = (tenantId as text, clientId as text, clientSecret as text) as text =>
    let
        tokenUrl = "https://login.microsoftonline.com/" & tenantId & "/oauth2/v2.0/token",
        body = "grant_type=client_credentials"
            & "&client_id=" & clientId
            & "&client_secret=" & Uri.EscapeDataString(clientSecret)
            & "&scope=" & Uri.EscapeDataString("https://graph.microsoft.com/.default"),
        response = Web.Contents(
            tokenUrl,
            [
                Content = Text.ToBinary(body),
                Headers = [#"Content-Type" = "application/x-www-form-urlencoded"],
                ManualStatusHandling = {400, 401, 403}
            ]
        ),
        json = Json.Document(response),
        token = json[access_token]
    in
        token
in
    fn
```

Renommer la requête en `fnGetGraphToken`.

### 6.3 Créer la fonction de pagination

```m
let
    fn = (url as text, token as text) as list =>
    let
        FetchPage = (pageUrl as text) =>
            let
                response = Web.Contents(
                    pageUrl,
                    [
                        Headers = [
                            #"Authorization" = "Bearer " & token,
                            #"ConsistencyLevel" = "eventual"
                        ],
                        ManualStatusHandling = {400, 401, 403, 429, 503}
                    ]
                ),
                json = Json.Document(response)
            in
                json,
        Pages = List.Generate(
            () => [page = FetchPage(url)],
            each [page] <> null,
            each [
                page = if Record.HasFields([page], "@odata.nextLink")
                       then FetchPage(Record.Field([page], "@odata.nextLink"))
                       else null
            ],
            each [page][value]
        ),
        Combined = List.Combine(Pages)
    in
        Combined
in
    fn
```

Renommer en `fnGetGraphPaged`.

---

## 7) Étape 5 — Exemples de requêtes Graph

### 7.1 Liste des utilisateurs

```m
let
    Token = fnGetGraphToken(TenantId, ClientId, ClientSecret),
    Url = "https://graph.microsoft.com/v1.0/users?$select=id,displayName,userPrincipalName,mail,jobTitle,department,accountEnabled&$top=999",
    Data = fnGetGraphPaged(Url, Token),
    AsTable = Table.FromList(Data, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    Expanded = Table.ExpandRecordColumn(AsTable, "Column1", {"id","displayName","userPrincipalName","mail","jobTitle","department","accountEnabled"})
in
    Expanded
```

### 7.2 Sign-Ins (7 derniers jours)

```m
let
    Token = fnGetGraphToken(TenantId, ClientId, ClientSecret),
    Filter = "createdDateTime ge " & DateTime.ToText(DateTime.LocalNow() - #duration(7,0,0,0), "yyyy-MM-ddTHH:mm:ssZ"),
    Url = "https://graph.microsoft.com/v1.0/auditLogs/signIns?$filter=" & Uri.EscapeDataString(Filter) & "&$top=1000",
    Data = fnGetGraphPaged(Url, Token),
    AsTable = Table.FromList(Data, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    Expanded = Table.ExpandRecordColumn(AsTable, "Column1", {"id","createdDateTime","userPrincipalName","userId","appDisplayName","appId","ipAddress","clientAppUsed","isInteractive"})
in
    Expanded
```

### 7.3 Service Principals

```m
let
    Token = fnGetGraphToken(TenantId, ClientId, ClientSecret),
    Url = "https://graph.microsoft.com/v1.0/servicePrincipals?$select=id,appId,displayName,servicePrincipalType,accountEnabled,appOwnerOrganizationId&$top=999",
    Data = fnGetGraphPaged(Url, Token),
    AsTable = Table.FromList(Data, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    Expanded = Table.ExpandRecordColumn(AsTable, "Column1", {"id","appId","displayName","servicePrincipalType","accountEnabled","appOwnerOrganizationId"})
in
    Expanded
```

---

## 8) Étape 6 — Endpoints Graph utiles

| Usage | Endpoint |
|---|---|
| Utilisateurs | `https://graph.microsoft.com/v1.0/users` |
| Groupes | `https://graph.microsoft.com/v1.0/groups` |
| Sign-ins (audit) | `https://graph.microsoft.com/v1.0/auditLogs/signIns` |
| Directory audits | `https://graph.microsoft.com/v1.0/auditLogs/directoryAudits` |
| App Registrations | `https://graph.microsoft.com/v1.0/applications` |
| Service Principals | `https://graph.microsoft.com/v1.0/servicePrincipals` |
| Licences | `https://graph.microsoft.com/v1.0/subscribedSkus` |
| Activité M365 | `https://graph.microsoft.com/v1.0/reports/getOffice365ActiveUserDetail(period='D7')` |

---

## 9) Étape 7 — Publication et refresh dans Power BI Service

1. **Publier** le fichier `.pbix` dans un workspace
2. Dataset → **Settings → Data source credentials**
3. Pour chaque source détectée :
   - `https://login.microsoftonline.com` → **Anonymous** + Privacy : **Organizational**
   - `https://graph.microsoft.com` → **Anonymous** + Privacy : **Organizational**
4. **Parameters** : modifier les valeurs si différentes du Desktop
5. **Scheduled refresh** → activer (1 à 8 fois/jour selon licence)

> Note : l'auth Power BI est "Anonymous" car le secret circule dans le body de la requête M. La sécurité repose sur le secret lui-même.

---

## 10) Bonnes pratiques

- **Service Principal dédié** par usage (un pour Power BI, un pour autre chose)
- **Permissions minimales** (préférer `Reports.Read.All` plutôt que `Directory.Read.All`)
- **Secret en Key Vault** + rotation tous les 90 à 180 jours
- **Filtrer côté Graph** avec `$select`, `$filter`, `$top` plutôt que côté Power Query
- **ConsistencyLevel: eventual** + `$count=true` pour les filtres avancés
- **Gérer le throttling 429** : respecter le header `Retry-After`
- **Versionner les requêtes M** dans un repo Git
- **Documenter** les Service Principals autorisés et leur usage

---

## 11) Mauvaises pratiques

- Stocker le `ClientSecret` en clair dans le `.pbix` partagé
- Utiliser un compte utilisateur (avec MFA) → cassera le refresh planifié
- Demander des permissions trop larges « pour aller vite »
- Ne pas gérer la pagination (`@odata.nextLink`) → données incomplètes
- Ignorer les erreurs `429` Throttling → bannissement temporaire
- Refresh trop fréquent (toutes les heures pour des données qui n'évoluent qu'une fois par jour)

---

## 12) Limites et points d'attention

- **Sign-ins** : nécessite licence **Entra ID P1 ou P2**
- **Throttling Graph** : varie selon endpoint (typique 10 000 req / 10 min / app)
- **Pagination** : pages de 100 à 999 selon endpoint
- **Format de date** ISO 8601 uniquement
- **Refresh M365 reports** : données décalées de 24 à 48 h
- **Privacy levels** : si plusieurs sources, configurer en `Organizational` ou désactiver Privacy

---

## 13) Diagnostic en cas d'erreur

| Erreur | Cause probable | Solution |
|---|---|---|
| 401 Unauthorized | Token invalide / expiré | Régénérer secret, vérifier admin consent |
| 403 Forbidden | Permission manquante | Vérifier API permissions + admin consent |
| 429 Too Many Requests | Throttling | Réduire fréquence, respecter Retry-After |
| AADSTS7000215 | Secret invalide | Régénérer le client secret |
| AADSTS700016 | App non trouvée | Vérifier ClientId / TenantId |
| Refresh failed in Service | Privacy levels | Mettre toutes les sources en Organizational |

---

## 14) Modèle Power BI fourni

Un modèle prêt à l'emploi est disponible :

- **Fichier BIM** : `PowerBI_Graph_Monitoring.bim`
- **Dossier TMDL** : `PowerBI_Graph_Monitoring.SemanticModel/`

Il contient :

- 3 paramètres (TenantId, ClientId, ClientSecret)
- 2 fonctions M (`fnGetGraphToken`, `fnGetGraphPaged`)
- 3 tables (`GraphUsers`, `GraphSignIns`, `GraphServicePrincipals`)
- 7 mesures DAX (Total Users, Sign-Ins 7j, Apps Distinctes, etc.)

### Chargement

Via Tabular Editor 2 → Open → `PowerBI_Graph_Monitoring.bim` → Save dans une instance Power BI Desktop ouverte.

---

## 15) Liens de référence

- Microsoft Graph overview : https://learn.microsoft.com/en-us/graph/overview
- Permissions reference : https://learn.microsoft.com/en-us/graph/permissions-reference
- Auth client_credentials : https://learn.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-client-creds-grant-flow
- Throttling Graph : https://learn.microsoft.com/en-us/graph/throttling
- Power Query Web.Contents in Service : https://learn.microsoft.com/en-us/power-query/connectors/web/web-troubleshoot

---

*Mode opératoire préparé le 30 avril 2026.*
