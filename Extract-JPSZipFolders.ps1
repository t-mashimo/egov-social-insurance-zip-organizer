# Extract-JPSZipFolders.ps1
# ZIP内の階層を調べ、条件に合うフォルダだけを展開する
#
# パターンごとに指定展開先を持つ。
# 指定展開先が存在し、書き込み可能ならそこへ展開。
# 存在しない、または書き込み不可なら Desktop へ展開。
# 展開が成功した場合、最後に展開先の親フォルダを Explorer で開く。

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ZipPath
)

$ErrorActionPreference = "Stop"

# ============================================================
# 設定：パターンごとの優先展開先
# ============================================================
# 必要に応じて変更してください。
# 例: "\\server\share\年金\被保険者データ"
# 例: "C:\APL\年金\被保険者データ"

$OutputPathPattern1 = "C:\APL\年金\被保険者データ"
$OutputPathPattern2 = "C:\APL\年金\納入告知額・領収済額通知"
$OutputPathPattern3 = "C:\APL\年金\社会保険料額情報"

# ============================================================

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-SafeFolderName {
    param([string]$Name)

    return ($Name -replace '[\\/:*?"<>|]', '').Trim()
}

function Test-WritableFolder {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $false
    }

    $testFile = Join-Path $Path ("write_test_{0}.tmp" -f ([guid]::NewGuid().ToString()))

    try {
        New-Item -ItemType File -Path $testFile -Force | Out-Null
        Remove-Item -LiteralPath $testFile -Force
        return $true
    }
    catch {
        return $false
    }
}

function Get-OutputRootPath {
    param(
        [string]$PreferredPath,
        [string]$PatternName
    )

    $desktopPath = [Environment]::GetFolderPath("Desktop")

    if (Test-WritableFolder -Path $PreferredPath) {
        return [pscustomobject]@{
            Path   = $PreferredPath
            Reason = "$PatternName の指定展開先を使用"
        }
    }

    return [pscustomobject]@{
        Path   = $desktopPath
        Reason = "$PatternName の指定展開先が存在しない、または書き込み不可のためDesktopを使用"
    }
}

function Get-UniqueFolderName {
    param(
        [string]$ParentPath,
        [string]$BaseName
    )

    $name = $BaseName
    $i = 2

    while (Test-Path -LiteralPath (Join-Path $ParentPath $name)) {
        $name = "$BaseName ($i)"
        $i++
    }

    return $name
}

function Get-EntryDirectory {
    param([string]$FullName)

    $normalized = $FullName -replace '\\', '/'

    if ($normalized.EndsWith('/')) {
        return $normalized.TrimEnd('/')
    }

    $idx = $normalized.LastIndexOf('/')

    if ($idx -lt 0) {
        return ""
    }

    return $normalized.Substring(0, $idx)
}

function Get-EntryFileName {
    param([string]$FullName)

    $normalized = $FullName -replace '\\', '/'

    if ($normalized.EndsWith('/')) {
        return ""
    }

    $idx = $normalized.LastIndexOf('/')

    if ($idx -lt 0) {
        return $normalized
    }

    return $normalized.Substring($idx + 1)
}

function Get-EntryBaseName {
    param([string]$FullName)

    $fileName = Get-EntryFileName $FullName
    return [System.IO.Path]::GetFileNameWithoutExtension($fileName)
}

function Read-ZipEntryXml {
    param(
        [System.IO.Compression.ZipArchiveEntry]$Entry
    )

    $stream = $null

    try {
        $stream = $Entry.Open()

        $xml = New-Object System.Xml.XmlDocument
        $xml.PreserveWhitespace = $false
        $xml.Load($stream)

        return $xml
    }
    finally {
        if ($stream) {
            $stream.Dispose()
        }
    }
}

