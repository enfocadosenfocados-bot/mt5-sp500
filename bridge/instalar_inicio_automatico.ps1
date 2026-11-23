# =============================================================================
# Instala el Puente Local CME -> MT5 en el Inicio Automatico de Windows
# =============================================================================
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BridgePy  = Join-Path $ScriptDir "cme_mt5_bridge.py"

$PywCmd = Get-Command pythonw -ErrorAction SilentlyContinue
if (-not $PywCmd) {
    $PywCmd = Get-Command python -ErrorAction SilentlyContinue
}
if (-not $PywCmd) {
    Write-Host "[ERROR] No se encontro Python en el sistema. Instalalo desde python.org (marca 'Add Python to PATH')." -ForegroundColor Red
    exit 1
}

$StartupDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$Ws = New-Object -ComObject WScript.Shell
$Lnk = $Ws.CreateShortcut("$StartupDir\CME_MT5_Bridge.lnk")
$Lnk.TargetPath = $PywCmd.Source
$Lnk.Arguments = "`"$BridgePy`""
$Lnk.WorkingDirectory = $ScriptDir
$Lnk.Save()

Write-Host "[+] Acceso directo creado en Inicio de Windows: $StartupDir\CME_MT5_Bridge.lnk" -ForegroundColor Green

# Iniciar el puente ahora mismo en segundo plano
Start-Process -FilePath $PywCmd.Source -ArgumentList "`"$BridgePy`"" -WorkingDirectory $ScriptDir -WindowStyle Hidden
Write-Host "[+] Puente iniciado en segundo plano en http://127.0.0.1:8765" -ForegroundColor Green
