<# :
@echo off
setlocal
if "%~1"=="" (
    echo.
    echo ========================================================
    echo  INSTRUCCIONES DE EJECUCION REMOTA
    echo ========================================================
    echo  Este script ejecuta la limpieza en un ordenador 
    echo  remoto y devuelve los resultados a su pantalla.
    echo.
    echo  Uso:     %~nx0 [MAC-DESTINO]
    echo  Ejemplo: %~nx0 FC-AA-14-22-31-01
    echo ========================================================
    echo.
    exit /b 1
)

set "SCRIPT_PATH=%~f0"
set "MAC_ARG=%~1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Command -ScriptBlock ([ScriptBlock]::Create((Get-Content -Raw -LiteralPath $env:SCRIPT_PATH))) -ArgumentList $env:MAC_ARG"
exit /b %errorlevel%
#>

param(
    [string]$MacAddress
)

$ErrorActionPreference = "Stop"

$NormalizedMac = ($MacAddress -replace "[:-]", "-").ToLower()

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  EJECUCION Y MONITOREO REMOTO"                -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "MAC de Destino: $NormalizedMac"
Write-Host "---------------------------------------------"

function Get-IpFromArp ([string]$mac) {
    try {
        $arpEntry = arp -a | Select-String -Pattern $mac -SimpleMatch -ErrorAction Stop
        if ($arpEntry) {
            $line = $arpEntry.Line.Trim() -replace '\s+', ' '
            $parts = $line.Split(' ')
            return $parts[0]
        }
    } catch {}
    return $null
}

$ipDestino = Get-IpFromArp $NormalizedMac

if (-not $ipDestino) {
    Write-Host "[*] MAC no en cache. Escaneando red..." -ForegroundColor Yellow
    $localIpInfo = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback" } | Select-Object -First 1
    if ($localIpInfo) {
        $baseIp = "$($localIpInfo.IPAddress.Substring(0, $localIpInfo.IPAddress.LastIndexOf('.')))."
        $Tasks = @(); $Pingers = @()
        for ($i=1; $i -le 254; $i++) {
            $p = New-Object System.Net.NetworkInformation.Ping
            $Pingers += $p; $Tasks += $p.SendPingAsync("$baseIp$i", 400)
        }
        [System.Threading.Tasks.Task]::WaitAll($Tasks)
        $ipDestino = Get-IpFromArp $NormalizedMac
    }
}

if ($ipDestino) {
    Write-Host "[+] PC Localizada: $ipDestino" -ForegroundColor Green
    Write-Host "[*] Conectando y ejecutando limpieza... Por favor espere." -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray

    try {
        # Usamos Invoke-Command para obtener la salida en tiempo real
        # Se requiere que WinRM este habilitado (Enable-PSRemoting) en los destinos
        Invoke-Command -ComputerName $ipDestino -ScriptBlock {
            if (Test-Path "C:\BorrarArchivos\EjecutarLimpieza.bat") {
                # Ejecutamos el batch y capturamos su salida
                cmd /c "C:\BorrarArchivos\EjecutarLimpieza.bat"
            } else {
                Write-Error "El archivo C:\BorrarArchivos\EjecutarLimpieza.bat no existe en la PC remota."
            }
        } -ErrorAction Stop
        
        Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "[+] PROCESO FINALIZADO EXITOSAMENTE" -ForegroundColor Green
    } catch {
        Write-Host ""
        Write-Host "[-] ERROR DE CONEXION O EJECUCION:" -ForegroundColor Red
        Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        Write-Host "POSIBLES CAUSAS:" -ForegroundColor Yellow
        Write-Host "1. WinRM no esta habilitado en el estudiante (Ejecutar: Enable-PSRemoting -Force)." -ForegroundColor White
        Write-Host "2. El Firewall de Windows bloquea la conexion (Puertos 5985/5986)." -ForegroundColor White
        Write-Host "3. Credenciales insuficientes." -ForegroundColor White
    }
} else {
    Write-Host "[-] ERROR: No se encontro la IP para la MAC $NormalizedMac." -ForegroundColor Red
}
Write-Host ""
