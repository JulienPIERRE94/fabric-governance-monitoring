# Modèle Power BI — Monitoring API Power BI / Fabric

## Contenu

- `PowerBI_API_Monitoring.bim` : modèle complet au format TMSL (JSON)
  - 3 tables : `ActivityEvents`, `DimDate`, `_Measures`
  - 1 paramètre : `CsvPath` (chemin du CSV)
  - 1 relation : `ActivityEvents[DateKey]` → `DimDate[Date]`
  - 18 mesures DAX prêtes à l'emploi
- `PowerBI_ActivityEvents_Sample.csv` : jeu de données simulé (1821 lignes, 7 jours)

---

## Option 1 — Charger via Tabular Editor (recommandé, le plus rapide)

### Pré-requis
- **Power BI Desktop** ouvert avec un fichier `.pbix` vide (File → New)
- **Tabular Editor 2** (gratuit) : https://tabulareditor.com/

### Étapes

1. Ouvrir Power BI Desktop, créer un nouveau fichier vide, le **sauvegarder** (ex. `Monitoring.pbix`).
2. Ouvrir **Tabular Editor 2**.
3. `File → Open → From File` → sélectionner `PowerBI_API_Monitoring.bim`.
4. `File → Save As` → choisir le moteur AS local de Power BI Desktop  
   (Tabular Editor détecte automatiquement l'instance ouverte).
5. Retourner dans Power BI Desktop → bouton **Refresh** → le modèle se peuple à partir du CSV.
6. Construire les visuels (voir section *Pages recommandées* ci-dessous).

---

## Option 2 — Reproduire manuellement dans Power BI Desktop (sans outil tiers)

Suivre [PowerBI_Demo_Modele_Mesures.md](PowerBI_Demo_Modele_Mesures.md) :

1. **Get Data → Text/CSV** → sélectionner `PowerBI_ActivityEvents_Sample.csv` (délimiteur `;`, UTF-8)
2. **Transform Data** → coller le script M fourni
3. **Modeling → New Table** → coller le DAX de `DimDate`
4. **Modeling → New Table** → `_Measures = ROW("Marqueur", "_")` puis masquer la colonne
5. Créer la relation `ActivityEvents[DateKey] → DimDate[Date]`
6. Ajouter les 18 mesures DAX dans `_Measures`

---

## Option 3 — Déployer sur Power BI Service / Fabric

Si vous disposez d'une **capacité Premium / Fabric** avec endpoint XMLA :

```powershell
# Déploiement via Tabular Editor CLI
& "C:\Program Files (x86)\Tabular Editor\TabularEditor.exe" `
    "PowerBI_API_Monitoring.bim" `
    -D "powerbi://api.powerbi.com/v1.0/myorg/<WORKSPACE>" "<DATASET_NAME>" `
    -O -C
```

---

## Paramétrer le chemin du CSV

Le modèle contient un paramètre `CsvPath`.  
Pour pointer vers votre vrai CSV (issu de `Get-PowerBIActivityEvents.ps1`) :

- Dans Power BI Desktop : **Transform Data → Manage Parameters → CsvPath** → modifier la valeur
- Dans Tabular Editor : sélectionner l'expression `CsvPath` et modifier la valeur littérale

---

## Pages recommandées à construire

### Page 1 — Vue d'ensemble
- Cards : `Total Evenements`, `Utilisateurs Distincts`, `Workspaces Actifs`, `Taux Succes`
- Line chart : `Total Evenements` par `DimDate[Date]` + `Moyenne Mobile 7j`
- Donut : par `OperationCategory`
- Card : `Pic Detecte`

### Page 2 — Top consommateurs
- Bar : Top 10 `UserId` par `Total Evenements`
- Bar : Top 10 `WorkSpaceName`
- Bar : Top 10 `DatasetName`
- Table : `Operation` × `Total Evenements`

### Page 3 — API et automatisation
- Cards : `Appels API`, `% Appels Automatises`
- Matrix : `HourOfDay` × `DayOfWeek` (heatmap)
- Bar : Top Service Principals (filtre `UserType = ServicePrincipal`)

### Page 4 — Fiabilité
- Cards : `Taux Echecs Refresh`, `Echecs`
- Bar : Échecs par `DatasetName`
- Time series : Échecs dans le temps
- Table détail filtré sur `IsSuccess = FALSE`

### Page 5 — Capacités Fabric
- Bar : `Total Evenements` par `CapacityName`
- Matrix : `WorkSpaceName` × `CapacityName`

---

## Mesures DAX incluses

| Mesure | Catégorie |
|---|---|
| Total Evenements | Volume |
| Utilisateurs Distincts | Volume |
| Workspaces Actifs | Volume |
| Datasets Utilises | Volume |
| Rapports Consultes | Volume |
| Appels API | Catégorisation |
| Refresh Datasets | Catégorisation |
| Exports | Catégorisation |
| Consultations | Catégorisation |
| Taux Succes | Fiabilité |
| Echecs | Fiabilité |
| Taux Echecs Refresh | Fiabilité |
| Evenements Jour Precedent | Tendance |
| Evolution % vs J-1 | Tendance |
| Moyenne Mobile 7j | Tendance |
| Pic Detecte | Anomalie |
| Appels Service Principal | Automatisation |
| % Appels Automatises | Automatisation |

---

*Modèle préparé le 29 avril 2026.*
