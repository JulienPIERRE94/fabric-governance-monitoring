# SSRS Migration Guide (server obsolescence)

**Author**: BI / Power BI Governance team
**Audience**: Production / Infrastructure team
**Context**: migration of an end-of-life SQL Server Reporting Services (SSRS) instance towards a new instance (new VM / new SQL Server version).
**Goal**: provide a reliable migration procedure aligned with Microsoft's documented approach, plus optional helper scripts for partial / clean-install scenarios.

> This guide covers native SSRS (SQL Server Reporting Services). For Power BI Report Server (PBIRS) the procedure is identical for the database + key path; the per-object REST API differs (`/reports/api/v2.0`).

---

## Recommended migration strategy

Microsoft's documented and supported migration path is:

1. **Back up** the `ReportServer` and `ReportServerTempDB` databases + the encryption key.
2. **Install** the new SSRS instance.
3. **Restore** the databases on the new SQL instance and **reapply** the encryption key.

When this path is followed, **all metadata is migrated automatically** because it lives inside the `ReportServer` database:

- Folder hierarchy
- Reports (RDL) and linked resources
- Shared data sources (with their stored encrypted credentials, thanks to the reapplied key)
- Subscriptions and schedules
- Roles and item-level permissions
- Custom roles
- Snapshots and caching settings

This is the **primary path** used in this guide. Per-object migration via the SSRS Web Service API (rebuilding datasources / reports / subscriptions one by one) is only required if the database cannot be restored as-is (clean install, version mismatch with manual schema rebuild, partial migration). Those scripts are provided as **optional examples** (see Appendix E) and must be tested on a non-prod environment before any production use.

---

## Common prerequisites

| Item | Value |
|---|---|
| Execution account | Service account with `sysadmin` SQL role on both source and target instances, plus local admin on the SSRS hosts |
| SQL module | `SqlServer` PowerShell module – `Install-Module SqlServer -Scope CurrentUser` |
| Microsoft tooling | `rskeymgmt.exe`, `rsconfig.exe` (shipped with SSRS) |
| Web service URL | e.g. `http://OLD-SSRS/ReportServer` and `http://NEW-SSRS/ReportServer` |
| Network | SQL flow (1433), HTTP/HTTPS to SSRS, `\\BACKUP\` SMB share for backups |

Variables can be centralised in [scripts/ssrs/ssrs-config.sample.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/ssrs-config.sample.ps1) (to be duplicated as `ssrs-config.ps1`, kept out of source control).

> **Verify the location of `rskeymgmt.exe` on the source server before step 2** — the path differs across SSRS versions. The provided scripts default to `%ProgramFiles%\Microsoft SQL Server Reporting Services\Shared Tools\rskeymgmt.exe` and fall back to `PATH`, but a sanity check is recommended:
>
> ```powershell
> Get-ChildItem 'C:\Program Files\Microsoft SQL Server*' -Recurse -Filter rskeymgmt.exe -ErrorAction SilentlyContinue
> ```

---

## 1. PREPARATION – Audit of the existing instance

**Expected deliverables**:
- Inventory of reports (path, size, last execution, owner).
- Inventory of shared data sources (type, masked connection string, authentication mode).
- Inventory of subscriptions (scheduled and data-driven).
- List of folder-level permissions.

**Script**: [01-Audit-SSRS.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/01-Audit-SSRS.ps1) – read-only, low risk.

```powershell
.\scripts\ssrs\01-Audit-SSRS.ps1 `
    -ReportServerUri "http://OLD-SSRS/ReportServer" `
    -OutputFolder ".\out\ssrs-audit"
```

Produces `reports.csv`, `datasources.csv`, `subscriptions.csv`, `permissions.csv`, `folders.csv`, `audit-summary.json`.

These files are reused later in step 4 (validation: count match between source and target) and constitute the audit trail of the migration.

---

## 2. BACKUP

**Items to back up**:
1. `ReportServer` and `ReportServerTempDB` databases (SQL `.bak`).
2. SSRS encryption key (`.snk`) – mandatory to decrypt stored connection strings on the new server.
3. Configuration files `rsreportserver.config`, `rssvrpolicy.config`, `rsmgrpolicy.config`.
4. Custom assemblies / extensions (`bin` folder).

**Script**: [02-Backup-SSRS.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/02-Backup-SSRS.ps1)

```powershell
$pwd = Read-Host -AsSecureString "Encryption key password"
.\scripts\ssrs\02-Backup-SSRS.ps1 `
    -SqlInstance "OLD-SQL01" `
    -BackupFolder "\\BACKUP\SSRS\$(Get-Date -f yyyyMMdd)" `
    -EncryptionKeyPassword $pwd
```

