# Génère le Word de l'architecture Cross-Domain Data Sharing

$mdPath   = 'C:\Users\Julien.SQL2022\Desktop\CA\CA-GIP\docs\Architecture_CrossDomain_DataSharing.md'
$docxPath = 'C:\Users\Julien.SQL2022\Desktop\CA\CA-GIP\docs\Architecture_CrossDomain_DataSharing.docx'

$lines = Get-Content -Path $mdPath -Encoding UTF8

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$doc  = $word.Documents.Add()
$sel  = $word.Selection

# Style de page
$doc.PageSetup.TopMargin    = $word.CentimetersToPoints(2.5)
$doc.PageSetup.BottomMargin = $word.CentimetersToPoints(2.5)
$doc.PageSetup.LeftMargin   = $word.CentimetersToPoints(2.5)
$doc.PageSetup.RightMargin  = $word.CentimetersToPoints(2.5)

function Set-Text {
    param([string]$Text, [int]$Size=11, [bool]$Bold=$false, [string]$Font='Calibri',
          [string]$Color='000000', [bool]$Italic=$false)
    $sel.Font.Name  = $Font
    $sel.Font.Size  = $Size
    $sel.Font.Bold  = $Bold
    $sel.Font.Italic = $Italic
    $sel.Font.Color = [int]('0x' + $Color) -bor 0
    $sel.TypeText($Text)
    $sel.TypeParagraph()
    $sel.Font.Bold   = $false
    $sel.Font.Italic = $false
    $sel.Font.Color  = 0
}

function Add-HRule {
    $sel.TypeText("_" * 80)
    $sel.TypeParagraph()
}

$inCode  = $false
$inTable = $false

foreach ($raw in $lines) {
    $line = $raw.TrimEnd()

    # Bloc code
    if ($line -match '^```') {
        $inCode = -not $inCode
        if (-not $inCode) { $sel.TypeParagraph() }
        continue
    }
    if ($inCode) {
        Set-Text -Text $line -Size 9 -Font 'Consolas' -Color '2E4053'
        continue
    }

    # Titres
    if ($line -match '^# (.+)$') {
        $sel.TypeParagraph()
        Set-Text -Text $Matches[1] -Size 22 -Bold $true -Color '1F3864'
        Set-Text -Text '' -Size 6
        continue
    }
    if ($line -match '^## (.+)$') {
        $sel.TypeParagraph()
        Set-Text -Text $Matches[1] -Size 15 -Bold $true -Color '2E75B6'
        continue
    }
    if ($line -match '^### (.+)$') {
        Set-Text -Text $Matches[1] -Size 12 -Bold $true -Color '2E75B6'
        continue
    }
    if ($line -match '^#### (.+)$') {
        Set-Text -Text $Matches[1] -Size 11 -Bold $true
        continue
    }

    # Séparateur
    if ($line -match '^---\s*$') {
        Add-HRule
        continue
    }

    # Ligne de tableau
    if ($line -match '^\|') {
        # Ignore les lignes séparateurs |---|
        if ($line -match '^\|[\s\-\|:]+\|$') { continue }
        $cells = $line -split '\|' | Where-Object { $_ -ne '' } | ForEach-Object { $_.Trim() }
        $row = $cells -join '   |   '
        Set-Text -Text ('| ' + $row + ' |') -Size 9 -Font 'Consolas'
        continue
    }

    # Listes à puces
    if ($line -match '^\s*[-*]\s+(.+)$') {
        $txt = $Matches[1] -replace '\*\*(.+?)\*\*','$1' -replace '`(.+?)`','$1'
        Set-Text -Text ('  •  ' + $txt) -Size 11
        continue
    }

    # Texte gras inline -> simplifié
    if ($line -match '\*\*') {
        $plain = $line -replace '\*\*(.+?)\*\*','$1' -replace '`(.+?)`','$1' -replace '\[(.+?)\]\(.+?\)','$1'
        Set-Text -Text $plain -Size 11
        continue
    }

    # Ligne vide
    if ($line -eq '') {
        $sel.TypeParagraph()
        continue
    }

    # Texte normal
    $plain = $line -replace '`(.+?)`','$1' -replace '\[(.+?)\]\(.+?\)','$1'
    Set-Text -Text $plain -Size 11
}

$doc.SaveAs2($docxPath)
$doc.Close()
$word.Quit()

Write-Host "✅ Word généré : $docxPath"
