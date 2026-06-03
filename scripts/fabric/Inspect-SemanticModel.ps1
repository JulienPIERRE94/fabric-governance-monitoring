# Met à jour SEM_Insurance avec toutes les tables, relations, RLS et OLS

$fabToken = (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
$h = @{ Authorization = "Bearer $fabToken"; "Content-Type" = "application/json" }

$wsI  = "cbc321b0-5e65-41c1-a98c-eea5781305b7"
$smId = "5809e89f-eb8c-4cc1-b7a9-bf95809f5b62"  # SEM_Insurance
$lhI  = "317f23e4-0dd7-4ace-9780-2c81c342bd5a"

# Récupère la définition actuelle pour voir sa structure
Write-Host "Getting current definition..."
try {
    $defResp = Invoke-RestMethod -Method POST `
        -Uri ("https://api.fabric.microsoft.com/v1/workspaces/" + $wsI + "/semanticModels/" + $smId + "/getDefinition") `
        -Headers $h -Body "{}"
    $part = $defResp.definition.parts | Where-Object { $_.path -like "*.bim" -or $_.path -like "*.json" }
    if ($part) {
        $currentBim = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part.payload))
        Write-Host ("Current BIM path: " + $part.path)
        Write-Host ("Current BIM (first 300): " + $currentBim.Substring(0, [Math]::Min(300, $currentBim.Length)))
    } else {
        Write-Host "Parts found:"
        $defResp.definition.parts | ForEach-Object { Write-Host ("  path=" + $_.path + " payloadType=" + $_.payloadType) }
    }
} catch {
    $resp = $_.Exception.Response
    if ($resp) {
        $rd = New-Object System.IO.StreamReader($resp.GetResponseStream())
        Write-Host ("Error: " + $rd.ReadToEnd())
    } else {
        Write-Host ("Error: " + $_.Exception.Message)
    }
}
