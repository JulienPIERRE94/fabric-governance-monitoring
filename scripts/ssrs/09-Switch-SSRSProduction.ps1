<#
.SYNOPSIS
    [OPTIONAL / EXAMPLE] Cutover SSRS automatisé : désactivation ancienne instance,
    bascule DNS, activation nouvelle instance et communication aux utilisateurs.

.DESCRIPTION
    ⚠️ Ce script est fourni à titre d'EXEMPLE. Le cutover en production doit
    être piloté manuellement via la check-list de l'étape 5 du guide, en
    coordination avec les équipes Réseau / DNS / Production.

    La partie DNS suppose un serveur DNS Microsoft accessible via
    DnsServer module. Adapter (ou retirer) si le DNS est géré par Infoblox,
    Azure DNS ou autre.

    À tester impérativement sur un environnement de non-production avant tout
    usage en production.

    Étape 9 du guide (optionnelle / exemple).

.PARAMETER OldUri
    URL Web Service de l'ancienne instance (utilisée pour désactiver les souscriptions).

.PARAMETER NewUri
    URL Web Service de la nouvelle instance (utilisée pour réactivation).

.PARAMETER DnsRecord
    Enregistrement DNS A à modifier (ex. ssrs.entreprise.local).

.PARAMETER NewIp
    Nouvelle IP cible (ou IP du nouveau serveur SSRS).

.PARAMETER DnsZone
    Zone DNS contenant l'enregistrement (ex. entreprise.local).

.PARAMETER DnsServer
    Serveur DNS sur lequel exécuter Set-DnsServerResourceRecord.

.PARAMETER SmtpServer
    Serveur SMTP pour la communication.

.PARAMETER CommRecipients
    Destinataires du mail de communication.

.PARAMETER CommFrom
    Émetteur du mail.

.EXAMPLE
    .\09-Switch-SSRSProduction.ps1 -OldUri "http://OLD-SSRS/ReportServer" `
        -NewUri "http://NEW-SSRS/ReportServer" `
        -DnsRecord "ssrs" -DnsZone "entreprise.local" -DnsServer "DC01" -NewIp "10.20.30.40" `
        -SmtpServer "smtp.entreprise.local" -CommFrom "bi@entreprise.local" `
        -CommRecipients "bi-users@entreprise.local" -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]  [string] $OldUri,
    [Parameter(Mandatory = $true)]  [string] $NewUri,
    [Parameter(Mandatory = $true)]  [string] $DnsRecord,
    [Parameter(Mandatory = $true)]  [string] $DnsZone,
    [Parameter(Mandatory = $true)]  [string] $DnsServer,
    [Parameter(Mandatory = $true)]  [string] $NewIp,
    [Parameter(Mandatory = $false)] [string] $SmtpServer,
    [Parameter(Mandatory = $false)] [string] $CommFrom = "bi@entreprise.local",
    [Parameter(Mandatory = $false)] [string[]] $CommRecipients
)

$ErrorActionPreference = 'Stop'
Import-Module ReportingServicesTools

function Set-AllSubscriptionsState {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$Uri, [bool]$Enable)

    $proxy = New-RsWebServiceProxy -ReportServerUri $Uri
    $reports = $proxy.ListChildren("/", $true) | Where-Object { $_.TypeName -eq 'Report' }
    foreach ($r in $reports) {
        try {
            $subs = $proxy.ListSubscriptions($r.Path)
            foreach ($s in $subs) {
                if ($Enable) {
                    if ($PSCmdlet.ShouldProcess("$($r.Path) [$($s.SubscriptionID)]", "EnableSubscription")) {
                        $proxy.EnableSubscription($s.SubscriptionID)
                    }
                } else {
                    if ($PSCmdlet.ShouldProcess("$($r.Path) [$($s.SubscriptionID)]", "DisableSubscription")) {
                        $proxy.DisableSubscription($s.SubscriptionID)
                    }
                }
            }
        } catch { Write-Warning "Subscription state KO sur $($r.Path) : $_" }
    }
}

# 1. Désactivation des souscriptions sur l'ancien serveur
Write-Host "[1/4] Désactivation des souscriptions sur l'ancienne instance..." -ForegroundColor Cyan
Set-AllSubscriptionsState -Uri $OldUri -Enable:$false

# 2. Bascule DNS
Write-Host "[2/4] Bascule DNS $DnsRecord.$DnsZone -> $NewIp" -ForegroundColor Cyan
if ($PSCmdlet.ShouldProcess("$DnsRecord.$DnsZone", "Set-DnsServerResourceRecord")) {
    try {
        $old = Get-DnsServerResourceRecord -ComputerName $DnsServer -ZoneName $DnsZone -Name $DnsRecord -RRType A -ErrorAction Stop
        $new = [ciminstance]::new($old)
        $new.RecordData.IPv4Address = [ipaddress]$NewIp
        Set-DnsServerResourceRecord -ComputerName $DnsServer -ZoneName $DnsZone -OldInputObject $old -NewInputObject $new
    } catch {
        Write-Warning "Bascule DNS KO ($_). À effectuer manuellement."
    }
}

# 3. Activation des souscriptions sur le nouveau serveur
Write-Host "[3/4] Activation des souscriptions sur la nouvelle instance..." -ForegroundColor Cyan
Set-AllSubscriptionsState -Uri $NewUri -Enable:$true

# 4. Communication
Write-Host "[4/4] Envoi du mail de communication..." -ForegroundColor Cyan
if ($SmtpServer -and $CommRecipients) {
    $body = @"
Bonjour,

La migration de l'instance SQL Server Reporting Services a été effectuée ce jour.

- Ancien portail : $OldUri (sera maintenu en lecture seule pendant 30 jours)
- Nouveau portail : $NewUri
- Adresse stable (DNS) : http://$DnsRecord.$DnsZone/Reports

Vos rapports, abonnements et accès ont été migrés à l'identique.
Merci de signaler tout dysfonctionnement à l'équipe BI.

Cordialement,
L'équipe BI / Gouvernance
"@
    if ($PSCmdlet.ShouldProcess("$($CommRecipients -join ', ')", "Send-MailMessage")) {
        Send-MailMessage -SmtpServer $SmtpServer -From $CommFrom -To $CommRecipients `
            -Subject "[INFO] Migration SSRS effectuée" -Body $body -Encoding utf8
    }
} else {
    Write-Warning "SmtpServer/CommRecipients non fourni : pas d'envoi de mail."
}

Write-Host "Cutover terminé. Démarrer la surveillance post-migration (ExecutionLog3)." -ForegroundColor Green
