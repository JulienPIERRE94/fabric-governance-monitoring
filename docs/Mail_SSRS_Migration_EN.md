# Email – SSRS migration kit + SSAS (ABF) backup consistency

**To:** Saurabh <saurabh@company.local>
**Cc:** BI Governance team
**Subject:** SSRS migration kit + SSAS (ABF) backup consistency – references and scripts

---

Hi Saurabh,

Following your two requests, please find below: the SSRS migration kit and the SSAS (ABF) backup consistency information. Everything is published on GitHub for easy sharing with the production team.

---

## 1. SSRS migration kit

Following your request regarding the SSRS migration driven by the obsolescence of the current server, the full kit is now available on GitHub:

**Repository**: https://github.com/JulienPIERRE94/CA-GIP-ReportServer

**Documentation**

- Guide (Word): https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/docs/Guide_Migration_SSRS_EN.docx
- Guide (Markdown source): https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/docs/Guide_Migration_SSRS_EN.md
- Scripts folder: https://github.com/JulienPIERRE94/CA-GIP-ReportServer/tree/main/scripts/ssrs

The guide covers prerequisites, invocation examples, a RACI matrix, watchpoints (TLS, SPN/Kerberos, custom assemblies, licensing), a rollback plan and links to all relevant Microsoft Learn pages (Appendix D).

**Recommended migration path** (Microsoft-supported)

The primary path is the database + encryption key restore. When the `ReportServer` database is restored and the `.snk` key is reapplied with `rskeymgmt -a`, all metadata is migrated automatically (folders, reports, datasources, subscriptions, permissions, custom roles).

| # | Step | Script | Status |
|---|---|---|---|
| 1 | Audit (read-only) | [01-Audit-SSRS.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/01-Audit-SSRS.ps1) | Reliable |
| 2 | Backup DB + key + config | [02-Backup-SSRS.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/02-Backup-SSRS.ps1) | Reliable |
| 3 | Restore DB + reapply key | [03-Restore-SSRS.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/03-Restore-SSRS.ps1) | Reliable |
| 4 | Validation – critical report rendering | [08-Test-SSRSReports.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/08-Test-SSRSReports.ps1) | Reliable |
| 5 | Cutover – manual checklist + T-SQL on `dbo.Subscriptions.InactiveFlags` | n/a (manual) | Reliable |

**Optional / example scripts** (Appendix E of the guide) – only required for a clean-install scenario where the `ReportServer` database is NOT restored as-is. They are provided as a starting point and must be tested on a non-prod environment before any production use:

- [04-Migrate-SSRSPermissions.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/04-Migrate-SSRSPermissions.ps1)
- [05-Migrate-SSRSDataSources.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/05-Migrate-SSRSDataSources.ps1)
- [06-Migrate-SSRSReports.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/06-Migrate-SSRSReports.ps1)
- [07-Migrate-SSRSSubscriptions.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/07-Migrate-SSRSSubscriptions.ps1)
- [09-Switch-SSRSProduction.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/09-Switch-SSRSProduction.ps1)

**Next steps – please confirm**

1. Source and target SSRS versions (e.g. SSRS 2016 → SSRS 2022).
2. Topology: single-server or scale-out deployment.
3. Target maintenance window for steps 2, 3 and 5.
4. SMTP server and distribution list to be used for the user communication step.

---

## 2. SSAS (ABF) backup consistency

Please find below the information regarding the consistency of SSAS Analysis Services Backup File (ABF) backups, with the official Microsoft documentation linked at the end.

### 2.1 How ABF consistency is guaranteed by the engine

SSAS (both Multidimensional and Tabular modes) writes ABF files through the `Backup` XMLA command. The operation is **transactionally consistent**:

- A read commit lock is taken on the database at the start of the backup. Any in-flight `Process` transaction must complete (or be rolled back) before the backup can read the files.
- The ABF archive contains **both data and metadata** (model definition, roles, partitions, calculations) as a single atomic unit. There is no partial / split state.
- For Tabular, the in-memory VertiPaq segments are flushed to the data folder and then archived; the backup reflects the database **as of the start time** of the backup.
- For Multidimensional, the same principle applies to MOLAP/ROLAP/HOLAP storage files.
- If the backup is interrupted (service crash, disk full, network drop on UNC), the resulting `.abf` is **not** committed: the file should be considered invalid and discarded.

