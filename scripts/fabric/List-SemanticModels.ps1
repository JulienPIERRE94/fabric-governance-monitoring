$fabToken = (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
$h = @{ Authorization = "Bearer $fabToken" }
$wsI = "cbc321b0-5e65-41c1-a98c-eea5781305b7"

$items = Invoke-RestMethod -Uri ("https://api.fabric.microsoft.com/v1/workspaces/" + $wsI + "/semanticModels") -Headers $h
Write-Host "Semantic Models in WS-Insurance:"
$items.value | ForEach-Object { Write-Host ("  " + $_.displayName + " -> " + $_.id) }
