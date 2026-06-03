# Modèle Power BI — Analyse de l'usage API Power BI / Fabric

Ce document décrit le **modèle de données**, les **mesures DAX** et les **visuels** à mettre en place dans Power BI Desktop pour analyser le CSV produit par `Get-PowerBIActivityEvents.ps1`.

---

## 1) Connexion à la source

**Power BI Desktop → Obtenir les données → Texte/CSV**

- Fichier : `PowerBI_ActivityEvents.csv`
- Délimiteur : `;`
- Encodage : `UTF-8`

---

## 2) Étapes Power Query

Renommer la requête en `ActivityEvents`.

```m
let
    Source = Csv.Document(
        File.Contents("C:\Users\Julien.SQL2022\Desktop\CA\CA-GIP\PowerBI_ActivityEvents.csv"),
        [Delimiter=";", Columns=27, Encoding=65001, QuoteStyle=QuoteStyle.Csv]
    ),
    Promoted = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Promoted, {
        {"CreationTime", type datetime},
        {"IsSuccess", type logical},
        {"Operation", type text},
        {"UserId", type text},
        {"WorkSpaceName", type text},
        {"DatasetName", type text},
        {"ReportName", type text},
        {"CapacityName", type text}
    }),
    AddDate = Table.AddColumn(Typed, "DateKey", each DateTime.Date([CreationTime]), type date),
    AddHour = Table.AddColumn(AddDate, "HourOfDay", each Time.Hour([CreationTime]), Int64.Type),
    AddDayName = Table.AddColumn(AddHour, "DayOfWeek", each Date.DayOfWeekName([DateKey]), type text),
    AddCategory = Table.AddColumn(AddDayName, "OperationCategory", each
        if Text.Contains([Operation], "Refresh") then "Refresh"
        else if Text.Contains([Operation], "View") then "Consultation"
        else if Text.Contains([Operation], "Export") then "Export"
        else if Text.Contains([Operation], "Get") then "API Read"
        else if Text.Contains([Operation], "Create") or Text.Contains([Operation], "Update") or Text.Contains([Operation], "Delete") then "API Write"
        else "Autre", type text)
in
    AddCategory
```

---

## 3) Table de dates (Calendrier)

Créer une table calculée DAX :

```DAX
DimDate =
ADDCOLUMNS(
    CALENDAR(
        MIN(ActivityEvents[DateKey]),
        MAX(ActivityEvents[DateKey])
    ),
    "Année",        YEAR([Date]),
    "Mois",         FORMAT([Date], "yyyy-MM"),
    "JourSemaine",  FORMAT([Date], "dddd"),
    "NumJour",      WEEKDAY([Date], 2)
)
```

**Relation** : `DimDate[Date]` ↔ `ActivityEvents[DateKey]` (1 → *)

---

## 4) Mesures DAX

### 4.1 Volumes globaux

```DAX
Total Évènements = COUNTROWS(ActivityEvents)

Total Utilisateurs Distincts =
DISTINCTCOUNT(ActivityEvents[UserId])

Total Workspaces Actifs =
DISTINCTCOUNT(ActivityEvents[WorkspaceId])

Total Datasets Utilisés =
DISTINCTCOUNT(ActivityEvents[DatasetId])

Total Rapports Consultés =
CALCULATE(
    DISTINCTCOUNT(ActivityEvents[ReportId]),
    ActivityEvents[OperationCategory] = "Consultation"
)
```

### 4.2 Catégorisation

```DAX
Appels API =
CALCULATE(
    [Total Évènements],
    ActivityEvents[OperationCategory] IN { "API Read", "API Write" }
)

Refresh Datasets =
CALCULATE(
    [Total Évènements],
    ActivityEvents[OperationCategory] = "Refresh"
)

Exports =
CALCULATE(
    [Total Évènements],
    ActivityEvents[OperationCategory] = "Export"
)

Consultations =
CALCULATE(
    [Total Évènements],
    ActivityEvents[OperationCategory] = "Consultation"
)
```

### 4.3 Taux et fiabilité

