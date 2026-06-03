$mdPath = 'c:\Users\Julien.SQL2022\Desktop\CA\CA-GIP\Demo_Monitoring_API_PowerBI_Fabric.md'
$docxPath = 'c:\Users\Julien.SQL2022\Desktop\CA\CA-GIP\Demo_Monitoring_API_PowerBI_Fabric.docx'

$lines = Get-Content -Path $mdPath -Encoding UTF8

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$doc = $word.Documents.Add()
$sel = $word.Selection

function Write-Line {
    param(
        [string]$Text,
        [int]$Size = 11,
        [bool]$Bold = $false,
        [string]$Font = 'Calibri'
    )
    $sel.Font.Name = $Font
    $sel.Font.Size = $Size
    $sel.Font.Bold = $Bold
    $sel.TypeText($Text)
    $sel.TypeParagraph()
}

$inCode = $false

foreach ($raw in $lines) {
    $line = $raw.TrimEnd()

    if ($line -match '^```') { $inCode = -not $inCode; Write-Line -Text ''; continue }
    if ($inCode) { Write-Line -Text $line -Size 9 -Font 'Consolas'; continue }

    if ($line -match '^#\s+(.+)$') { Write-Line -Text $Matches[1] -Size 20 -Bold $true; continue }
    if ($line -match '^##\s+(.+)$') { Write-Line -Text $Matches[1] -Size 14 -Bold $true; continue }
    if ($line -match '^###\s+(.+)$') { Write-Line -Text $Matches[1] -Size 12 -Bold $true; continue }
    if ($line -match '^---\s*$') { Write-Line -Text ''; continue }
    if ($line -match '^\|') { Write-Line -Text $line -Size 10; continue }
    if ($line -match '^\s*[-*]\s+(.+)$') { Write-Line -Text ('• ' + $Matches[1]); continue }

    $plain = $line -replace '\*\*','' -replace '`',''
    Write-Line -Text $plain
}

$doc.SaveAs2($docxPath)
$doc.Close()
$word.Quit()

Write-Host "DOCX généré : $docxPath"
