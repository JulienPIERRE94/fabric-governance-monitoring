# Vérifie les rôles RLS actuels de SEM_Insurance

$fabToken = (& az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv)
$h = @{ Authorization = "Bearer $fabToken"; "Content-Type" = "application/json" }
$wsI  = "cbc321b0-5e65-41c1-a98c-eea5781305b7"
$smId = "5809e89f-eb8c-4cc1-b7a9-bf95809f5b62"

# Lancer getDefinition (async)
$req = Invoke-WebRequest -Method POST `
    -Uri "https://api.fabric.microsoft.com/v1/workspaces/$wsI/semanticModels/$smId/getDefinition" `
    -Headers $h -Body '{"format":"TMDL"}' -UseBasicParsing

Write-Host "HTTP $($req.StatusCode)"
$opUrl = ($req.Headers["Location"] | Select-Object -First 1)
Write-Host "Op: $opUrl"

# Polling
$elapsed = 0
do {
    Start-Sleep 8; $elapsed += 8
    $op = Invoke-RestMethod -Uri $opUrl -Headers @{ Authorization = "Bearer $fabToken" }
    Write-Host "[$elapsed s] $($op.status)"
    if ($op.status -in @("Succeeded","Failed","Cancelled")) { break }
} while ($elapsed -lt 60)

if ($op.status -ne "Succeeded") {
    Write-Host "Echec: $($op.error | ConvertTo-Json)"
    exit 1
}

# Récupérer le résultat
$result = Invoke-RestMethod -Uri ($opUrl + "/result") -Headers @{ Authorization = "Bearer $fabToken" }
$parts  = $result.definition.parts

Write-Host "`n=== Parts ($($parts.Count)) ==="
$parts | ForEach-Object { Write-Host "  $($_.path)" }

Write-Host "`n=== Rôles ==="
$roles = $parts | Where-Object { $_.path -like "*/roles/*" }
if ($roles.Count -eq 0) {
    Write-Host "  ⚠️  Aucun rôle trouvé !"
} else {
    foreach ($r in $roles) {
        Write-Host "`n  --- $($r.path) ---"
        [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($r.payload))
    }
}

Write-Host "`n=== model.tmdl (refs roles) ==="
$mdl = $parts | Where-Object { $_.path -eq "definition/model.tmdl" }
[System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($mdl.payload))
