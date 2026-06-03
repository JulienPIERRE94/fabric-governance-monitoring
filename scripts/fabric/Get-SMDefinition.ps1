$fabToken = (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
$h = @{ Authorization = "Bearer $fabToken"; "Content-Type" = "application/json" }
$wsI  = "cbc321b0-5e65-41c1-a98c-eea5781305b7"
$smId = "5809e89f-eb8c-4cc1-b7a9-bf95809f5b62"

Write-Host "Getting definition of SEM_Insurance..."
try {
    $resp = Invoke-WebRequest -Method POST `
        -Uri ("https://api.fabric.microsoft.com/v1/workspaces/" + $wsI + "/semanticModels/" + $smId + "/getDefinition") `
        -Headers $h -Body "{}" -UseBasicParsing
    Write-Host ("HTTP " + $resp.StatusCode)
    $loc = $resp.Headers["Location"]
    if ($loc) {
        Write-Host ("Async Location: " + $loc)
        Start-Sleep 10
        $op = Invoke-RestMethod -Uri $loc -Headers @{ Authorization = "Bearer $fabToken" }
        Write-Host ("Op status: " + $op.status)
        # Try fetching result from /result endpoint
        $resultUrl = $loc + "/result"
        Write-Host ("Fetching result from: " + $resultUrl)
        $result = Invoke-RestMethod -Uri $resultUrl -Headers @{ Authorization = "Bearer $fabToken" }
        Write-Host "Result:"
        $result | ConvertTo-Json -Depth 8
        $r = $result.definition
    } else {
        $r = ($resp.Content | ConvertFrom-Json).definition
    }
    if ($r) {
        $r.parts | ForEach-Object {
            Write-Host ("--- Part: " + $_.path + " ---")
            if ($_.payload) {
                $dec = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_.payload))
                Write-Host $dec
            }
        }
    }
} catch {
    $r2 = $_.Exception.Response
    if ($r2) {
        $rd = New-Object System.IO.StreamReader($r2.GetResponseStream())
        Write-Host ("Error: " + $rd.ReadToEnd())
    } else {
        Write-Host ("Error: " + $_.Exception.Message)
    }
}
