# MT5 SP500 — Suite Completa de Indicadores Institucionales MQL5 + CME Open Interest & GEX

Suite completa y lista para instalar en cualquier PC con **MetaTrader 5 (IC Markets)** para operar **S&P 500 (`US500`)** e índices US.

---

## ¿Qué incluye este repositorio?

### 1. Indicadores MQL5 (`mql5/Indicators/` — código `.mq5` + `.ex5` ya compilados)
| Indicador | Función |
| :--- | :--- |
| **`CME_OpenInterest_Levels`** *(v2.05)* | Dibuja los strikes con mayor Open Interest de CME dentro de **±300 puntos desde la Apertura del Día** en IC Markets. Muestra Call o Put mayor por strike (líneas gruesas para los más grandes) y aplica offset `-20` automático de `ES → US500`. |
| **`DailyVolumeProfilePOC`** *(v2.20)* | Perfil de Volumen Diario en tiempo real (`POC Hoy`, `VAH`, `VAL`), `POC Ayer` fijo, **`VWAP Hoy` y `VWAP Ayer`**, máximos/mínimos de sesiones (Asia, Londres, NY) y proyección de puja. |
| **`SP500_Gamma_Flip_Levels`** *(v1.10)* | Dibuja los niveles institucionales de Gamma Exposure (**Gamma Flip**, **Vol Trigger**, **Call Wall**, **Put Wall** y **Abs Gamma Strike**) + panel HUD de régimen GEX (`Positive/Negative Gamma`). |
| **`US500_CVD_Trigger`** *(v1.00)* | Subventana de **Cumulative Volume Delta (CVD)** en tiempo real con detección automática de **divergencias de absorción** y señal EMA. |
| **`US_Market_Internals_Filter`** *(v1.00)* | Filtro anti-trampas de amplitud real US comparando **`US2000` (Proxy `$ADD`)**, **`US500`**, **`USTEC`** y **`US30`** (o `$ADD / $VOLD / $TICK` nativos si tu broker los tiene). |

### 2. Script MQL5 de Actualización GEX (`mql5/Scripts/`)
* **`GEX_Update_Data.mq5` / `.ex5`**: Descarga automáticamente los niveles diarios de Gamma Flip (`gex_latest.json`) hacia `MQL5\Files\`.

### 3. Extensión de Chrome + Puente Python (`chrome_extension/` y `bridge/`)
* Extrae en **1 clic** los strikes del **CME QuikStrike Open Interest Heatmap** desde Google Chrome y los envía al instante a MetaTrader 5.

### 4. Herramientas Python GEX locales opcionales (`gex_python/`)
* Scripts de `Gex-Multi` (`gex_multi.py`, `cboe_data.py`, `gamma_exposure.py`) por si deseas calcular perfiles GEX locales directamente desde CBOE.

---

## Estructura del Repositorio

```text
mt5-sp500/
├── mql5/
│   ├── Indicators/
│   │   ├── CME_OpenInterest_Levels.mq5 / .ex5
│   │   ├── DailyVolumeProfilePOC.mq5 / .ex5
│   │   ├── SP500_Gamma_Flip_Levels.mq5 / .ex5
│   │   ├── US500_CVD_Trigger.mq5 / .ex5
│   │   └── US_Market_Internals_Filter.mq5 / .ex5
│   ├── Scripts/
│   │   └── GEX_Update_Data.mq5 / .ex5
│   └── Files/
│       └── gex_latest.json
├── chrome_extension/
│   ├── manifest.json
│   ├── service-worker.js
│   └── content.js
├── bridge/
│   ├── cme_mt5_bridge.py
│   ├── iniciar_puente.bat
│   └── instalar_inicio_automatico.ps1
└── gex_python/
    ├── cboe_data.py
    ├── gamma_exposure.py
    ├── gex_multi.py
    └── requirements.txt
