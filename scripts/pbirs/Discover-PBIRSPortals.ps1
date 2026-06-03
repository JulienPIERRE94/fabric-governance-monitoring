param(
    [Parameter(Mandatory = $false)]
    [string[]]$Servers,

    [Parameter(Mandatory = $false)]
    [string]$InputFile,

    [Parameter(Mandatory = $false)]
    [string]$OutputCsv = ".\PBIRS_Portals_Discovery.csv",

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSec = 8
)

function Get-ServerList {
    param(
        [string[]]$DirectServers,
        [string]$FilePath
    )

    $all = @()

    if ($DirectServers) {
        $all += $DirectServers
    }

    if ($FilePath -and (Test-Path $FilePath)) {
        $fromFile = Get-Content -Path $FilePath | Where-Object { $_ -and $_.Trim() -ne '' }
        $all += $fromFile
    }

    $all | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } | Sort-Object -Unique
}

function Test-PbirUrl {
    param(
        [string]$Url,
        [int]$Timeout
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $Timeout -Method Get -ErrorAction Stop
        $content = [string]$response.Content

        $isLikelyPbirs = $false
        if ($content -match 'Power BI Report Server' -or $content -match 'Report Server' -or $content -match 'pbirs') {
            $isLikelyPbirs = $true
        }

        [PSCustomObject]@{
            Url           = $Url
            Reachable     = $true
            HttpStatus    = [int]$response.StatusCode
            IsLikelyPBIRS = $isLikelyPbirs
            TitleMatch    = ($content -match '<title>')
            Error         = $null
        }
    }
    catch {
        $status = $null
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $status = [int]$_.Exception.Response.StatusCode
        }

        [PSCustomObject]@{
            Url           = $Url
            Reachable     = $false
            HttpStatus    = $status
            IsLikelyPBIRS = $false
            TitleMatch    = $false
            Error         = $_.Exception.Message
        }
    }
}

$serverList = Get-ServerList -DirectServers $Servers -FilePath $InputFile

if (-not $serverList -or $serverList.Count -eq 0) {
    Write-Error "Aucun serveur fourni. Utilisez -Servers ou -InputFile."
    exit 1
}

$paths = @('/reports', '/reportserver')
$schemes = @('https', 'http')

$results = foreach ($server in $serverList) {
    foreach ($scheme in $schemes) {
        foreach ($path in $paths) {
            $url = "{0}://{1}{2}" -f $scheme, $server, $path
            $test = Test-PbirUrl -Url $url -Timeout $TimeoutSec

            [PSCustomObject]@{
                Server        = $server
                Url           = $test.Url
                Reachable     = $test.Reachable
                HttpStatus    = $test.HttpStatus
                IsLikelyPBIRS = $test.IsLikelyPBIRS
                TitleMatch    = $test.TitleMatch
                Error         = $test.Error
                CheckedAt     = (Get-Date)
            }
        }
    }
}

$results | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8

$summary = $results | Where-Object { $_.Reachable -eq $true -and $_.IsLikelyPBIRS -eq $true }

Write-Host "Scan terminé. Résultats CSV : $OutputCsv"
Write-Host "Portails PBIRS probables détectés : $($summary.Count)"
$summary | Select-Object Server, Url, HttpStatus | Format-Table -AutoSize
