# Guide de migration SSRS (obsolescence serveur)

**Auteur** : Équipe BI / Gouvernance Power BI
**Destinataire** : Sabrina – équipe Production
**Contexte** : migration d'une instance SQL Server Reporting Services (SSRS) sortante d'obsolescence vers une nouvelle instance (nouvelle VM / nouvelle version SQL Server).
**Objectif** : industrialiser et sécuriser la migration en 9 étapes, avec scripts PowerShell associés disponibles dans [scripts/ssrs/](../scripts/ssrs/).

> ⚠️ Ce guide couvre **SSRS natif** (SQL Server Reporting Services). Pour Power BI Report Server (PBIRS), la procédure est identique sur les 9 étapes mais l'API REST utilisée est `/reports/api/v2.0` et il faut sauvegarder en plus les fichiers `.pbix` publiés.

---

## Pré-requis communs

| Élément | Valeur |
|---|---|
| Compte d'exécution | Compte de service avec droit `sysadmin` SQL côté ancienne et nouvelle instance |
| Module PowerShell | `ReportingServicesTools` (PowerShell Gallery) – `Install-Module ReportingServicesTools -Scope CurrentUser` |
| Module SQL | `SqlServer` – `Install-Module SqlServer -Scope CurrentUser` |
| Outil Microsoft | `rskeymgmt.exe`, `rsconfig.exe` (livrés avec SSRS) |
| URL service web | ex. `http://OLD-SSRS/ReportServer` et `http://NEW-SSRS/ReportServer` |
| Réseau | Flux SQL (1433), HTTP/HTTPS SSRS, partage `\\NEW-SSRS\` pour copie de clés |

Toutes les variables sont centralisées dans le fichier [scripts/ssrs/ssrs-config.sample.ps1](../scripts/ssrs/ssrs-config.sample.ps1) (à dupliquer en `ssrs-config.ps1` non versionné).

---

## 1. PRÉPARATION – Audit de l'existant

**Livrables attendus** :
- Inventaire des rapports (chemin, taille, dernière exécution, propriétaire).
- Inventaire des sources de données partagées (type, chaîne masquée, mode d'authentification).
- Inventaire des souscriptions (planifiées + data-driven).
- Liste des rôles personnalisés et permissions par dossier.

**Script** : [01-Audit-SSRS.ps1](../scripts/ssrs/01-Audit-SSRS.ps1)

```powershell
.\scripts\ssrs\01-Audit-SSRS.ps1 `
    -ReportServerUri "http://OLD-SSRS/ReportServer" `
    -OutputFolder ".\out\ssrs-audit"
```

Génère :
- `reports.csv`, `datasources.csv`, `subscriptions.csv`, `permissions.csv`, `folders.csv`
- `audit-summary.json` (compteurs, taille totale, dernière exécution).

---

## 2. SAUVEGARDE

**Éléments à sauvegarder** :
1. Bases `ReportServer` et `ReportServerTempDB` (BAK SQL).
2. Clé de chiffrement SSRS (`.snk`) — **indispensable** pour relire les chaînes de connexion stockées chiffrées.
3. Fichier de configuration `rsreportserver.config` et `rssvrpolicy.config` (`%ProgramFiles%\Microsoft SQL Server Reporting Services\SSRS\ReportServer\`).
4. Custom assemblies / extensions (dossier `bin`).

**Script** : [02-Backup-SSRS.ps1](../scripts/ssrs/02-Backup-SSRS.ps1)

```powershell
.\scripts\ssrs\02-Backup-SSRS.ps1 `
    -SqlInstance "OLD-SQL01" `
    -BackupFolder "\\BACKUP\SSRS\$(Get-Date -f yyyyMMdd)" `
    -EncryptionKeyPassword (Read-Host -AsSecureString "Mot de passe clé")
```

Effectue :
- `BACKUP DATABASE ReportServer` + `ReportServerTempDB` (FULL, COMPRESSION, CHECKSUM).
- `rskeymgmt -e` pour exporter la clé.
- Copie des fichiers `.config` et du dossier `bin`.

> 🔐 La clé `.snk` et son mot de passe doivent être stockés dans le coffre-fort (CyberArk / KeePass entreprise).

---

## 3. INSTALLATION DU NOUVEAU SERVEUR

Étapes manuelles (Setup SSRS) — non scriptées car interactives :
1. Installer **SQL Server Reporting Services** (version cible, ex. SSRS 2022).
2. Lancer **Report Server Configuration Manager**.
3. Configurer : compte de service, URL service web, URL portail web, base de données → **pointer sur la base restaurée à l'étape suivante**.
4. NE PAS générer une nouvelle clé de chiffrement : on restaurera celle de l'ancien serveur.

