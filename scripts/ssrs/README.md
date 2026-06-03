# Scripts de migration SSRS

Ce dossier contient les scripts PowerShell associés au [Guide de migration SSRS](../../docs/Guide_Migration_SSRS.md).

## Pré-requis

```powershell
Install-Module ReportingServicesTools -Scope CurrentUser
Install-Module SqlServer             -Scope CurrentUser
```

Outils SSRS natifs requis sur les serveurs SSRS source et cible :
- `rskeymgmt.exe` (export/import clé de chiffrement)
- `rsconfig.exe` (configuration base de données)

## Ordre d'exécution

| # | Script | Étape du guide |
|---|---|---|
| 1 | [01-Audit-SSRS.ps1](01-Audit-SSRS.ps1) | Préparation / audit |
| 2 | [02-Backup-SSRS.ps1](02-Backup-SSRS.ps1) | Sauvegarde DB + clé |
| 3 | [03-Restore-SSRS.ps1](03-Restore-SSRS.ps1) | Restauration nouveau serveur |
| 4 | [04-Migrate-SSRSPermissions.ps1](04-Migrate-SSRSPermissions.ps1) | Migration accès / rôles |
| 5 | [05-Migrate-SSRSDataSources.ps1](05-Migrate-SSRSDataSources.ps1) | Sources de données partagées |
| 6 | [06-Migrate-SSRSReports.ps1](06-Migrate-SSRSReports.ps1) | RDL + dossiers |
| 7 | [07-Migrate-SSRSSubscriptions.ps1](07-Migrate-SSRSSubscriptions.ps1) | Souscriptions + schedules |
| 8 | [08-Test-SSRSReports.ps1](08-Test-SSRSReports.ps1) | Tests / validation |
| 9 | [09-Switch-SSRSProduction.ps1](09-Switch-SSRSProduction.ps1) | Cutover production |

## Configuration

Dupliquer [ssrs-config.sample.ps1](ssrs-config.sample.ps1) en `ssrs-config.ps1` (ignoré par Git) et le sourcer :

```powershell
. .\scripts\ssrs\ssrs-config.ps1
.\scripts\ssrs\01-Audit-SSRS.ps1 -ReportServerUri $SsrsConfig.OldReportServerUri -OutputFolder $SsrsConfig.OutputFolder
```

## Conventions

- Tous les scripts acceptent `-WhatIf` quand ils écrivent côté serveur cible.
- Les sorties CSV/JSON sont produites en UTF-8 (`-Encoding utf8`).
- Les erreurs non bloquantes sont écrites avec `Write-Warning` ; les erreurs bloquantes lèvent `throw`.
