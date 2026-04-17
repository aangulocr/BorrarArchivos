# ================================================================
# Script: LimpiarArchivosRecientes.ps1
# Ubicacion: C:\BorrarArchivos\ (fuera de perfiles de usuario)
# Descripcion: Elimina archivos recientes (< 9 dias) de las
#              Bibliotecas de Windows de usuarios no excluidos
# ================================================================

# ----- ADMIN CHECK -----
$esAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $esAdmin) {
    Write-Host "  [ERROR] Ejecute como Administrador." -ForegroundColor Red
    Write-Host "  Presione cualquier tecla..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# ----- CONFIGURACION -----
$diasLimite = 9
$fechaLimite = (Get-Date).AddDays(-$diasLimite)
$rutaUsuarios = "C:\Users"

# Log en la misma carpeta del script (C:\BorrarArchivos - fuera de perfiles)
$logPath = Join-Path $PSScriptRoot "Log_Limpieza_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').txt"

# Debug log
$debugPath = Join-Path $PSScriptRoot "debug_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').txt"
function Log-Debug { param([string]$Msg); "$(Get-Date -Format 'HH:mm:ss') $Msg" | Out-File $debugPath -Append -Encoding UTF8 }

Log-Debug "=== INICIO ==="
Log-Debug "Usuario: $env:USERNAME | PSScriptRoot: $PSScriptRoot"

# ----- USUARIOS EXCLUIDOS -----
$usuariosExcluidosManuales = @("arnol", "10-2", "Lab-01")
$perfilesSistema = @("Public", "Default", "Default User", "All Users", "defaultuser0")

$adminMembers = @()
try {
    $adminSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $adminGroupName = $adminSID.Translate([System.Security.Principal.NTAccount]).Value.Split('\')[-1]
    $adminMembers = Get-LocalGroupMember -Group $adminGroupName -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Name.Split('\')[-1] }
}
catch { Log-Debug "Error admins: $($_.Exception.Message)" }

$todosExcluidos = ($usuariosExcluidosManuales + $perfilesSistema + $adminMembers) | Select-Object -Unique
Log-Debug "Excluidos: $($todosExcluidos -join ', ')"

# ----- EXTENSIONES -----
$extensiones = @(
    "*.pdf",
    "*.jpg", "*.jpeg", "*.png", "*.gif", "*.bmp",
    "*.tiff", "*.tif", "*.webp", "*.svg", "*.ico",
    "*.raw", "*.heic", "*.heif", "*.avif",
    "*.psd", "*.ai", "*.eps", "*.cr2", "*.nef",
    "*.dng", "*.orf", "*.arw", "*.rw2",
    "*.doc", "*.docx", "*.docm",
    "*.xls", "*.xlsx", "*.xlsm", "*.csv",
    "*.ppt", "*.pptx", "*.pptm",
    "*.txt", "*.rtf",
    "*.odt", "*.ods", "*.odp"
)

# ----- CARPETAS DE BIBLIOTECA -----
$carpetasBiblioteca = @(
    "Objetos 3D", "Musica", "Imagenes", "Descargas", "Videos", "Escritorio", "Documentos",
    "3D Objects", "Music", "Images", "Downloads", "Videos", "Desktop", "Documents"
)

# ----- USUARIOS OBJETIVO -----
$carpetasUsuarios = Get-ChildItem $rutaUsuarios -Directory -ErrorAction SilentlyContinue
$usuariosObjetivo = $carpetasUsuarios | Where-Object { $_.Name -notin $todosExcluidos }
Log-Debug "Objetivo: $(($usuariosObjetivo | ForEach-Object { $_.Name }) -join ', ')"

# ----- ENCABEZADO -----
Clear-Host
Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Cyan
Write-Host "       LIMPIEZA DE ARCHIVOS RECIENTES (< $diasLimite dias)          " -ForegroundColor Cyan
Write-Host "       Fecha limite: $($fechaLimite.ToString('yyyy-MM-dd HH:mm:ss'))                " -ForegroundColor Cyan
Write-Host "  ============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "  Usuarios EXCLUIDOS:" -ForegroundColor Yellow
foreach ($u in ($todosExcluidos | Sort-Object)) {
    $tag = if ($adminMembers -contains $u) { " [Admin]" } else { "" }
    Write-Host "    X $u$tag" -ForegroundColor Yellow
}
Write-Host ""

if ($usuariosObjetivo.Count -eq 0) {
    Write-Host "  No hay usuarios objetivo. Todos excluidos." -ForegroundColor Red
    Log-Debug "Sin usuarios objetivo. Fin."
    Write-Host "  Presione cualquier tecla..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

Write-Host "  Usuarios OBJETIVO:" -ForegroundColor Green
foreach ($u in $usuariosObjetivo) { Write-Host "    > $($u.Name)" -ForegroundColor Green }
Write-Host ""

# ----- PROCESAMIENTO -----
$reporte = @()
$totalArchivos = 0
$totalCarpetas = 0
$totalErrores = 0

foreach ($usuario in $usuariosObjetivo) {
    $userPath = $usuario.FullName
    $userPathLower = $userPath.TrimEnd('\').ToLower()
    $archivosUsr = @()
    $carpetasUsr = @()

    Write-Host "  >> Usuario: $($usuario.Name)" -ForegroundColor Magenta
    Log-Debug "--- Usuario: $($usuario.Name) ($userPath) ---"

    foreach ($carpeta in $carpetasBiblioteca) {
        $rutaCarpeta = Join-Path $userPath $carpeta
        if (-not (Test-Path $rutaCarpeta -ErrorAction SilentlyContinue)) { continue }

        $itemCarpeta = Get-Item $rutaCarpeta -Force -ErrorAction SilentlyContinue
        if ($null -eq $itemCarpeta) { continue }

        # PROTECCION: Omitir ReparsePoints (junctions/symlinks)
        if ($itemCarpeta.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            Log-Debug "  OMITIDO (reparse): $rutaCarpeta"
            continue
        }

        # PROTECCION: Verificar ruta real dentro del perfil
        $rutaRealLower = $itemCarpeta.FullName.TrimEnd('\').ToLower()
        if (-not $rutaRealLower.StartsWith($userPathLower)) {
            Log-Debug "  OMITIDO (fuera de perfil): $rutaCarpeta -> $($itemCarpeta.FullName)"
            continue
        }

        # PROTECCION: No procesar rutas de usuarios excluidos
        $esExcluido = $false
        foreach ($excl in $todosExcluidos) {
            $exclPath = (Join-Path $rutaUsuarios $excl).TrimEnd('\').ToLower()
            if ($rutaRealLower.StartsWith($exclPath)) {
                $esExcluido = $true
                Log-Debug "  OMITIDO (usuario excluido $excl): $rutaCarpeta"
                break
            }
        }
        if ($esExcluido) { continue }

        Write-Host "    [$carpeta]" -ForegroundColor DarkCyan
        Log-Debug "  Procesando: $rutaCarpeta"

        # --- ARCHIVOS ---
        foreach ($ext in $extensiones) {
            $archivos = Get-ChildItem -Path $rutaCarpeta -Filter $ext -Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.CreationTime -gt $fechaLimite -or $_.LastWriteTime -gt $fechaLimite }

            foreach ($archivo in $archivos) {
                $fpLower = $archivo.FullName.TrimEnd('\').ToLower()

                # PROTECCION: Verificar ruta
                if (-not $fpLower.StartsWith($userPathLower)) {
                    Log-Debug "    ARCHIVO OMITIDO (fuera perfil): $($archivo.FullName)"
                    continue
                }

                # PROTECCION: No tocar usuarios excluidos
                $skip = $false
                foreach ($excl in $todosExcluidos) {
                    $ep = (Join-Path $rutaUsuarios $excl).TrimEnd('\').ToLower()
                    if ($fpLower.StartsWith($ep)) { $skip = $true; break }
                }
                if ($skip) {
                    Log-Debug "    ARCHIVO OMITIDO (excluido): $($archivo.FullName)"
                    continue
                }

                Log-Debug "    ELIMINANDO: $($archivo.FullName)"
                try {
                    Remove-Item $archivo.FullName -Force -ErrorAction Stop
                    $archivosUsr += [PSCustomObject]@{ Tipo="[Archivo]"; Ruta=$archivo.FullName; Estado="ELIMINADO" }
                    $totalArchivos++
                }
                catch {
                    $archivosUsr += [PSCustomObject]@{ Tipo="[Archivo]"; Ruta=$archivo.FullName; Estado="ERROR: $($_.Exception.Message)" }
                    $totalErrores++
                }
            }
        }

        # --- CARPETAS ---
        $subcarpetas = Get-ChildItem -Path $rutaCarpeta -Directory -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.CreationTime -gt $fechaLimite -or $_.LastWriteTime -gt $fechaLimite } |
            Sort-Object { $_.FullName.Length } -Descending

        foreach ($sub in $subcarpetas) {
            if (-not (Test-Path $sub.FullName)) { continue }
            $spLower = $sub.FullName.TrimEnd('\').ToLower()

            if (-not $spLower.StartsWith($userPathLower)) {
                Log-Debug "    CARPETA OMITIDA (fuera perfil): $($sub.FullName)"
                continue
            }

            $skip = $false
            foreach ($excl in $todosExcluidos) {
                $ep = (Join-Path $rutaUsuarios $excl).TrimEnd('\').ToLower()
                if ($spLower.StartsWith($ep)) { $skip = $true; break }
            }
            if ($skip) {
                Log-Debug "    CARPETA OMITIDA (excluido): $($sub.FullName)"
                continue
            }

            Log-Debug "    ELIMINANDO CARPETA: $($sub.FullName)"
            try {
                Remove-Item $sub.FullName -Recurse -Force -ErrorAction Stop
                $carpetasUsr += [PSCustomObject]@{ Tipo="[Carpeta]"; Ruta=$sub.FullName; Estado="ELIMINADO" }
                $totalCarpetas++
            }
            catch {
                $carpetasUsr += [PSCustomObject]@{ Tipo="[Carpeta]"; Ruta=$sub.FullName; Estado="ERROR: $($_.Exception.Message)" }
                $totalErrores++
            }
        }
    }

    $detalles = $archivosUsr + $carpetasUsr
    if ($detalles.Count -gt 0) {
        $reporte += [PSCustomObject]@{ Usuario=$usuario.Name; Detalles=$detalles }
    }
    else { Write-Host "    (sin archivos recientes)" -ForegroundColor DarkGray }
    Write-Host ""
}

# ----- REPORTE -----
Write-Host "  ============================================================" -ForegroundColor Cyan
Write-Host "              REPORTE FINAL                                    " -ForegroundColor Cyan
Write-Host "  ============================================================" -ForegroundColor Cyan
Write-Host ""

if ($reporte.Count -eq 0) {
    Write-Host "  No se encontraron archivos para eliminar." -ForegroundColor Yellow
}
else {
    foreach ($e in $reporte) {
        Write-Host "  Usuario: $($e.Usuario)" -ForegroundColor Green
        $ok = $e.Detalles | Where-Object { $_.Estado -eq "ELIMINADO" }
        $err = $e.Detalles | Where-Object { $_.Estado -like "ERROR*" }
        if ($ok.Count -gt 0) {
            Write-Host "    Eliminados ($($ok.Count)):" -ForegroundColor Green
            foreach ($i in $ok) { Write-Host "      $($i.Tipo) $($i.Ruta)" -ForegroundColor Gray }
        }
        if ($err.Count -gt 0) {
            Write-Host "    Errores ($($err.Count)):" -ForegroundColor Red
            foreach ($i in $err) { Write-Host "      $($i.Ruta) -> $($i.Estado)" -ForegroundColor Red }
        }
        Write-Host ""
    }
}

Write-Host "  Archivos eliminados: $totalArchivos" -ForegroundColor Green
Write-Host "  Carpetas eliminadas: $totalCarpetas" -ForegroundColor Green
Write-Host "  Errores: $totalErrores" -ForegroundColor $(if ($totalErrores -gt 0) { "Red" } else { "Green" })
Write-Host ""

# Guardar log
try {
    $lc = @("REPORTE - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", "Limite: $($fechaLimite.ToString('yyyy-MM-dd'))", "Excluidos: $($todosExcluidos -join ', ')", "Procesados: $(($usuariosObjetivo | ForEach-Object { $_.Name }) -join ', ')", "")
    foreach ($e in $reporte) {
        $lc += "--- $($e.Usuario) ---"
        foreach ($i in $e.Detalles) { $lc += "  $($i.Estado) | $($i.Tipo) | $($i.Ruta)" }
        $lc += ""
    }
    $lc += "Archivos: $totalArchivos | Carpetas: $totalCarpetas | Errores: $totalErrores"
    $lc | Out-File -FilePath $logPath -Encoding UTF8
    Write-Host "  Log: $logPath" -ForegroundColor DarkCyan
    Write-Host "  Debug: $debugPath" -ForegroundColor DarkCyan
}
catch { Write-Host "  Error guardando log: $($_.Exception.Message)" -ForegroundColor Yellow }

Log-Debug "=== FIN === Archivos:$totalArchivos Carpetas:$totalCarpetas Errores:$totalErrores"

Write-Host ""
Write-Host "  Presione cualquier tecla para cerrar..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