### 2.2 Backup options that affect integrity

When generating the backup (XMLA, SSMS, PowerShell `Backup-ASDatabase`):

| Option | Recommendation | Reason |
|---|---|---|
| `AllowOverwrite` | true (with naming convention + retention) | avoids stale `.abf` |
| `ApplyCompression` | true (default) | smaller files, faster I/O |
| `Password` | set in production | encrypts the archive (AES) |
| `BackupRemotePartitions` | true if remote partitions exist | otherwise the archive is **incomplete** |
| `Locations` | one entry per remote partition server | required to bundle remote MOLAP files |

If `BackupRemotePartitions` is omitted on a scale-out / partitioned model, the resulting ABF is functionally inconsistent at restore time.

### 2.3 How to verify an ABF backup

There is no native `RESTORE VERIFYONLY` equivalent for SSAS. The supported verification path is:

1. **Restore to a non-production instance** with `AllowOverwrite=true` and `DbStorageLocation` pointing to a scratch folder.
2. Run a `Process Default` (Tabular) or open the database in SSMS (Multidimensional) – any structural corruption surfaces here.
3. Execute a representative DAX/MDX smoke test (row counts, key measures, role-based queries).
4. Check the SSAS msmdsrv log for `Errors in the metadata manager` or `File system error` entries during restore.

PowerShell helper:

```powershell
Import-Module SqlServer
Restore-ASDatabase `
    -Server "TEST-SSAS\TAB" `
    -RestoreFile "\\BACKUP\SSAS\Sales_20260505.abf" `
    -Name "Sales_RestoreCheck" `
    -AllowOverwrite `
    -Password (Read-Host -AsSecureString "ABF password")
```

### 2.4 Operational checklist

- Run backups via SQL Agent / scheduled XMLA, **never** via file copy of the data folder (not supported, not consistent).
- Store ABF on a different volume than the SSAS data folder.
- Keep at least N+1 generations and run a weekly **restore drill** on a test instance.
- Monitor the msmdsrv log for `Backup` events (event class 32). A backup with no matching end event is suspect.
- Hash the ABF (SHA-256) after the backup completes and store the hash with the file – allows future detection of bit rot on the backup volume.

### 2.5 Official Microsoft documentation

- Backup and Restore of Analysis Services Databases: https://learn.microsoft.com/en-us/analysis-services/multidimensional-models/backup-and-restore-of-analysis-services-databases
- Tabular model database backup, restore, and attach: https://learn.microsoft.com/en-us/analysis-services/tabular-models/backup-restore-and-attach-tabular-models-ssas-tabular
- `Backup` XMLA element reference: https://learn.microsoft.com/en-us/analysis-services/xmla/xml-elements-commands/backup-element-xmla
- `Restore` XMLA element reference: https://learn.microsoft.com/en-us/analysis-services/xmla/xml-elements-commands/restore-element-xmla
- High availability and disaster recovery for Analysis Services: https://learn.microsoft.com/en-us/analysis-services/instances/high-availability-and-disaster-recovery-for-analysis-services
- `Backup-ASDatabase` PowerShell cmdlet: https://learn.microsoft.com/en-us/powershell/module/sqlserver/backup-asdatabase
- `Restore-ASDatabase` PowerShell cmdlet: https://learn.microsoft.com/en-us/powershell/module/sqlserver/restore-asdatabase

A companion PowerShell script automating the verification path of section 2.3 (test restore + `Process Default` + DAX/MDX smoke query + msmdsrv log scan + SHA-256 hashing) is also published in the same repository:

- [Test-AsBackupIntegrity.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssas/Test-AsBackupIntegrity.ps1)

It must be run against a **non-production** SSAS instance.

---

Please let me know if you would like a working session to walk through the SSRS kit and align the migration schedule with the production team.

Best regards,
Julien
BI / Power BI Governance team
