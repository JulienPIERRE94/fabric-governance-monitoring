# Dupliquer ce fichier en ssrs-config.ps1 (non versionné) et personnaliser les valeurs.
# Usage : . .\scripts\ssrs\ssrs-config.ps1

$SsrsConfig = @{
    OldReportServerUri = "http://OLD-SSRS/ReportServer"
    NewReportServerUri = "http://NEW-SSRS/ReportServer"
    OldSqlInstance     = "OLD-SQL01"
    NewSqlInstance     = "NEW-SQL01"
    BackupFolder       = "\\BACKUP\SSRS"
    OutputFolder       = ".\out\ssrs"
    DnsRecord          = "ssrs.entreprise.local"
    NewIp              = "10.20.30.40"
    SmtpServer         = "smtp.entreprise.local"
    CommRecipients     = @("bi-users@entreprise.local")
}