**Restauration des bases + clé** : [03-Restore-SSRS.ps1](../scripts/ssrs/03-Restore-SSRS.ps1)

```powershell
.\scripts\ssrs\03-Restore-SSRS.ps1 `
    -SqlInstance "NEW-SQL01" `
    -BackupFolder "\\BACKUP\SSRS\20260505" `
    -EncryptionKeyFile "\\BACKUP\SSRS\20260505\rskey.snk" `
    -EncryptionKeyPassword (Read-Host -AsSecureString) `
    -SsrsServer "NEW-SSRS"
```

Effectue : `RESTORE DATABASE` (avec `WITH MOVE` si chemins différents), puis `rskeymgmt -a` pour réappliquer la clé sur la nouvelle instance.

---

## 4. MIGRATION DES ACCÈS

Les comptes locaux/AD sont conservés s'ils sont AD. Les rôles personnalisés (`System Roles` et `Item Roles`) doivent être **recréés** sur la nouvelle instance si la base `ReportServer` n'est pas restaurée intégralement (ex. installation propre).

**Script** : [04-Migrate-SSRSPermissions.ps1](../scripts/ssrs/04-Migrate-SSRSPermissions.ps1)

```powershell
# Export
.\scripts\ssrs\04-Migrate-SSRSPermissions.ps1 -Mode Export `
    -ReportServerUri "http://OLD-SSRS/ReportServer" -File ".\out\permissions.json"

# Import
.\scripts\ssrs\04-Migrate-SSRSPermissions.ps1 -Mode Import `
    -ReportServerUri "http://NEW-SSRS/ReportServer" -File ".\out\permissions.json"
```

Couvre : rôles système, policies par dossier/rapport, héritage cassé.

---

## 5. MIGRATION DES SOURCES DE DONNÉES PARTAGÉES

**Script** : [05-Migrate-SSRSDataSources.ps1](../scripts/ssrs/05-Migrate-SSRSDataSources.ps1)

```powershell
.\scripts\ssrs\05-Migrate-SSRSDataSources.ps1 `
    -SourceUri "http://OLD-SSRS/ReportServer" `
    -TargetUri "http://NEW-SSRS/ReportServer" `
    -ConnectionStringMap ".\config\connstr-mapping.csv"
```

Le CSV `connstr-mapping.csv` permet de transformer les chaînes (ex. `OLD-SQL01` → `NEW-SQL01`).
Les mots de passe stockés ne sont pas exportables en clair → **réinjection manuelle** ou via `Set-RsDataSourcePassword` (le script trace les datasources qui nécessitent une saisie).

---

## 6. MIGRATION DES RAPPORTS

**Script** : [06-Migrate-SSRSReports.ps1](../scripts/ssrs/06-Migrate-SSRSReports.ps1)

```powershell
# Téléchargement complet de l'arborescence
.\scripts\ssrs\06-Migrate-SSRSReports.ps1 -Mode Download `
    -ReportServerUri "http://OLD-SSRS/ReportServer" -LocalFolder ".\out\reports"

# Upload vers la nouvelle instance avec rebinding des datasources
.\scripts\ssrs\06-Migrate-SSRSReports.ps1 -Mode Upload `
    -ReportServerUri "http://NEW-SSRS/ReportServer" -LocalFolder ".\out\reports" `
    -RebindDataSources
```

Préserve l'arborescence des dossiers, les RDL, RDS, RSDS et fichiers liés (Excel, images).

---

## 7. MIGRATION DES SOUSCRIPTIONS

Les souscriptions (`Subscriptions` + `Schedule`) sont **liées par GUID** aux rapports. Elles peuvent être migrées via l'API SOAP/REST en utilisant `Get-RsSubscription` / `Set-RsSubscription` (module `ReportingServicesTools`).

**Script** : [07-Migrate-SSRSSubscriptions.ps1](../scripts/ssrs/07-Migrate-SSRSSubscriptions.ps1)

```powershell
# Export
.\scripts\ssrs\07-Migrate-SSRSSubscriptions.ps1 -Mode Export `
    -ReportServerUri "http://OLD-SSRS/ReportServer" -File ".\out\subscriptions.json"

# Import (recrée les schedules + bindings)
.\scripts\ssrs\07-Migrate-SSRSSubscriptions.ps1 -Mode Import `
    -ReportServerUri "http://NEW-SSRS/ReportServer" -File ".\out\subscriptions.json" `
    -EmailDomainMap ".\config\email-mapping.csv"
```