Performs:
- `BACKUP DATABASE ReportServer` + `ReportServerTempDB` (FULL, COMPRESSION, CHECKSUM).
- `rskeymgmt -e` to export the key.
- Copy of `.config` files and the `bin` folder.
- Generates a JSON manifest of the backup.

> The `.snk` key file and its password must be stored in the corporate vault (CyberArk / KeePass).

---

## 3. NEW SERVER INSTALLATION + DATABASE/KEY RESTORE

### 3.1 Manual installation steps (interactive, not scripted)

1. Install **SQL Server Reporting Services** (target version, e.g. SSRS 2022).
2. Launch **Report Server Configuration Manager**.
3. Configure: service account, web service URL, web portal URL.
4. **Database step**: choose "Choose an existing report server database" and point to the database that will be restored at step 3.2.
5. **Encryption keys step**: do NOT generate a new key – we will reapply the one exported at step 2.

### 3.2 Database restore + key reapply

**Script**: [03-Restore-SSRS.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/03-Restore-SSRS.ps1)

```powershell
$pwd = Read-Host -AsSecureString "Encryption key password"
.\scripts\ssrs\03-Restore-SSRS.ps1 `
    -SqlInstance "NEW-SQL01" `
    -BackupFolder "\\BACKUP\SSRS\20260505" `
    -EncryptionKeyFile "\\BACKUP\SSRS\20260505\rskey_20260505_120000.snk" `
    -EncryptionKeyPassword $pwd `
    -SsrsServer "NEW-SSRS"
```

Performs `RESTORE DATABASE` (with `WITH MOVE` if `-DataPath` / `-LogPath` are provided), then `rskeymgmt -a` to reapply the key.

After restore, restart the SSRS service:

```powershell
Restart-Service -Name 'SQLServerReportingServices'
```

### 3.3 Custom assemblies and configuration

If your reports use custom assemblies, copy the `bin` folder backed up at step 2 into the new server's SSRS `bin` folder before running validation tests.

Compare the relevant sections of `rsreportserver.config` (mail extension, authentication, custom security extensions) between the backup and the new server and merge the deltas manually. **Do not overwrite** the new file — service URLs and machine keys differ.

---

## 4. VALIDATION

After step 3, the new server should expose the exact same content as the old one. Validate this before scheduling cutover.

### 4.1 Re-run the audit on the new server

```powershell
.\scripts\ssrs\01-Audit-SSRS.ps1 `
    -ReportServerUri "http://NEW-SSRS/ReportServer" `
    -OutputFolder ".\out\ssrs-audit-new"
```

Compare the two `audit-summary.json` files (counts of reports / data sources / subscriptions / permissions). They must match.

### 4.2 Functional tests on critical reports

**Script**: [08-Test-SSRSReports.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/08-Test-SSRSReports.ps1) – uses the SSRS URL Access endpoint, low risk.

```powershell
.\scripts\ssrs\08-Test-SSRSReports.ps1 `
    -ReportServerUri "http://NEW-SSRS/ReportServer" `
    -ReportList ".\config\critical-reports.csv" `
    -OutputFolder ".\out\test-runs"
```

For each report listed:
- PDF render through URL access (`?rs:Format=PDF`).
- Execution time measurement.
- HTTP 200 + size > 0 check.
- Generates `test-results.csv` (OK/KO + duration).

### 4.3 Manual checks

- **Subscriptions** – open the Web Portal, check that subscriptions are listed and that one or two non-critical ones can be triggered manually.
- **Stored credentials** – open a couple of shared data sources and click "Test Connection" in the portal.
- **Business validation** – have the critical reports validated by business key users and document the sign-off.

---

## 5. PRODUCTION CUTOVER

The cutover steps below are **deliberately kept manual / semi-manual** because each environment has its own constraints (DNS server, change management, SMTP relay, scale-out topology). An optional automation script is provided in Appendix E as an example.

### 5.1 Cutover checklist

1. Communicate the maintenance window to users (T-1 day).
2. **Disable subscriptions on the old server** (prevents duplicate sends during the switch). Recommended: SQL update against `ReportServer.dbo.Subscriptions`:

   ```sql
   UPDATE ReportServer.dbo.Subscriptions SET InactiveFlags = 1;  -- to be reverted in case of rollback
   ```

3. **Switch DNS / load balancer** to point the SSRS alias to the new server.
4. **Re-enable subscriptions on the new server**:

   ```sql
   UPDATE ReportServer.dbo.Subscriptions SET InactiveFlags = 0;
   ```

5. Send the user communication (template in section 5.3).
6. Monitor (section 5.2).

### 5.2 Day+1 to Day+15 monitoring

Monitoring query against the `ReportServer` database (`ExecutionLog3` view) – **failed executions** in the last 24 hours:

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

Subscription failures:

