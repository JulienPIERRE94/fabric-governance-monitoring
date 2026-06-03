$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$mdPath   = Join-Path $repoRoot 'docs\Guide_Migration_SSRS_EN.md'
$docxPath = Join-Path $repoRoot 'docs\Guide_Migration_SSRS_EN.docx'

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

$inCode = $false
foreach ($raw in $lines) {
    $line = $raw.TrimEnd()

    if ($line -match '^```') { $inCode = -not $inCode; Write-Line -Text ''; continue }
    if ($inCode)              { Write-Line -Text $line -Size 10; continue }

    if ($line -match '^#\s+(.+)$')   { Write-Line -Text $Matches[1] -Size 20 -Bold $true; continue }
    if ($line -match '^##\s+(.+)$')  { Write-Line -Text $Matches[1] -Size 14 -Bold $true; continue }
    if ($line -match '^###\s+(.+)$') { Write-Line -Text $Matches[1] -Size 12 -Bold $true; continue }
    if ($line -match '^---\s*$')     { Write-Line -Text ''; continue }
    if ($line -match '^\|')          { Write-Line -Text $line -Size 10; continue }
    if ($line -match '^>\s*(.+)$')   { Write-Line -Text ('Note: ' + $Matches[1]); continue }
    if ($line -match '^\s*[-*]\s+(.+)$') { Write-Line -Text ('• ' + $Matches[1]); continue }

    $plain = $line -replace '\*\*','' -replace '`',''
    Write-Line -Text $plain
}

# Convert plain-text URLs into clickable hyperlinks
$urlPattern = 'https?://[^\s)]+'

$fullText = $doc.Content.Text
$regex = [regex]$urlPattern
$urlMatches = $regex.Matches($fullText)
foreach ($m in ($urlMatches | Sort-Object Index -Descending)) {
    $start = $m.Index
    $end   = $m.Index + $m.Length
    $linkRange = $doc.Range($start, $end)
    try {
        $null = $doc.Hyperlinks.Add($linkRange, $m.Value, $null, $null, $m.Value)
    } catch {
        Write-Warning "Hyperlink KO for $($m.Value): $_"
    }
}

$doc.SaveAs2($docxPath)
$doc.Close()
$word.Quit()

[System.Runtime.InteropServices.Marshal]::ReleaseComObject($sel)  | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc)  | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null

Write-Host "DOCX generated: $docxPath"
