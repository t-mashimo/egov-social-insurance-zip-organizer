@echo off
setlocal

set "SCRIPT=%~dp0Extract-JPSZipFolders.ps1"

if "%~1"=="" (
    echo ZIPファイルをこのBATにドラッグ＆ドロップしてください。
    pause
    exit /b
)

:loop
if "%~1"=="" goto end

echo.
echo === 処理対象: %~1 ===
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" "%~1"

shift
goto loop

:end
echo.
echo 完了しました。
pause