```sql
SELECT s.Description, s.LastStatus, s.LastRunTime, c.Path
FROM ReportServer.dbo.Subscriptions s
JOIN ReportServer.dbo.Catalog c ON c.ItemID = s.Report_OID
WHERE s.LastStatus NOT LIKE 'Mail sent to%'
  AND s.LastStatus NOT LIKE 'File written%'
  AND s.LastRunTime > DATEADD(day, -1, GETDATE());
```

These queries can be plugged into the existing governance Power BI dashboard ([powerbi/api-monitoring](internal CA-GIP workspace: powerbi/api-monitoring/)).

### 5.3 User communication (template)

```
Subject: [INFO] SSRS migration completed

Dear users,

The SQL Server Reporting Services migration has been completed today.

- Stable URL (DNS): http://ssrs.company.local/Reports
- Old portal: kept read-only for 30 days

Reports, subscriptions and access rights have been preserved.
Please report any issue to the BI team.

Best regards,
The BI Governance team
```

---

## 6. ROLLBACK PLAN

If the cutover (step 5) is blocked:

1. Revert the DNS / load balancer change.
2. Re-enable the old server subscriptions:
   ```sql
   UPDATE ReportServer.dbo.Subscriptions SET InactiveFlags = 0;
   ```
3. Disable the new server subscriptions:
   ```sql
   UPDATE ReportServer.dbo.Subscriptions SET InactiveFlags = 1;
   ```
4. Communicate the rollback to users.

The old server **must be kept as-is for at least 30 days** after the cutover to allow rollback.

---

## Appendices

### A. RACI matrix

| Step | DBA | SSRS Admin | BI Dev | Business |
|---|---|---|---|---|
| 1 Audit | C | **R** | C | I |
| 2 Backup | **R** | C | I | I |
| 3 Install + Restore | **R** | **R** | I | I |
| 4 Validation | I | C | C | **R** |
| 5 Cutover | C | **R** | C | I |
| 6 Rollback (if needed) | C | **R** | I | I |

### B. Watchpoints

- **Versioning**: an SSRS 2016 → 2022 upgrade automatically migrates the `ReportServer` database schema on first start. Do not downgrade.
- **Custom code / assemblies**: copy them into the new server `bin` folder before running validation tests.
- **Authentication**: when moving from NTLM to Kerberos, configure SPNs and constrained delegation on the new service account.
- **TLS**: enforce TLS 1.2 minimum on the SSRS web service.
- **Licensing**: verify the licensing model (per core / server+CAL) before go-live.
- **Scale-out deployments**: each node must be joined with `rskeymgmt -j` after the key is reapplied.

### C. SQL queries for ad-hoc checks

Number of subscriptions per report:

```sql
SELECT c.Path, COUNT(s.SubscriptionID) AS Subs
FROM ReportServer.dbo.Catalog c
LEFT JOIN ReportServer.dbo.Subscriptions s ON s.Report_OID = c.ItemID
WHERE c.Type = 2  -- Report
GROUP BY c.Path
ORDER BY 2 DESC;
```

Top 20 slowest reports over the last 30 days:

```sql
SELECT TOP 20 ItemPath,
       AVG(TimeDataRetrieval + TimeProcessing + TimeRendering) AS AvgMs,
       COUNT(*) AS Runs
FROM ReportServer.dbo.ExecutionLog3
WHERE TimeStart > DATEADD(day, -30, SYSUTCDATETIME())
GROUP BY ItemPath
ORDER BY 2 DESC;
```

### D. Official Microsoft documentation

General installation and migration:
- What is SQL Server Reporting Services (SSRS): https://learn.microsoft.com/en-us/sql/reporting-services/create-deploy-and-manage-mobile-and-paginated-reports
- Install SQL Server Reporting Services: https://learn.microsoft.com/en-us/sql/reporting-services/install-windows/install-reporting-services
- Migrate a Reporting Services installation (native mode): https://learn.microsoft.com/en-us/sql/reporting-services/install-windows/migrate-a-reporting-services-installation-native-mode
- Upgrade and migrate Reporting Services: https://learn.microsoft.com/en-us/sql/reporting-services/install-windows/upgrade-and-migrate-reporting-services

Configuration and databases:
- Report Server Configuration Manager (Native mode): https://learn.microsoft.com/en-us/sql/reporting-services/install-windows/reporting-services-configuration-manager-native-mode
- Configure and administer a report server (Native mode): https://learn.microsoft.com/en-us/sql/reporting-services/report-server/configure-and-administer-a-report-server-ssrs-native-mode
- Create a report server database: https://learn.microsoft.com/en-us/sql/reporting-services/install-windows/create-a-report-server-database
- Move report server databases to another computer: https://learn.microsoft.com/en-us/sql/reporting-services/report-server-database/moving-the-report-server-databases-to-another-computer

