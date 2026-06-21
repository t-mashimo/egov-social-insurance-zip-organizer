@echo off
rem csv_vertical_ascii.bat
rem
rem Author: Tatsumi Mashimo
rem Repository: https://github.com/t-mashimo/egov-social-insurance-zip-organizer
rem License: MIT
rem
rem This script is provided as-is, without warranty of any kind.

setlocal EnableExtensions

set "target=%*"
set "target=%target:"=%"
set "script=%~dp0csv_vertical_ascii.ps1"

if "%target%"=="" (
  echo No CSV file was dropped.
  pause
  exit /b 1
)

if not exist "%script%" (
  echo PowerShell script not found: %script%
  pause
  exit /b 1
)

echo target=[%target%]
echo script=[%script%]

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%script%" -CsvPath "%target%"

pause
