<# :
@echo off
setlocal
if "%~2"=="" (
    echo.
    echo ========================================================
    echo  INSTRUCCIONES DE USO
    echo ========================================================
    echo  Este script transfiere un archivo a un ordenador 
    echo  remoto identificandolo unicamente por su MAC Address.
    echo.
    echo  Uso:     %~nx0 [MAC-DESTINO] [ARCHIVO]
    echo  Ejemplo: %~nx0 FC-AA-14-22-31-01 EjecutarLimpieza.bat
    echo ========================================================
    echo.
    exit /b 1
)

if not exist "%~2" (
    echo ERROR: El archivo "%~2" no existe.
    exit /b 1
)

:: El siguiente bloque salta las politicas de Execution Policy llamando un flujo Bypass
:: Utiliza variables de entorno para evitar cualquier inyeccion en los argumentos
set "SCRIPT_PATH=%~f0"
set "MAC_ARG=%~1"
set "FILE_ARG=%~2"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Command -ScriptBlock ([ScriptBlock]::Create((Get-Content -Raw -LiteralPath $env:SCRIPT_PATH))) -ArgumentList $env:MAC_ARG, $env:FILE_ARG"
exit /b %errorlevel%
#>

param(
    [string]$MacAddress,
    [string]$FilePath
)

$ErrorActionPreference = "Stop"

$NormalizedMac = ($MacAddress -replace "[:-]", "-").ToLower()
$FileName = Split-Path -Path $FilePath -Leaf

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Iniciando proceso de transferencia LAN"      -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "Archivo a transferir: $FileName" 
Write-Host "MAC de Destino:       $NormalizedMac"
Write-Host "---------------------------------------------"

function Get-IpFromArp ([string]$mac) {
    # Evitamos errores si no hay conincidencias en ARP
    try {
        $arpEntry = arp -a | Select-String -Pattern $mac -SimpleMatch -ErrorAction Stop
        if ($arpEntry) {
            # Extraemos la IP que viene estructurada con espacios
            $line = $arpEntry.Line.Trim() -replace '\s+', ' '
            $parts = $line.Split(' ')
            return $parts[0]
        }
    } catch {}
    return $null
}

$ipDestino = Get-IpFromArp $NormalizedMac

if (-not $ipDestino) {
    Write-Host "[*] La MAC no esta en cache. Ejecutando escaneo rapido en la subred..." -ForegroundColor Yellow
    
    $localIpInfo = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
        $_.InterfaceAlias -notmatch "Loopback" -and 
        $_.IPAddress -notmatch "^169.254" 
    } | Select-Object -First 1
    
    if ($localIpInfo) {
        $ipParts = $localIpInfo.IPAddress.Split('.')
        $baseIp = "$($ipParts[0]).$($ipParts[1]).$($ipParts[2])."
        
        Write-Host "    Barriendo la subred: $baseIp* (Ping Asincrono)..." -ForegroundColor DarkGray
        
        # Ping asincrono ultrarapido a la subred /24 
        $Tasks = @()
        $Pingers = @()
        for ($i=1; $i -le 254; $i++) {
            $target = "$baseIp$i"
            $pinger = New-Object System.Net.NetworkInformation.Ping
            $Pingers += $pinger
            $Tasks += $pinger.SendPingAsync($target, 500)
        }
        
        try { 
            [System.Threading.Tasks.Task]::WaitAll($Tasks) 
        } catch {}
        
        foreach ($p in $Pingers) { $p.Dispose() }
        
        # Volvemos a consultar el catalogo de ARP
        $ipDestino = Get-IpFromArp $NormalizedMac
    }
}

if ($ipDestino) {
    Write-Host "[+] Equipo destino localizado en la IP: $ipDestino" -ForegroundColor Green
    
    # Configuramos la ruta administrativa por defecto C:\BorrarArchivos en la maquina remota
    $remoteFolder = "\\$ipDestino\C$\BorrarArchivos"
    $remoteFilePath = "$remoteFolder\$FileName"
            
    Write-Host "[*] Comprobando acceso administrativo a \\$ipDestino\C$ ..." -ForegroundColor Yellow
    
    if (-not (Test-Path "\\$ipDestino\C$" -ErrorAction SilentlyContinue)) {
        Write-Host "[-] ERROR DE RED O PERMISOS:" -ForegroundColor Red
        Write-Host "    Acceso denegado o el Firewall remoto esta bloqueando el puerto SMB (445)." -ForegroundColor Red
        Write-Host "    Asegurese de que:" -ForegroundColor Yellow
        Write-Host "       1. Tiene credenciales de Administrador para esa maquina." -ForegroundColor Yellow
        Write-Host "       2. Compartir Archivos e Impresoras esta activo en el PC de destino." -ForegroundColor Yellow
        exit 1
    }
    
    if (-not (Test-Path $remoteFolder -ErrorAction SilentlyContinue)) {
        Write-Host "[*] Creando carpeta remota destino en el equipo..." -ForegroundColor Yellow
        New-Item -Path $remoteFolder -ItemType Directory -Force | Out-Null
    }

    Write-Host "[*] Realizando la copia del archivo por la red..." -ForegroundColor Cyan
    try {
        Copy-Item -Path $FilePath -Destination $remoteFilePath -Force -ErrorAction Stop
        Write-Host "[+] EXITO: El archivo fue transferido correctamente a la ruta remota:" -ForegroundColor Green
        Write-Host "    $remoteFilePath" -ForegroundColor Green
    } catch {
        Write-Host "[-] ERROR AL COPIAR EL ARCHIVO:" -ForegroundColor Red
        Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
    }
    
} else {
    Write-Host "[-] ERROR CRITICO DE LOCALIZACION:" -ForegroundColor Red
    Write-Host "    No se pudo resolver ninguna IP asignable a la MAC $NormalizedMac." -ForegroundColor Red
    Write-Host "    Verifique que el PC remoto esta encendido, en la red correcta, y no conectado a un segmento distinto." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
