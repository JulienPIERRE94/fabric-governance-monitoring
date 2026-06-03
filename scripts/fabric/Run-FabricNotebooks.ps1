$fabToken = (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
$h        = @{ Authorization = "Bearer $fabToken" }
$wsB      = "5015e396-cb2d-4fbe-8ebf-c87544cf6bfd"
$wsI      = "cbc321b0-5e65-41c1-a98c-eea5781305b7"

$nbsB = (Invoke-RestMethod -Uri ("https://api.fabric.microsoft.com/v1/workspaces/" + $wsB + "/notebooks") -Headers $h).value
$nbsI = (Invoke-RestMethod -Uri ("https://api.fabric.microsoft.com/v1/workspaces/" + $wsI + "/notebooks") -Headers $h).value

Write-Host "=== Banking notebooks ==="
$nbsB | ForEach-Object { Write-Host ($_.displayName + " -> " + $_.id) }

Write-Host "=== Insurance notebooks ==="
$nbsI | ForEach-Object { Write-Host ($_.displayName + " -> " + $_.id) }

$nbBId = ($nbsB | Where-Object { $_.displayName -eq "Load_Banking_Tables" }).id
$nbIId = ($nbsI | Where-Object { $_.displayName -eq "Load_Insurance_Tables" }).id

Write-Host ("Banking nb id   : " + $nbBId)
Write-Host ("Insurance nb id : " + $nbIId)

function Run-Nb {
    param([string]$WsId, [string]$NbId, [string]$Label)
    if (-not $NbId) { Write-Host ("SKIP " + $Label); return }
    Write-Host ("Running " + $Label + "...")
    $runBody = (@{ executionData = @{} } | ConvertTo-Json -Compress)
    $hPost   = @{ Authorization = "Bearer $fabToken"; "Content-Type" = "application/json" }
    try {
        $job   = Invoke-RestMethod -Method POST -Uri ("https://api.fabric.microsoft.com/v1/workspaces/" + $WsId + "/notebooks/" + $NbId + "/jobs/instances?jobType=RunNotebook") -Headers $hPost -Body $runBody
        $jobId = $job.id
        if (-not $jobId) { Write-Host "  Submitted async (no job id returned)"; return }
        $elapsed = 0
        do {
            Start-Sleep 15; $elapsed += 15
            $s = Invoke-RestMethod -Uri ("https://api.fabric.microsoft.com/v1/workspaces/" + $WsId + "/notebooks/" + $NbId + "/jobs/instances/" + $jobId) -Headers $h
            Write-Host ("  [" + $elapsed + "s] " + $s.status)
        } while ($s.status -notin @("Succeeded","Failed","Cancelled") -and $elapsed -lt 300)
        Write-Host ("  FINAL: " + $s.status)
    } catch {
        Write-Host ("  ERROR: " + $_.Exception.Message)
    }
}

Run-Nb -WsId $wsB -NbId $nbBId -Label "Load_Banking_Tables"
Run-Nb -WsId $wsI -NbId $nbIId -Label "Load_Insurance_Tables"

Write-Host "Done. Check Lakehouses for Delta tables."