> ⚠️ Les souscriptions **data-driven** nécessitent SSRS Enterprise et doivent être ré-associées à leur datasource après migration.

---

## 8. TESTS ET VALIDATION

**Script** : [08-Test-SSRSReports.ps1](../scripts/ssrs/08-Test-SSRSReports.ps1)

```powershell
.\scripts\ssrs\08-Test-SSRSReports.ps1 `
    -ReportServerUri "http://NEW-SSRS/ReportServer" `
    -ReportList ".\config\critical-reports.csv" `
    -OutputFolder ".\out\test-runs"
```

Pour chaque rapport listé :
- Rendu PDF via l'URL access (`?rs:Format=PDF`).
- Mesure du temps d'exécution.
- Vérification HTTP 200 + taille > 0.
- Génère `test-results.csv` (OK/KO + durée).

Étapes manuelles complémentaires :
- Vérifier les souscriptions : déclencher `FireEventsAsync` pour 2-3 abonnements de contrôle.
- Faire valider les rapports critiques par les key users métiers (signature dans le PV de recette).

---

## 9. MISE EN PRODUCTION (CUTOVER)

**Script** : [09-Switch-SSRSProduction.ps1](../scripts/ssrs/09-Switch-SSRSProduction.ps1)

Effectue la check-list de bascule :
1. Met l'ancien serveur en lecture seule (désactive les souscriptions).
2. Bascule l'enregistrement DNS / alias (`ssrs.entreprise.local` → nouvelle IP).
3. Active les souscriptions sur le nouveau serveur.
4. Envoie un mail de communication aux utilisateurs (template inclus).
5. Lance la surveillance post-migration (compteurs perfmon + table `ExecutionLog3`).

```powershell
.\scripts\ssrs\09-Switch-SSRSProduction.ps1 `
    -OldUri "http://OLD-SSRS/ReportServer" `
    -NewUri "http://NEW-SSRS/ReportServer" `
    -DnsRecord "ssrs.entreprise.local" `
    -NewIp "10.20.30.40" `
    -SmtpServer "smtp.entreprise.local" `
    -CommRecipients "bi-users@entreprise.local"
```

### Surveillance J+1 à J+15

Requête de monitoring sur la base `ReportServer` (vue `ExecutionLog3`) :

```sql
SELECT
    ItemPath,
    UserName,
    TimeStart,
    TimeDataRetrieval, TimeProcessing, TimeRendering,
    [Status], ByteCount, [RowCount]
FROM ReportServer.dbo.ExecutionLog3
WHERE TimeStart >= DATEADD(day, -1, SYSUTCDATETIME())
  AND [Status] <> 'rsSuccess'
ORDER BY TimeStart DESC;
```

À intégrer dans le tableau de bord Power BI de gouvernance déjà en place ([powerbi/api-monitoring](../powerbi/api-monitoring/)).

---

## Annexes

### A. Matrice RACI (extrait)

| Étape | DBA | Admin SSRS | BI Dev | Métier |
|---|---|---|---|---|
| 1 Audit | C | **R** | C | I |
| 2 Backup | **R** | C | I | I |
| 3 Install | C | **R** | I | I |
| 4 Accès | C | **R** | I | C |
| 5 DataSources | C | **R** | C | I |
| 6 Rapports | I | **R** | C | I |
| 7 Souscriptions | I | **R** | I | C |
| 8 Tests | I | C | C | **R** |
| 9 Cutover | C | **R** | C | I |

### B. Points d'attention

- **Versioning** : un upgrade SSRS 2016 → 2022 implique une montée de schéma de la base `ReportServer` automatique au premier démarrage. **Ne pas downgrader**.
- **Custom code / assemblies** : à recopier dans le dossier `bin` du nouveau serveur **avant** de tester les rapports qui en dépendent.
- **Authentification** : si passage de NTLM à Kerberos, configurer les SPN et la délégation contrainte.
- **TLS** : forcer TLS 1.2 minimum sur le service web SSRS (clé registre `SecurityProtocol`).
- **Licences** : vérifier le mode (par cœur / serveur+CAL) avant la mise en production.

### C. Plan de rollback

En cas de blocage durant le cutover (étape 9) :
1. Restaurer l'ancien enregistrement DNS.
2. Réactiver les souscriptions de l'ancien serveur (`SET enabled = 1` dans `dbo.Subscriptions`).
3. Communiquer aux utilisateurs la bascule arrière.

L'ancien serveur doit rester **en l'état pendant 30 jours minimum** après la bascule.
