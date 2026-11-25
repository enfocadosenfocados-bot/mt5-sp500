# CBOE SPY & SPX 0DTE — Paquete Independiente para MT5

Esta carpeta contiene **únicamente** lo necesario para instalar el indicador de **CBOE 0DTE (`SPY` y `SPX`)** en otro computador sin tener que descargar ni tocar lo de CME o GEX.

## Contenido de esta carpeta
* `CBOE_SPY_SPX_0DTE_Levels.mq5` / `.ex5` (v1.10)
* `cboe_0dte_updater.py` (descarga gratis sin login cada 5 min `Vol`, `IV`, `Delta`, `Gamma`, `OI`, `Max Pain`, `Net GEX` y `Mov. Esperado`)
* `instalar_cboe_0dte.ps1` (instalador automático en 1 clic)

---

## Cómo descargar SOLO esta carpeta en tu otro PC (sin bajar el resto del repo)

Abre **PowerShell** en el otro computador y pega estas líneas:

```powershell
$dest = "C:\cboe_spy_0dte"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$base = "https://raw.githubusercontent.com/enfocadosenfocados-bot/mt5-sp500/main/cboe_spy_0dte"
foreach ($f in @("CBOE_SPY_SPX_0DTE_Levels.mq5", "CBOE_SPY_SPX_0DTE_Levels.ex5", "cboe_0dte_updater.py", "instalar_cboe_0dte.ps1")) {
    Invoke-WebRequest -Uri "$base/$f" -OutFile "$dest\$f"
}
powershell -ExecutionPolicy Bypass -File "$dest\instalar_cboe_0dte.ps1"
```

### ¿Qué hace automáticamente ese comando?
1. Descarga **solo** los 4 archivos de CBOE en `C:\cboe_spy_0dte`.
2. Instala `requests` (si hace falta) y descarga los datos 0DTE de hoy al instante.
3. Copia `CBOE_SPY_SPX_0DTE_Levels.mq5` y `.ex5` directo a la carpeta `MQL5\Indicators\` de tu MetaTrader 5.
4. Deja `cboe_0dte_updater.py` corriendo en segundo plano cada **5 minutos** y agregado al **Inicio de Windows**.

Después en MetaTrader 5 solo haz clic derecho en **Indicadores → Actualizar** y arrastra **`CBOE_SPY_SPX_0DTE_Levels`** a tu gráfico de **`SPY.NYSE-24`** o **`US500`**.
