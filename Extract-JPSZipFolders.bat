@echo off
rem Extract-JPSZipFolders.bat
rem
rem Author: Tatsumi Mashimo
rem Repository: https://github.com/t-mashimo/egov-social-insurance-zip-organizer
rem License: MIT
rem
rem This script is provided as-is, without warranty of any kind.

setlocal

set "SCRIPT=%~dp0Extract-JPSZipFolders.ps1"

if "%~1"=="" (
    echo Drag and drop ZIP files onto this BAT.
    pause
    exit /b
)

:loop
if "%~1"=="" goto end

echo.
echo === Target: %~1 ===
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" "%~1"

shift
goto loop

:end
echo.
echo Done.
pause