```DAX
Taux Succès =
DIVIDE(
    CALCULATE([Total Évènements], ActivityEvents[IsSuccess] = TRUE()),
    [Total Évènements]
)

Échecs =
CALCULATE([Total Évènements], ActivityEvents[IsSuccess] = FALSE())

Taux Échecs Refresh =
VAR _refresh = [Refresh Datasets]
VAR _failed =
    CALCULATE(
        [Total Évènements],
        ActivityEvents[OperationCategory] = "Refresh",
        ActivityEvents[IsSuccess] = FALSE()
    )
RETURN DIVIDE(_failed, _refresh)
```

### 4.4 Tendance et évolution

```DAX
Évènements Jour Précédent =
CALCULATE(
    [Total Évènements],
    DATEADD(DimDate[Date], -1, DAY)
)

Évolution % vs J-1 =
DIVIDE(
    [Total Évènements] - [Évènements Jour Précédent],
    [Évènements Jour Précédent]
)

Moyenne Mobile 7j =
AVERAGEX(
    DATESINPERIOD(DimDate[Date], MAX(DimDate[Date]), -7, DAY),
    [Total Évènements]
)
```

### 4.5 Détection d'anomalies / pics

```DAX
Pic Détecté =
VAR _avg = [Moyenne Mobile 7j]
VAR _today = [Total Évènements]
RETURN IF(_today > _avg * 1.5, "🔴 Pic", "✅ Normal")
```

### 4.6 Service Principals

```DAX
Appels Service Principal =
CALCULATE(
    [Total Évènements],
    ActivityEvents[UserType] = "ServicePrincipal"
        || CONTAINSSTRING(ActivityEvents[UserId], "@app")
)

% Appels Automatisés =
DIVIDE([Appels Service Principal], [Total Évènements])
```

---

## 5) Pages de rapport recommandées

### Page 1 — Vue d'ensemble
- **KPI cards** : Total Évènements, Utilisateurs Distincts, Workspaces, Taux Succès
- **Courbe** : Total Évènements par jour (avec moyenne mobile 7j)
- **Donut** : Répartition par OperationCategory
- **Carte d'anomalie** : Pic Détecté

### Page 2 — Top consommateurs
- **Bar chart** : Top 10 utilisateurs (par Total Évènements)
- **Bar chart** : Top 10 workspaces
- **Bar chart** : Top 10 datasets
- **Table** : Top 20 opérations détaillées

### Page 3 — API et automatisation
- **KPI** : Appels API, % Service Principal
- **Heatmap** : Appels par heure × jour de semaine
- **Bar chart** : Top Service Principals
- **Table** : Détail des appels avec filtre Operation

### Page 4 — Fiabilité
- **KPI** : Taux Échec Refresh, Échecs total
- **Bar chart** : Échecs par dataset
- **Time series** : Échecs dans le temps
- **Table** : Détail des opérations en échec

### Page 5 — Capacités Fabric
- **Bar chart** : Évènements par CapacityName
- **Table croisée** : Workspace × Capacity × Volume
- **Lien** vers la Fabric Capacity Metrics App

---

## 6) Filtres / segments recommandés

- Plage de dates (DimDate)
- Workspace
- OperationCategory
- UserType (User / ServicePrincipal)
- IsSuccess

---

## 7) Bonnes pratiques modèle

- Conserver les colonnes texte longues (`UserAgent`, `RequestId`) **hors résumé visuel**, uniquement pour drillthrough.
- Désactiver auto date/time global → la table `DimDate` est explicite.
- Mettre à jour le CSV par planification (script PowerShell + Task Scheduler) puis Refresh dataset.
- En production : envoyer les données dans **Azure Storage** ou **Log Analytics** plutôt qu'un CSV local.

---

## 8) Étapes de déploiement de la démo

1. Lancer le script `Get-PowerBIActivityEvents.ps1` → CSV produit
2. Ouvrir Power BI Desktop → connecter au CSV via Power Query (script M ci-dessus)
3. Créer la table `DimDate` et la relation
4. Ajouter les mesures DAX dans une table dédiée `_Measures`
5. Construire les pages de rapport
6. Publier dans le Service ou exposer en local

---

*Document préparé le 29 avril 2026.*
