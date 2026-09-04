@echo off
chcp 65001 > nul
setlocal

echo.
echo   === Sangokushi 14 - Trait Name Finder ===
echo.

set "TARGET=%~1"
if "%TARGET%"=="" (
  echo   Drag a FILE or a FOLDER onto this .bat file,
  echo   or type the full path below.
  echo.
  set /p TARGET="   Path: "
)

set "TARGET=%TARGET:"=%"
if not exist "%TARGET%" (
  echo.
  echo   [X] Not found: %TARGET%
  echo.
  pause
  exit /b 1
)

set "OUT=%~dp0result.txt"
echo   Scanning... a large folder may take a few minutes.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0GaeseongID.ps1" "%TARGET%" > "%OUT%" 2>&1

echo   Done. Opening result.txt
echo.
start notepad "%OUT%"
endlocal
