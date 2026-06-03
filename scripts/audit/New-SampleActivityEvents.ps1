<#
Génère un CSV d'exemple PowerBI_ActivityEvents_Sample.csv compatible avec le modèle Power BI.
Utile pour démonstration en l'absence d'accès tenant.
#>

param(
    [Parameter(Mandatory = $false)]
    [int]$Days = 7,

    [Parameter(Mandatory = $false)]
    [int]$EventsPerDay = 250,

    [Parameter(Mandatory = $false)]
    [string]$OutputCsv = ".\PowerBI_ActivityEvents_Sample.csv"
)

$operations = @(
    @{ Name = 'ViewReport';        Cat = 'Consultation' },
    @{ Name = 'ViewDashboard';     Cat = 'Consultation' },
    @{ Name = 'GetDatasets';       Cat = 'API Read' },
    @{ Name = 'GetReports';        Cat = 'API Read' },
    @{ Name = 'GetWorkspaces';     Cat = 'API Read' },
    @{ Name = 'RefreshDataset';    Cat = 'Refresh' },
    @{ Name = 'ExportReport';      Cat = 'Export' },
    @{ Name = 'CreateDataset';     Cat = 'API Write' },
    @{ Name = 'UpdateDataset';     Cat = 'API Write' },
    @{ Name = 'DeleteReport';      Cat = 'API Write' }
)

$users = @(
    'alice@contoso.com',
    'bob@contoso.com',
    'charlie@contoso.com',
    'diane@contoso.com',
    'erwan@contoso.com',
    'sp-monitoring@contoso.com',
    'sp-etl@contoso.com'
)

$workspaces = @(
    @{ Id = 'WS001'; Name = 'Finance' },
    @{ Id = 'WS002'; Name = 'Ventes' },
    @{ Id = 'WS003'; Name = 'RH' },
    @{ Id = 'WS004'; Name = 'Production' },
    @{ Id = 'WS005'; Name = 'Marketing' }
)

$capacities = @(
    @{ Id = 'CAP001'; Name = 'F64-Prod' },
    @{ Id = 'CAP002'; Name = 'F32-Dev' }
)

$datasets = 1..15 | ForEach-Object { @{ Id = "DS$($_.ToString('000'))"; Name = "Dataset_$_" } }
$reports  = 1..25 | ForEach-Object { @{ Id = "RP$($_.ToString('000'))"; Name = "Report_$_" } }

$rows = New-Object System.Collections.Generic.List[Object]
$rand = New-Object System.Random

for ($d = 1; $d -le $Days; $d++) {
    $day = (Get-Date).AddDays(-$d).Date
    $count = $EventsPerDay + $rand.Next(-50, 80)

    for ($i = 0; $i -lt $count; $i++) {
        $hour = $rand.Next(7, 20)
        $min = $rand.Next(0, 60)
        $sec = $rand.Next(0, 60)
        $time = $day.AddHours($hour).AddMinutes($min).AddSeconds($sec)

        $op = $operations | Get-Random
        $user = $users | Get-Random
        $ws = $workspaces | Get-Random
        $cap = $capacities | Get-Random
        $ds = $datasets | Get-Random
        $rp = $reports | Get-Random

        $userType = if ($user -like 'sp-*') { 'ServicePrincipal' } else { 'Regular' }
        $isSuccess = ($rand.Next(0, 100) -lt 95)

        $rows.Add([PSCustomObject]@{
            Id                  = [guid]::NewGuid().ToString()
            CreationTime        = $time.ToString('yyyy-MM-ddTHH:mm:ss')
            Operation           = $op.Name
            UserId              = $user
            UserType            = $userType
            UserKey             = $user
            Activity            = $op.Name
            ItemName            = $rp.Name
            WorkSpaceName       = $ws.Name
            WorkspaceId         = $ws.Id
            ObjectId            = $rp.Id
            DatasetName         = $ds.Name
            DatasetId           = $ds.Id
            ReportName          = $rp.Name
            ReportId            = $rp.Id
            ReportType          = 'PowerBIReport'
            CapacityId          = $cap.Id
            CapacityName        = $cap.Name
            ClientIP            = "10.0.$($rand.Next(0,255)).$($rand.Next(1,254))"
            UserAgent           = 'Mozilla/5.0'
            IsSuccess           = $isSuccess
            RequestId           = [guid]::NewGuid().ToString()
            ActivityId          = [guid]::NewGuid().ToString()
            DistributionMethod  = 'Workspace'
            ConsumptionMethod   = 'PowerBI Web'
        }) | Out-Null
    }
}

$rows | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8 -Delimiter ';'

Write-Host "Échantillon généré : $OutputCsv"
Write-Host "Lignes : $($rows.Count)"
