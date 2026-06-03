# Mail – Kit de migration SSRS + cohérence des sauvegardes SSAS (ABF)

**À :** Saurabh <saurabh@company.local>
**Cc :** Équipe Gouvernance BI
**Objet :** Kit de migration SSRS + cohérence des sauvegardes SSAS (ABF) – références et scripts

---

Bonjour Saurabh,

Suite à tes deux demandes, tu trouveras ci-dessous : le kit de migration SSRS et les informations relatives à la cohérence des sauvegardes SSAS (ABF). L'ensemble est publié sur GitHub pour faciliter le partage avec l'équipe de production.

---

## 1. Kit de migration SSRS

Suite à ta demande concernant la migration SSRS imposée par l'obsolescence du serveur actuel, le kit complet est disponible sur GitHub :

**Dépôt** : https://github.com/JulienPIERRE94/CA-GIP-ReportServer

**Documentation**

- Guide (Word) : https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/docs/Guide_Migration_SSRS_EN.docx
- Guide (source Markdown) : https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/docs/Guide_Migration_SSRS_EN.md
- Dossier des scripts : https://github.com/JulienPIERRE94/CA-GIP-ReportServer/tree/main/scripts/ssrs

Le guide couvre les prérequis, des exemples d'invocation, une matrice RACI, les points de vigilance (TLS, SPN/Kerberos, assemblies personnalisés, licences), un plan de retour arrière et les liens vers toutes les pages Microsoft Learn pertinentes (Annexe D).

**Chemin de migration recommandé** (supporté par Microsoft)

Le chemin principal est la restauration de la base de données + clé de chiffrement. Lorsque la base `ReportServer` est restaurée et que la clé `.snk` est réappliquée via `rskeymgmt -a`, l'ensemble des métadonnées est migré automatiquement (dossiers, rapports, sources de données, abonnements, permissions, rôles personnalisés).

| # | Étape | Script | Statut |
|---|---|---|---|
| 1 | Audit (lecture seule) | [01-Audit-SSRS.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/01-Audit-SSRS.ps1) | Fiable |
| 2 | Sauvegarde BDD + clé + config | [02-Backup-SSRS.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/02-Backup-SSRS.ps1) | Fiable |
| 3 | Restauration BDD + réapplication clé | [03-Restore-SSRS.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/03-Restore-SSRS.ps1) | Fiable |
| 4 | Validation – rendu des rapports critiques | [08-Test-SSRSReports.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/08-Test-SSRSReports.ps1) | Fiable |
| 5 | Bascule – checklist manuelle + T-SQL sur `dbo.Subscriptions.InactiveFlags` | n/a (manuel) | Fiable |

**Scripts optionnels / d'exemple** (Annexe E du guide) – nécessaires uniquement pour un scénario d'installation propre où la base `ReportServer` n'est PAS restaurée telle quelle. Ils sont fournis comme point de départ et doivent être testés sur un environnement hors production avant tout usage en production :

- [04-Migrate-SSRSPermissions.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/04-Migrate-SSRSPermissions.ps1)
- [05-Migrate-SSRSDataSources.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/05-Migrate-SSRSDataSources.ps1)
- [06-Migrate-SSRSReports.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/06-Migrate-SSRSReports.ps1)
- [07-Migrate-SSRSSubscriptions.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/07-Migrate-SSRSSubscriptions.ps1)
- [09-Switch-SSRSProduction.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/09-Switch-SSRSProduction.ps1)

**Prochaines étapes – merci de confirmer**

1. Versions SSRS source et cible (par ex. SSRS 2016 → SSRS 2022).
2. Topologie : serveur unique ou déploiement scale-out.
3. Fenêtre de maintenance cible pour les étapes 2, 3 et 5.
4. Serveur SMTP et liste de diffusion à utiliser pour la communication aux utilisateurs.

---

## 2. Cohérence des sauvegardes SSAS (ABF)

Tu trouveras ci-dessous les informations relatives à la cohérence des fichiers de sauvegarde SSAS (Analysis Services Backup File – ABF), avec la documentation officielle Microsoft en fin de section.

### 2.1 Comment la cohérence des ABF est garantie par le moteur

SSAS (modes Multidimensionnel et Tabulaire) écrit les fichiers ABF via la commande XMLA `Backup`. L'opération est **transactionnellement cohérente** :

- Un verrou de type *read commit* est posé sur la base au démarrage de la sauvegarde. Toute transaction `Process` en cours doit se terminer (ou être annulée) avant que la sauvegarde ne lise les fichiers.
- L'archive ABF contient à la fois les **données et les métadonnées** (définition du modèle, rôles, partitions, calculs) en une seule unité atomique. Il n'existe pas d'état partiel / scindé.
- Pour le mode Tabulaire, les segments VertiPaq en mémoire sont vidés vers le dossier de données puis archivés ; la sauvegarde reflète la base **à l'instant de démarrage** de la sauvegarde.
- Pour le mode Multidimensionnel, le même principe s'applique aux fichiers de stockage MOLAP / ROLAP / HOLAP.
- Si la sauvegarde est interrompue (crash du service, disque plein, coupure réseau sur UNC), le fichier `.abf` résultant n'est **pas** validé : il doit être considéré comme invalide et écarté.