Encryption keys:
- Configure and manage encryption keys: https://learn.microsoft.com/en-us/sql/reporting-services/install-windows/configure-and-manage-encryption-keys
- Back up and restore Reporting Services encryption keys: https://learn.microsoft.com/en-us/sql/reporting-services/install-windows/back-up-and-restore-reporting-services-encryption-keys
- rskeymgmt utility: https://learn.microsoft.com/en-us/sql/reporting-services/tools/rskeymgmt-utility

Security and permissions:
- Roles and permissions (Reporting Services): https://learn.microsoft.com/en-us/sql/reporting-services/security/roles-and-permissions-reporting-services
- Grant user access to a report server: https://learn.microsoft.com/en-us/sql/reporting-services/security/grant-user-access-to-a-report-server
- Configure Windows service account and Kerberos: https://learn.microsoft.com/en-us/sql/reporting-services/install-windows/configure-the-report-server-service-account

Operations and monitoring:
- Report Server ExecutionLog and ExecutionLog3 view: https://learn.microsoft.com/en-us/sql/reporting-services/report-server/report-server-executionlog-and-the-executionlog3-view
- Performance, snapshots, caching: https://learn.microsoft.com/en-us/sql/reporting-services/report-server/performance-snapshots-caching-reporting-services
- URL access (parameter reference): https://learn.microsoft.com/en-us/sql/reporting-services/url-access-ssrs

PowerShell automation:
- ReportingServicesTools module (GitHub): https://github.com/microsoft/ReportingServicesTools
- ReportingServicesTools cmdlets reference: https://github.com/microsoft/ReportingServicesTools/wiki

Power BI Report Server (if applicable):
- Power BI Report Server documentation: https://learn.microsoft.com/en-us/power-bi/report-server/
- Migrate from SSRS to Power BI Report Server: https://learn.microsoft.com/en-us/power-bi/report-server/migrate-report-server

---

### E. Optional helper scripts (NOT part of the recommended path)

WARNING – Example scripts only.

The scripts listed below address the clean install scenario, where the ReportServer database is NOT restored as-is and the content must be rebuilt object by object on the new server. They rely on the ReportingServicesTools PowerShell module (community-maintained) and on the SSRS Web Service SOAP API.

They have not been validated end-to-end on a production-like environment by the author of this guide. They are provided as a starting point / example and must be tested on a non-prod environment before any production use. The recommended migration path remains the database + encryption key restore (steps 1 to 6 above), which is fully documented and supported by Microsoft.

Prerequisite for the optional scripts:

```powershell
Install-Module ReportingServicesTools -Scope CurrentUser
```

| Optional script | Purpose | Known caveats |
|---|---|---|
| [04-Migrate-SSRSPermissions.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/04-Migrate-SSRSPermissions.ps1) | Export/import SSRS policies (folder/report ACL) as JSON | Uses dynamic SOAP type instantiation, fragile across module versions. AD principals must already exist on the target. |
| [05-Migrate-SSRSDataSources.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/05-Migrate-SSRSDataSources.ps1) | Recreate shared data sources on the target with optional connection-string remap (CSV) | Stored credentials cannot be exported in clear text. Datasources using Store mode must be re-authenticated manually after import. |
| [06-Migrate-SSRSReports.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/06-Migrate-SSRSReports.ps1) | Download / upload of the full folder tree | Download/upload primitives are reliable. The optional -RebindDataSources switch is approximate and should not be relied upon: rebinding is best done manually in the Web Portal. |
| [07-Migrate-SSRSSubscriptions.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/07-Migrate-SSRSSubscriptions.ps1) | Export subscriptions to JSON and re-import on the target | Highest risk. The JSON round-trip via Get-RsSubscription / Set-RsSubscription is not officially supported and may fail on complex subscriptions (data-driven, file share delivery, custom delivery extensions). For production, prefer letting the database restore handle the subscriptions. |
| [09-Switch-SSRSProduction.ps1](https://github.com/JulienPIERRE94/CA-GIP-ReportServer/blob/main/scripts/ssrs/09-Switch-SSRSProduction.ps1) | Disable old subs, switch DNS, enable new subs, send the comm e-mail | DNS scripting depends on the local DNS server type (Microsoft DNS / Infoblox / Azure DNS). Treat the DNS step as a template and replace it with the procedure aligned with your infra team. |

If you decide to use any of these scripts, the recommended approach is:

1. Restore a non-production copy of the ReportServer database somewhere (it gives you a safe target to write to).
2. Run the optional script in -WhatIf mode first.
3. Validate the result via the Web Portal and the audit script (step 1).
4. Iterate.

For a clean-install scenario in production, an alternative that is more reliable than the optional scripts above is to use RDL/RSDS file deployment (Visual Studio / rs.exe deployment scripts) for reports, and to recreate datasources and subscriptions through the Web Portal.

The author can produce a more focused script set on request once the exact migration scenario is confirmed.
