$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$mdPath   = Join-Path $repoRoot 'docs\Guide_Gouvernance_PBIRS_vs_PowerBIService.md'
$docxPath = Join-Path $repoRoot 'docs\Guide_Gouvernance_PBIRS_vs_PowerBIService.docx'

$lines = Get-Content -Path $mdPath -Encoding UTF8

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$doc = $word.Documents.Add()
$sel = $word.Selection

function Write-Line {
    param(
        [string]$Text,
        [int]$Size = 11,
        [bool]$Bold = $false
    )

    $sel.Font.Name = 'Calibri'
    $sel.Font.Size = $Size
    $sel.Font.Bold = $Bold
    $sel.TypeText($Text)
    $sel.TypeParagraph()
}

foreach ($raw in $lines) {
    $line = $raw.TrimEnd()

    if ($line -match '^#\s+(.+)$') { Write-Line -Text $Matches[1] -Size 20 -Bold $true; continue }
    if ($line -match '^##\s+(.+)$') { Write-Line -Text $Matches[1] -Size 14 -Bold $true; continue }
    if ($line -match '^###\s+(.+)$') { Write-Line -Text $Matches[1] -Size 12 -Bold $true; continue }
    if ($line -match '^---\s*$') { Write-Line -Text ''; continue }
    if ($line -match '^\|') { Write-Line -Text $line -Size 10; continue }
    if ($line -match '^>\s*(.+)$') { Write-Line -Text ('Note : ' + $Matches[1]); continue }
    if ($line -match '^\s*[-*]\s+(.+)$') { Write-Line -Text ('• ' + $Matches[1]); continue }

    $plain = $line -replace '\*\*','' -replace '`',''
    Write-Line -Text $plain
}

$doc.SaveAs2($docxPath)
$doc.Close()
$word.Quit()

Write-Host "DOCX généré : $docxPath"