### 2.2 Options de sauvegarde impactant l'intégrité

Lors de la génération de la sauvegarde (XMLA, SSMS, PowerShell `Backup-ASDatabase`) :

| Option | Recommandation | Raison |
|---|---|---|
| `AllowOverwrite` | true (avec convention de nommage + rétention) | évite les `.abf` obsolètes |
| `ApplyCompression` | true (par défaut) | fichiers plus petits, I/O plus rapides |
| `Password` | défini en production | chiffre l'archive (AES) |
| `BackupRemotePartitions` | true si partitions distantes | sinon archive **incomplète** |
| `Locations` | une entrée par serveur de partition distante | requis pour embarquer les fichiers MOLAP distants |

Si `BackupRemotePartitions` est omis sur un modèle scale-out / partitionné, l'ABF résultant est fonctionnellement incohérent au moment de la restauration.

### 2.3 Comment vérifier une sauvegarde ABF

Il n'existe pas d'équivalent natif `RESTORE VERIFYONLY` pour SSAS. Le chemin de vérification supporté est le suivant :

1. **Restaurer sur une instance hors production** avec `AllowOverwrite=true` et `DbStorageLocation` pointant vers un dossier scratch.
2. Exécuter un `Process Default` (Tabulaire) ou ouvrir la base dans SSMS (Multidimensionnel) – toute corruption structurelle apparaît à ce stade.
3. Exécuter un test de fumée DAX/MDX représentatif (volumétrie, mesures clés, requêtes par rôle).
4. Vérifier le journal SSAS msmdsrv pour les entrées `Errors in the metadata manager` ou `File system error` durant la restauration.

Aide PowerShell :

```powershell
Import-Module SqlServer
Restore-ASDatabase `
    -Server "TEST-SSAS\TAB" `
    -RestoreFile "\\BACKUP\SSAS\Sales_20260505.abf" `
    -Name "Sales_RestoreCheck" `
    -AllowOverwrite `
    -Password (Read-Host -AsSecureString "Mot de passe ABF")
```

### 2.4 Checklist opérationnelle

- Lancer les sauvegardes via SQL Agent / XMLA planifié, **jamais** via copie de fichiers du dossier de données (non supporté, non cohérent).
- Stocker l'ABF sur un volume différent du dossier de données SSAS.
- Conserver au moins N+1 générations et exécuter un **exercice de restauration** hebdomadaire sur une instance de test.
- Surveiller le journal msmdsrv pour les événements `Backup` (event class 32). Une sauvegarde sans événement de fin associé est suspecte.
- Hasher l'ABF (SHA-256) à l'issue de la sauvegarde et stocker le hash avec le fichier – permet de détecter ultérieurement un *bit rot* sur le volume de sauvegarde.

### 2.5 Documentation officielle Microsoft

- Backup and Restore of Analysis Services Databases : https://learn.microsoft.com/en-us/analysis-services/multidimensional-models/backup-and-restore-of-analysis-services-databases
- Tabular model database backup, restore, and attach : https://learn.microsoft.com/en-us/analysis-services/tabular-models/backup-restore-and-attach-tabular-models-ssas-tabular
- Référence de l'élément XMLA `Backup` : https://learn.microsoft.com/en-us/analysis-services/xmla/xml-elements-commands/backup-element-xmla
- Référence de l'élément XMLA `Restore` : https://learn.microsoft.com/en-us/analysis-services/xmla/xml-elements-commands/restore-element-xmla
- High availability and disaster recovery for Analysis Services : https://learn.microsoft.com/en-us/analysis-services/instances/high-availability-and-disaster-recovery-for-analysis-services
- Cmdlet PowerShell `Backup-ASDatabase` : https://learn.microsoft.com/en-us/powershell/module/sqlserver/backup-asdatabase
- Cmdlet PowerShell `Restore-ASDatabase` : https://learn.microsoft.com/en-us/powershell/module/sqlserver/restore-asdatabase

Un script PowerShell compagnon automatisant le chemin de vérification de la section 2.3 (restauration de test + `Process Default` + test de fumée DAX/MDX + analyse du journal msmdsrv + hash SHA-256) est également publié dans le même dépôt :

- [Test-AsBackupIntegrity.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssas/Test-AsBackupIntegrity.ps1)

Il doit être exécuté sur une instance SSAS **hors production**.

---

N'hésite pas à me dire si tu souhaites une session de travail pour parcourir ensemble le kit SSRS et caler le planning de migration avec l'équipe de production.

Cordialement,
Julien
Équipe Gouvernance BI / Power BI
