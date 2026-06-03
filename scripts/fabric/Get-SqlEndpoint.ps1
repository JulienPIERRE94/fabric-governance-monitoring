$fabToken = (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
$h = @{ Authorization = "Bearer $fabToken" }

$wsI = "cbc321b0-5e65-41c1-a98c-eea5781305b7"
$lhI = "317f23e4-0dd7-4ace-9780-2c81c342bd5a"

$lh = Invoke-RestMethod -Uri ("https://api.fabric.microsoft.com/v1/workspaces/" + $wsI + "/lakehouses/" + $lhI) -Headers $h
Write-Host ("SQL Endpoint server  : " + $lh.properties.sqlEndpointProperties.connectionString)
Write-Host ("SQL Endpoint DB      : " + $lh.properties.sqlEndpointProperties.id)
Write-Host ("provisioningStatus   : " + $lh.properties.sqlEndpointProperties.provisioningStatus)
$lh | ConvertTo-Json -Depth 6
