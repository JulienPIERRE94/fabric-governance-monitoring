# Email reply – SSAS (ABF) backup consistency

**To:** Saurabh <saurabh@company.local>
**Cc:** Sabrina <sabrina@company.local>; BI Governance team
**Subject:** RE: SSAS backup (ABF) – consistency verification

---

Hi Saurabh,

Please find below the information regarding the consistency of SSAS Analysis Services Backup File (ABF) backups. The official Microsoft documentation is attached / linked at the end of this email.

## 1. How ABF consistency is guaranteed by the engine

SSAS (both Multidimensional and Tabular modes) writes ABF files through the `Backup` XMLA command. The operation is **transactionally consistent**:

- A read commit lock is taken on the database at the start of the backup. Any in-flight `Process` transaction must complete (or be rolled back) before the backup can read the files.
- The ABF archive contains **both data and metadata** (model definition, roles, partitions, calculations) as a single atomic unit. There is no partial / split state.
- For Tabular, the in-memory VertiPaq segments are flushed to the data folder and then archived; the backup reflects the database **as of the start time** of the backup.
- For Multidimensional, the same principle applies to MOLAP/ROLAP/HOLAP storage files.
- If the backup is interrupted (service crash, disk full, network drop on UNC), the resulting `.abf` is **not** committed: the file should be considered invalid and discarded.

Reference: *Backup and Restore of Analysis Services Databases* – Microsoft Learn.

## 2. Backup options that affect integrity

When generating the backup (XMLA, SSMS, PowerShell `Backup-ASDatabase`), the following options drive consistency and durability:

| Option | Recommendation | Reason |
|---|---|---|
| `AllowOverwrite` | true (with naming convention + retention) | avoids stale `.abf` |
| `ApplyCompression` | true (default) | smaller files, faster I/O |
| `Password` | set in production | encrypts the archive (AES) |
| `BackupRemotePartitions` | true if remote partitions exist | otherwise the archive is **incomplete** |
| `Locations` | one entry per remote partition server | required to bundle remote MOLAP files |

If `BackupRemotePartitions` is omitted on a scale-out / partitioned model, the resulting ABF is functionally inconsistent at restore time: query results will return errors for the missing partitions.

## 3. How to verify an ABF backup

There is no native `RESTORE VERIFYONLY` equivalent for SSAS. The supported verification path is:

1. **Restore to a non-production instance** with `AllowOverwrite=true` and `DbStorageLocation` pointing to a scratch folder.
2. Run a `Process Default` (Tabular) or open the database in SSMS (Multidimensional) – any structural corruption surfaces here.
3. Execute a representative DAX/MDX smoke test (row counts, key measures, role-based queries).
4. Check the SSAS msmdsrv log for `Errors in the metadata manager` or `File system error` entries during restore.

PowerShell helper (using SqlServer module):

```powershell
Import-Module SqlServer
Restore-ASDatabase `
    -Server "TEST-SSAS\TAB" `
    -RestoreFile "\\BACKUP\SSAS\Sales_20260505.abf" `
    -Name "Sales_RestoreCheck" `
    -AllowOverwrite `
    -Password (Read-Host -AsSecureString "ABF password")
```

For Tabular, you can additionally compare the model checksum before/after via:

```sql
SELECT [DATABASE_NAME], [LAST_DATA_UPDATE], [DATABASE_STATE]
FROM $SYSTEM.DBSCHEMA_CATALOGS;
```

## 4. Operational checklist (suggested)

- Run backups via SQL Agent / scheduled XMLA, **never** via file copy of the data folder (not supported, not consistent).
- Store ABF on a different volume than the SSAS data folder.
- Keep at least N+1 generations and run a weekly **restore drill** on a test instance.
- Monitor the msmdsrv log for `Backup` events (event class 32, subclass 1 = start, 2 = end). A backup with no matching end event is suspect.
- Hash the ABF (SHA-256) after the backup completes and store the hash with the file – allows future detection of bit rot on the backup volume.

## 5. Official Microsoft documentation (attached / links)

- Backup and Restore of Analysis Services Databases: https://learn.microsoft.com/en-us/analysis-services/multidimensional-models/backup-and-restore-of-analysis-services-databases
- Tabular model database backup, restore, and attach: https://learn.microsoft.com/en-us/analysis-services/tabular-models/backup-restore-and-attach-tabular-models-ssas-tabular
- `Backup` XMLA element reference: https://learn.microsoft.com/en-us/analysis-services/xmla/xml-elements-commands/backup-element-xmla
- `Restore` XMLA element reference: https://learn.microsoft.com/en-us/analysis-services/xmla/xml-elements-commands/restore-element-xmla
- High availability and disaster recovery for Analysis Services: https://learn.microsoft.com/en-us/analysis-services/instances/high-availability-and-disaster-recovery-for-analysis-services
- `Backup-ASDatabase` PowerShell cmdlet: https://learn.microsoft.com/en-us/powershell/module/sqlserver/backup-asdatabase
- `Restore-ASDatabase` PowerShell cmdlet: https://learn.microsoft.com/en-us/powershell/module/sqlserver/restore-asdatabase

I can also send a consolidated PDF of these pages if that helps the audit trail – let me know.

If useful, I can prepare a short PowerShell script (`scripts/ssas/Test-AsBackupIntegrity.ps1`) that automates points 1 to 4 above (test restore + smoke query + log scan + SHA-256 hashing). Just say the word.

Best regards,
Julien
BI / Power BI Governance team