function Extract-ZipDirectory {
    param(
        [System.IO.Compression.ZipArchive]$Archive,
        [string]$SourceDir,
        [string]$DestinationDir
    )

    $prefix = ""

    if ($SourceDir -ne "") {
        $prefix = $SourceDir.TrimEnd('/') + "/"
    }

    foreach ($entry in $Archive.Entries) {
        $entryName = $entry.FullName -replace '\\', '/'

        if ($entryName.EndsWith('/')) {
            continue
        }

        $isTarget = $false
        $relativeName = $null

        if ($SourceDir -eq "") {
            # ZIP直下の場合は直下のファイルだけ対象
            if ($entryName -notmatch '/') {
                $isTarget = $true
                $relativeName = $entryName
            }
        }
        else {
            if ($entryName.StartsWith($prefix)) {
                $isTarget = $true
                $relativeName = $entryName.Substring($prefix.Length)
            }
        }

        if (-not $isTarget) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($relativeName)) {
            continue
        }

        $relativePath = $relativeName -replace '/', [System.IO.Path]::DirectorySeparatorChar
        $destFile = Join-Path $DestinationDir $relativePath
        $destParent = Split-Path -Parent $destFile

        if (-not (Test-Path -LiteralPath $destParent)) {
            New-Item -ItemType Directory -Path $destParent -Force | Out-Null
        }

        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destFile, $true)
    }
}

function Confirm-And-Extract {
    param(
        [System.IO.Compression.ZipArchive]$Archive,
        [string]$SourceDir,
        [string]$NewFolderName,
        [string]$Reason,
        [string]$PreferredOutputPath
    )

    if ([string]::IsNullOrWhiteSpace($NewFolderName)) {
        Write-Host "  SKIP: 展開先フォルダ名が空です。" -ForegroundColor Yellow
        return [pscustomobject]@{
            Success    = $false
            ParentPath = $null
            DestDir    = $null
        }
    }

    $safeName = Get-SafeFolderName $NewFolderName

    if ([string]::IsNullOrWhiteSpace($safeName)) {
        Write-Host "  SKIP: 展開先フォルダ名が不正です。" -ForegroundColor Yellow
        return [pscustomobject]@{
            Success    = $false
            ParentPath = $null
            DestDir    = $null
        }
    }

    $outputInfo = Get-OutputRootPath -PreferredPath $PreferredOutputPath -PatternName $Reason
    $outputRoot = $outputInfo.Path

    $actualName = Get-UniqueFolderName -ParentPath $outputRoot -BaseName $safeName
    $destDir = Join-Path $outputRoot $actualName

    if ([string]::IsNullOrWhiteSpace($SourceDir)) {
        $displaySourceDir = "(ZIP直下)"
    }
    else {
        $displaySourceDir = $SourceDir
    }

    Write-Host ""
    Write-Host "[$Reason]"
    Write-Host "展開候補:"
    Write-Host "  ZIP内フォルダ: $displaySourceDir"
    Write-Host "  優先展開先  : $PreferredOutputPath"
    Write-Host "  実際の展開先: $destDir"
    Write-Host "  判定        : $($outputInfo.Reason)"

    if ($actualName -ne $safeName) {
        Write-Host "  ※同名フォルダがあるため、展開先名を変更します: $actualName"
    }

    Write-Host ""

    $answer = Read-Host "このフォルダを展開しますか？ y/N"

    if ($answer -notin @("y", "Y", "yes", "YES")) {
        Write-Host "  中止: $displaySourceDir"

        return [pscustomobject]@{
            Success    = $false
            ParentPath = $null
            DestDir    = $null
        }
    }

    try {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        Extract-ZipDirectory -Archive $Archive -SourceDir $SourceDir -DestinationDir $destDir
        Write-Host "  OK: $destDir" -ForegroundColor Green

        return [pscustomobject]@{
            Success    = $true
            ParentPath = $outputRoot
            DestDir    = $destDir
        }
    }
    catch {
        Write-Host "  NG: $displaySourceDir" -ForegroundColor Red
        Write-Host "      $($_.Exception.Message)" -ForegroundColor Red

        return [pscustomobject]@{
            Success    = $false
            ParentPath = $null
            DestDir    = $null
        }
    }
}

# ============================================================
# メイン処理
# ============================================================

if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
    Write-Host "ZIPファイルが見つかりません: $ZipPath" -ForegroundColor Red
    exit 1
}

