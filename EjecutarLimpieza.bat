@echo off
chcp 65001 >nul 2>&1
title Limpieza de Archivos Recientes

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo   Solicitando permisos de administrador...
    echo.
    powershell -NoProfile -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

if not exist "%~dp0LimpiarArchivosRecientes.ps1" (
    echo   [ERROR] No se encontro LimpiarArchivosRecientes.ps1
    echo   Buscado en: %~dp0
    pause
    exit /b 1
)

powershell.exe -NoProfile -NoLogo -ExecutionPolicy Bypass -Command "& '%~dp0LimpiarArchivosRecientes.ps1'"
