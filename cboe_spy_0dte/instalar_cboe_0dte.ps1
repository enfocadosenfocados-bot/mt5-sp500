# =============================================================================
# Instalador Automatico CBOE SPY/SPX 0DTE para MetaTrader 5 (Otro PC)
# =============================================================================
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$UpdaterPy = Join-Path $ScriptDir "cboe_0dte_updater.py"

$PyCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $PyCmd) {
    Write-Host "[ERROR] No se encontro Python 3 en el PATH. Instalalo desde python.org marcando 'Add Python to PATH'." -ForegroundColor Red
    exit 1
}

# 1. Instalar requests si falta
& $PyCmd.Source -m pip install requests --quiet

# 2. Ejecutar una vez ahora mismo para generar CBOE_0DTE_Levels.csv y CBOE_0DTE_Summary.csv
Write-Host "[*] Descargando datos CBOE 0DTE actuales..." -ForegroundColor Cyan
& $PyCmd.Source "$UpdaterPy" --once

# 3. Copiar el indicador (.mq5 y .ex5) a todos los terminales MT5 encontrados
$Terminals = Get-ChildItem "$env:APPDATA\MetaQuotes\Terminal" -Directory -ErrorAction SilentlyContinue
foreach ($t in $Terminals) {
    $indDir = Join-Path $t.FullName "MQL5\Indicators"
    if (Test-Path $indDir) {
        Copy-Item (Join-Path $ScriptDir "CBOE_SPY_SPX_0DTE_Levels.mq5") "$indDir\CBOE_SPY_SPX_0DTE_Levels.mq5" -Force
        Copy-Item (Join-Path $ScriptDir "CBOE_SPY_SPX_0DTE_Levels.ex5") "$indDir\CBOE_SPY_SPX_0DTE_Levels.ex5" -Force
        Write-Host "[+] Indicador copiado a: $indDir" -ForegroundColor Green
    }
}

# 4. Agregar actualizador cada 5 minutos al Inicio de Windows y arrancarlo ahora
$PywCmd = Get-Command pythonw -ErrorAction SilentlyContinue
if (-not $PywCmd) { $PywCmd = $PyCmd }

$StartupDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$Ws = New-Object -ComObject WScript.Shell
$Lnk = $Ws.CreateShortcut("$StartupDir\CBOE_0DTE_Updater.lnk")
$Lnk.TargetPath = $PywCmd.Source
$Lnk.Arguments = "`"$UpdaterPy`" --interval 300"
$Lnk.WorkingDirectory = $ScriptDir
$Lnk.Save()

Start-Process -FilePath $PywCmd.Source -ArgumentList "`"$UpdaterPy`" --interval 300" -WorkingDirectory $ScriptDir -WindowStyle Hidden
Write-Host "[+] CBOE 0DTE Updater activo cada 5 min y agregado al Inicio de Windows." -ForegroundColor Green
Write-Host "[!] En MT5: clic derecho en Indicadores -> Actualizar y arrastra CBOE_SPY_SPX_0DTE_Levels al grafico." -ForegroundColor Yellow
