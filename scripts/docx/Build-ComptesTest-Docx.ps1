# Génère le Word des comptes de test

$mdPath   = 'C:\Users\Julien.SQL2022\Desktop\CA\CA-GIP\docs\Comptes_Test_RLS.md'
$docxPath = 'C:\Users\Julien.SQL2022\Desktop\CA\CA-GIP\docs\Comptes_Test_RLS.docx'

$lines = Get-Content -Path $mdPath -Encoding UTF8

$word = New-Object -ComObject Word.Application
$word.Visible = $false
$doc  = $word.Documents.Add()
$sel  = $word.Selection

$doc.PageSetup.TopMargin    = $word.CentimetersToPoints(2.5)
$doc.PageSetup.BottomMargin = $word.CentimetersToPoints(2.5)
$doc.PageSetup.LeftMargin   = $word.CentimetersToPoints(2.5)
$doc.PageSetup.RightMargin  = $word.CentimetersToPoints(2.5)

function W { param([string]$t,[int]$s=11,[bool]$b=$false,[string]$f='Calibri',[string]$c='000000')
    $sel.Font.Name=$f; $sel.Font.Size=$s; $sel.Font.Bold=$b
    $sel.Font.Color=[Convert]::ToInt32($c,16)
    $sel.TypeText($t); $sel.TypeParagraph()
    $sel.Font.Bold=$false; $sel.Font.Color=0
}

$inCode = $false
foreach ($raw in $lines) {
    $line = $raw.TrimEnd()
    if ($line -match '^```') { $inCode=-not $inCode; continue }
    if ($inCode)             { W $line 9 $false 'Consolas' '2E4053'; continue }

    switch -Regex ($line) {
        '^# (.+)'    { W $Matches[1] 20 $true  'Calibri' '1F3864'; continue }
        '^## (.+)'   { $sel.TypeParagraph(); W $Matches[1] 14 $true 'Calibri' '2E75B6'; continue }
        '^### (.+)'  { W $Matches[1] 12 $true  'Calibri' '2E75B6'; continue }
        '^---\s*$'   { W ('─' * 80) 9; continue }
        '^\|[-:\s\|]+\|$' { continue }  # ligne séparateur tableau
        '^\|'        {
            $cells = $line -split '\|' | Where-Object {$_ -ne ''} | ForEach-Object {$_.Trim() -replace '\*\*(.+?)\*\*','$1' -replace '`(.+?)`','$1'}
            W ($cells -join '   |   ') 9 $false 'Consolas'
            continue
        }
        '^\s*[-*] (.+)' { W ('  •  ' + ($Matches[1] -replace '\*\*(.+?)\*\*','$1' -replace '`(.+?)`','$1')); continue }
        '^$'         { $sel.TypeParagraph(); continue }
        default      {
            $t = $line -replace '\*\*(.+?)\*\*','$1' -replace '`(.+?)`','$1' -replace '\[(.+?)\]\(.+?\)','$1'
            W $t
        }
    }
}

$doc.SaveAs2($docxPath)
$doc.Close()
$word.Quit()
Write-Host "OK : $docxPath"