```

---

## Instalación Completa en Otro Computador (Paso a Paso)

### Paso 1: Descargar el repositorio
Clona o descarga el ZIP desde GitHub en una carpeta fija (ej. `C:\mt5-sp500`):
```powershell
git clone https://github.com/enfocadosenfocados-bot/mt5-sp500.git C:\mt5-sp500
```

### Paso 2: Copiar Indicadores, Script y Archivo JSON en MetaTrader 5
1. Abre **MetaTrader 5** y ve a **Archivo → Abrir Carpeta de Datos** (`Ctrl + Shift + D`).
2. Copia el contenido de las 3 carpetas dentro de `MQL5\` de tu terminal:
   * **`mql5\Indicators\*`** → pega en **`MQL5\Indicators\`** *(5 indicadores `.mq5` y `.ex5`)*.
   * **`mql5\Scripts\*`** → pega en **`MQL5\Scripts\`** *(script `GEX_Update_Data.mq5` y `.ex5`)*.
   * **`mql5\Files\gex_latest.json`** → pega en **`MQL5\Files\`** *(datos iniciales para `SP500_Gamma_Flip_Levels`)*.
3. En MT5, ve a **Navegador → clic derecho en Indicadores → Actualizar** (y lo mismo en **Scripts**).

### Paso 3: Configurar Permisos y Símbolos en MetaTrader 5 (MUY IMPORTANTE)
1. **Para que funcione `GEX_Update_Data` (Gamma Flip):**
   * En MT5 ve a **Herramientas → Opciones → Asesores Expertos**.
   * Marca **"Permitir WebRequest para las URLs listadas"**.
   * Agrega exactamente esta URL:
     ```text
     https://raw.githubusercontent.com
     ```
   * Pulsa **Aceptar**. Cada vez que arrastres el script **`GEX_Update_Data`** al gráfico, actualizará `gex_latest.json` al instante.
2. **Para que funcione `US_Market_Internals_Filter`:**
   * Abre **Observación de Mercado (`Ctrl + M`)** y asegúrate de tener visibles/activos los 4 símbolos de IC Markets:
     `US500`, `USTEC`, `US2000`, `US30`.
3. **Colocar los indicadores en tu gráfico de `US500`:**
   * Gráfico principal: `CME_OpenInterest_Levels`, `SP500_Gamma_Flip_Levels`, `DailyVolumeProfilePOC`.
   * Subventanas: `US500_CVD_Trigger`, `US_Market_Internals_Filter`.

### Paso 4: Encender el Puente Local Python (para CME Open Interest)
*Requisito: tener **Python 3** instalado (en [python.org](https://www.python.org/downloads/), marca **"Add Python to PATH"** al instalar). No requiere librerías externas.*

* **Opción A — Inicio Automático con Windows (Recomendado):**
  ```powershell
  powershell -ExecutionPolicy Bypass -File "C:\mt5-sp500\bridge\instalar_inicio_automatico.ps1"
  ```
* **Opción B — Arranque Manual:**
  Haz doble clic en **`bridge\iniciar_puente.bat`** antes de operar.

### Paso 5: Instalar la Extensión en Google Chrome
1. Abre **Google Chrome** y ve a **`chrome://extensions`**.
2. Activa arriba a la derecha **Modo de desarrollador (Developer mode)**.
3. Haz clic en **Cargar descomprimida (Load unpacked)**.
4. Selecciona la carpeta **`C:\mt5-sp500\chrome_extension`**.

---

## Uso Diario
1. **Actualizar Gamma Flip:** Arrastra el script **`GEX_Update_Data`** al gráfico (descarga `gex_latest.json` automáticamente).
2. **Actualizar Strikes CME Open Interest:**
   * Abre `https://www.cmegroup.com/tools-information/quikstrike/open-interest-heatmap.html` en Chrome.
   * Selecciona **`S&P 500 (ES|ES)`** y cambia **`Strikes: 15`** a **`All`** (o `100`).
   * Haz clic en **`📤 Enviar Strikes a MT5`**.
   * El puente resta **`-20` puntos** automáticamente (`ES → US500`) y MT5 dibuja todos los niveles más grandes en **±300 puntos** desde la apertura del día.
