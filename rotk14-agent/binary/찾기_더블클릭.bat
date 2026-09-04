@echo off
chcp 65001 > nul
setlocal

echo.
echo   === Sangokushi 14 - Trait ID Finder ===
echo.

set "TARGET=%~1"
if "%TARGET%"=="" (
  echo   Drag the game data file onto this .bat file,
  echo   or type its full path below.
  echo.
  set /p TARGET="   File path: "
)

set "TARGET=%TARGET:"=%"
if not exist "%TARGET%" (
  echo.
  echo   [X] File not found: %TARGET%
  echo.
  pause
  exit /b 1
)

set "OUT=%~dp0result.txt"
echo   Scanning... this may take a minute for a large file.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0GaeseongID.ps1" "%TARGET%" > "%OUT%" 2>&1

echo   Done. Opening result.txt
echo.
start notepad "%OUT%"
endlocal
