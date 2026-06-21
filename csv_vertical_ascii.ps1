# csv_vertical_ascii.ps1
#
# CSVファイルを縦方向に読みやすく表示する補助ツール。
#
# Author: Tatsumi Mashimo
# Repository: https://github.com/t-mashimo/egov-social-insurance-zip-organizer
# License: MIT
#
# This script is provided as-is, without warranty of any kind.

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$CsvPath
)

Write-Host "CsvPath=[$CsvPath]"

if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
    Write-Host "CSV file not found."
    Write-Host "Received path: [$CsvPath]"
    exit 1
}

function Get-TextEncoding([string]$Path) {
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $bom = New-Object byte[] 4
        [void]$fs.Read($bom,0,4)
        if ($bom[0] -eq 0xEF -and $bom[1] -eq 0xBB -and $bom[2] -eq 0xBF) { return [System.Text.Encoding]::UTF8 }
        if ($bom[0] -eq 0xFF -and $bom[1] -eq 0xFE) { return [System.Text.Encoding]::Unicode }
        if ($bom[0] -eq 0xFE -and $bom[1] -eq 0xFF) { return [System.Text.Encoding]::BigEndianUnicode }
        return [System.Text.Encoding]::GetEncoding(932)
    } finally {
        $fs.Close()
    }
}

$enc = Get-TextEncoding $CsvPath

try {
    $reader = New-Object System.IO.StreamReader($CsvPath, $enc)
    $csvText = $reader.ReadToEnd()
    $reader.Close()
} catch {
    Write-Host "Failed to read CSV."
    Write-Host $_.Exception.Message
    exit 1
}

if ([string]::IsNullOrWhiteSpace($csvText)) {
    Write-Host "CSV is empty."
    exit 1
}

try {
    $csvData = $csvText | ConvertFrom-Csv
} catch {
    Write-Host "Failed to parse CSV."
    Write-Host $_.Exception.Message
    exit 1
}

if (-not $csvData) {
    Write-Host "No CSV rows found."
    exit 1
}

$row = $csvData[0]
$outfile = [System.IO.Path]::ChangeExtension($CsvPath, ".vertical.txt")

$result = New-Object System.Collections.Generic.List[string]
foreach ($prop in $row.PSObject.Properties) {
    $result.Add(("[{0}]`t{1}" -f $prop.Name, $prop.Value))
}

$result | Out-File -LiteralPath $outfile -Encoding UTF8
Write-Host "Output: $outfile"
Start-Process notepad.exe -ArgumentList $outfile
