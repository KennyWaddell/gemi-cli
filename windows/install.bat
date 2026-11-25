@echo off
setlocal
REM Optional helper: adds this folder to your Windows User PATH (no admin required).
REM Ayuda opcional: agrega esta carpeta al PATH de tu usuario en Windows (sin permisos de admin).

set "DIR=%~dp0"
if "%DIR:~-1%"=="\" set "DIR=%DIR:~0,-1%"

echo Adding to User PATH / Agregando al PATH de usuario:
echo   %DIR%
echo.

powershell -NoProfile -Command ^
  "$d = $env:DIR;" ^
  "$p = [Environment]::GetEnvironmentVariable('Path', 'User');" ^
  "if (-not $p) { $p = '' };" ^
  "$parts = $p -split ';' | Where-Object { $_ -ne '' };" ^
  "if ($parts -contains $d) { Write-Host 'Already in PATH / Ya estaba en el PATH.' }" ^
  "else { $new = ($parts + $d) -join ';'; [Environment]::SetEnvironmentVariable('Path', $new, 'User'); Write-Host 'Done! Reopen cmd.exe to use gemi from anywhere. / Listo! Reabre cmd.exe para usar gemi desde cualquier ruta.' }"

echo.
pause