if ([System.IO.Path]::GetExtension($ZipPath) -ne ".zip") {
    Write-Host "ZIPファイルではないようです: $ZipPath" -ForegroundColor Red
    exit 1
}

Write-Host "ZIP:"
Write-Host "  $ZipPath"
Write-Host ""
Write-Host "優先展開先:"
Write-Host "  パターン1 被保険者データ:"
Write-Host "    $OutputPathPattern1"
Write-Host "  パターン2 納入告知額・領収済額通知:"
Write-Host "    $OutputPathPattern2"
Write-Host "  パターン3 社会保険料額情報:"
Write-Host "    $OutputPathPattern3"
Write-Host ""

$archive = $null

try {
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)

    $fileEntries = @(
        $archive.Entries | Where-Object {
            -not ($_.FullName -replace '\\', '/').EndsWith("/")
        }
    )

    if ($fileEntries.Count -eq 0) {
        Write-Host "ZIP内にファイルがありません。"
        exit
    }

    # ZIP内の「フォルダ単位」でグループ化
    $groups = $fileEntries | Group-Object {
        Get-EntryDirectory $_.FullName
    }

    $matchedCount = 0
    $extractedCount = 0
    $openedParentPaths = @{}

    foreach ($group in $groups) {
        $dir = [string]$group.Name
        $entries = @($group.Group)

        if ([string]::IsNullOrWhiteSpace($dir)) {
            $displayDir = "(ZIP直下)"
        }
        else {
            $displayDir = $dir
        }

        Write-Host "確認中: $displayDir"

        # ------------------------------------------------------------
        # パターン2: 納入告知額・領収済額通知
        # 保険料納入告知額・領収済額通知書_*.xml
        # ------------------------------------------------------------
        $pattern2Xmls = @(
            $entries | Where-Object {
                $name = Get-EntryFileName $_.FullName
                $name -like "保険料納入告知額・領収済額通知書_*.xml"
            }
        )

        if ($pattern2Xmls.Count -gt 1) {
            Write-Host "  SKIP: パターン2のXMLが複数あります。" -ForegroundColor Yellow
            $pattern2Xmls | ForEach-Object {
                Write-Host "    $(Get-EntryFileName $_.FullName)"
            }
            continue
        }

        if ($pattern2Xmls.Count -eq 1) {
            $fileName = Get-EntryBaseName $pattern2Xmls[0].FullName

            if ($fileName -match '^保険料納入告知額・領収済額通知書_(.+?)\(') {
                $part = $Matches[1]
                $newFolderName = "${part}納入告知額・領収済額通知"

                $matchedCount++

                $done = Confirm-And-Extract `
                    -Archive $archive `
                    -SourceDir $dir `
                    -NewFolderName $newFolderName `
                    -Reason "パターン2: 納入告知額・領収済額通知" `
                    -PreferredOutputPath $OutputPathPattern2

                if ($done -and $done.Success) {
                    $extractedCount++
                    $openedParentPaths[$done.ParentPath] = $true
                }
            }
            else {
                Write-Host "  SKIP: パターン2のファイル名から年月部分を取得できません。" -ForegroundColor Yellow
                Write-Host "    $(Get-EntryFileName $pattern2Xmls[0].FullName)"
            }

            continue
        }

        # ------------------------------------------------------------
        # パターン3: 社会保険料額情報
        # 社会保険料額情報_*.xml
        # ------------------------------------------------------------
        $pattern3Xmls = @(
            $entries | Where-Object {
                $name = Get-EntryFileName $_.FullName
                $name -like "社会保険料額情報_*.xml"
            }
        )

        if ($pattern3Xmls.Count -gt 1) {
            Write-Host "  SKIP: パターン3のXMLが複数あります。" -ForegroundColor Yellow
            $pattern3Xmls | ForEach-Object {
                Write-Host "    $(Get-EntryFileName $_.FullName)"
            }
            continue
        }

        if ($pattern3Xmls.Count -eq 1) {
            $fileName = Get-EntryBaseName $pattern3Xmls[0].FullName

            if ($fileName -match '^社会保険料額情報_(.+?)\(') {
                $part = $Matches[1]
                $newFolderName = "${part}社会保険料額情報"

                $matchedCount++

                $done = Confirm-And-Extract `
                    -Archive $archive `
                    -SourceDir $dir `
                    -NewFolderName $newFolderName `
                    -Reason "パターン3: 社会保険料額情報" `
                    -PreferredOutputPath $OutputPathPattern3

                if ($done -and $done.Success) {
                    $extractedCount++
                    $openedParentPaths[$done.ParentPath] = $true
                }
            }
            else {
                Write-Host "  SKIP: パターン3のファイル名から年月部分を取得できません。" -ForegroundColor Yellow
                Write-Host "    $(Get-EntryFileName $pattern3Xmls[0].FullName)"
            }

            continue
        }

        # ------------------------------------------------------------
        # パターン1: 被保険者データ
        # 同一ZIP内フォルダに *.xml, *.xsl, *.DTA が1つずつある
        # XML内 APPTITLE から年月を取得
        # ------------------------------------------------------------
        $xmls = @(
            $entries | Where-Object {
                (Get-EntryFileName $_.FullName) -match '\.xml$'
            }
        )

        $xsls = @(
            $entries | Where-Object {
                (Get-EntryFileName $_.FullName) -match '\.xsl$'
            }
        )

        $dtas = @(
            $entries | Where-Object {
                (Get-EntryFileName $_.FullName) -match '\.DTA$'
            }
        )

        if ($xmls.Count -gt 1) {
            Write-Host "  SKIP: パターン1候補ですがXMLが複数あります。" -ForegroundColor Yellow
            $xmls | ForEach-Object {
                Write-Host "    $(Get-EntryFileName $_.FullName)"
            }
            continue
        }

        if ($xmls.Count -eq 1 -and $xsls.Count -eq 1 -and $dtas.Count -eq 1) {
            try {
                $xml = Read-ZipEntryXml -Entry $xmls[0]
                $appTitle = $xml.DOC.BODY.APPENDIX.APPTITLE

                if ([string]::IsNullOrWhiteSpace($appTitle)) {
                    Write-Host "  SKIP: APPTITLEが見つかりません。" -ForegroundColor Yellow
                    continue
                }

                if ($appTitle -match '_(.+?)\(') {
                    $part = $Matches[1]
                    $newFolderName = "${part}被保険者データ"

                    $matchedCount++

                    $done = Confirm-And-Extract `
                        -Archive $archive `
                        -SourceDir $dir `
                        -NewFolderName $newFolderName `
                        -Reason "パターン1: 被保険者データ" `
                        -PreferredOutputPath $OutputPathPattern1

                    if ($done -and $done.Success) {
                        $extractedCount++
                        $openedParentPaths[$done.ParentPath] = $true
                    }
                }
                else {
                    Write-Host "  SKIP: APPTITLEから年月部分を取得できません。" -ForegroundColor Yellow
                    Write-Host "    $appTitle"
                }
            }
            catch {
                Write-Host "  SKIP: XML読み込みに失敗しました。" -ForegroundColor Yellow
                Write-Host "    $($_.Exception.Message)" -ForegroundColor Yellow
            }

            continue
        }

        Write-Host "  SKIP: 該当パターンなし"
    }

    Write-Host ""
    Write-Host "=============================="
    Write-Host "処理結果"
    Write-Host "=============================="

    if ($matchedCount -eq 0) {
        Write-Host "該当するフォルダはありませんでした。"
    }
    else {
        Write-Host "該当候補数: $matchedCount"
        Write-Host "展開実行数: $extractedCount"
    }

    if ($openedParentPaths.Count -gt 0) {
        Write-Host ""
        Write-Host "展開先の親フォルダをExplorerで開きます。"

        foreach ($path in $openedParentPaths.Keys) {
            if (Test-Path -LiteralPath $path -PathType Container) {
                Start-Process explorer.exe -ArgumentList "`"$path`""
            }
        }
    }
}
finally {
    if ($archive) {
        $archive.Dispose()
    }
}