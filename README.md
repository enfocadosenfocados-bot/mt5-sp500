# MT5 SP500 — Indicadores Institucionales MQL5 + Puente CME Open Interest (Chrome Extension)

Suite lista para instalar en cualquier PC con **MetaTrader 5 (IC Markets)**, que combina:
1. **Indicador de Niveles CME Open Interest (`CME_OpenInterest_Levels`)**:
   - Dibuja en el gráfico los strikes con mayor Open Interest dentro de **±300 puntos desde el precio de apertura del día** en IC Markets.
   - Compara Call vs Put en cada strike y muestra **solo el mayor** (sin encimar líneas).
   - Destaca los niveles más grandes (`#1`, `#2` y muros `>= 1000` OI) con **líneas sólidas más gruesas**.
   - Incluye ajuste automático de base **Futuro CME (`ES`) → CFD IC Markets (`US500`) de `-20` puntos** (ej. `7200` en CME → `7180` en US500).
2. **Indicador de Perfil de Volumen, POC y VWAP (`DailyVolumeProfilePOC`)**:
   - Perfil de Volumen Diario en tiempo real (`POC Hoy`, `VAH`, `VAL`).
   - `POC Ayer` fijo y `VWAP Hoy` / `VWAP Ayer`.
   - Máximos y mínimos de sesiones (Asia, Londres, Nueva York) y proyección de puja compradora/vendedora.
3. **Extensión de Google Chrome + Puente Local Python**:
   - Extrae en **1 clic** todos los strikes del **CME QuikStrike Open Interest Heatmap** (soportando miles con punto o coma, ej. `3.489` y `3,489`) y los envía directo a tus gráficos de MetaTrader 5.

---

## Estructura del Repositorio

```text
mt5-sp500/
├── mql5/
│   └── Indicators/
│       ├── CME_OpenInterest_Levels.mq5   # Código fuente (v2.05)
│       ├── CME_OpenInterest_Levels.ex5   # Compilado listo para usar
│       ├── DailyVolumeProfilePOC.mq5     # Código fuente (v2.20)
│       └── DailyVolumeProfilePOC.ex5     # Compilado listo para usar
├── chrome_extension/
│   ├── manifest.json                     # Extensión Chrome Manifest V3
│   ├── service-worker.js
│   └── content.js                        # Botón "Enviar Strikes a MT5" en QuikStrike
└── bridge/
    ├── cme_mt5_bridge.py                 # Servidor local puerto 8765 (stdlib Python)
    ├── iniciar_puente.bat                # Arranque manual con doble clic
    └── instalar_inicio_automatico.ps1    # Instala inicio automático con Windows
```

---

## Instalación en Otro Computador (Paso a Paso)

### Paso 1: Descargar el repositorio
Clona o descarga el ZIP desde GitHub y descomprímelo en una carpeta fija (por ejemplo `C:\mt5-sp500`):
```powershell
git clone https://github.com/enfocadosenfocados-bot/mt5-sp500.git C:\mt5-sp500
```

### Paso 2: Instalar los Indicadores en MetaTrader 5
1. Abre tu **MetaTrader 5**.
2. Ve al menú **Archivo → Abrir Carpeta de Datos** (`Ctrl + Shift + D`).
3. Entra a la carpeta **`MQL5\Indicators\`**.
4. Copia dentro los 4 archivos de `mql5\Indicators\`:
   - `CME_OpenInterest_Levels.mq5` y `CME_OpenInterest_Levels.ex5`
   - `DailyVolumeProfilePOC.mq5` y `DailyVolumeProfilePOC.ex5`
5. En MetaTrader 5, ve al panel **Navegador → clic derecho en Indicadores → Actualizar** *(o compílalos con `F7` en MetaEditor si deseas recompilar)*.
6. Arrastra **`CME_OpenInterest_Levels`** y/o **`DailyVolumeProfilePOC`** a tu gráfico de **`US500`** (o `USTEC`, `XAUUSD`, `XTIUSD`, etc.).

### Paso 3: Instalar y Encender el Puente Local Python
*Requisito: tener **Python 3** instalado (en [python.org](https://www.python.org/downloads/), marca **"Add Python to PATH"** al instalar). No requiere instalar librerías externas.*

* **Opción A — Inicio Automático con Windows (Recomendado):**
  Haz clic derecho sobre `bridge\instalar_inicio_automatico.ps1` → **Ejecutar con PowerShell** (o ejecuta en PowerShell):
  ```powershell
  powershell -ExecutionPolicy Bypass -File "C:\mt5-sp500\bridge\instalar_inicio_automatico.ps1"
  ```
  Esto deja el puente corriendo en segundo plano en `http://127.0.0.1:8765` y crea un acceso directo en el Inicio de Windows para que arranque solo cada vez que prendas el PC.

* **Opción B — Arranque Manual:**
  Haz doble clic en **`bridge\iniciar_puente.bat`** cada vez que vayas a operar (deja la ventana negra abierta).

### Paso 4: Instalar la Extensión en Google Chrome
1. Abre **Google Chrome** y ve a la dirección:
   `chrome://extensions`
2. Activa arriba a la derecha el interruptor **Modo de desarrollador (Developer mode)**.
3. Haz clic en **Cargar descomprimida (Load unpacked)**.
4. Selecciona la carpeta **`chrome_extension`** dentro de `C:\mt5-sp500\chrome_extension`.
5. Verifica que aparezca activa **CME QuikStrike -> MT5 Open Interest Bridge**.

---

## Uso Diario en Operativa

1. Entra a tu cuenta en CME Group y abre el heatmap:
   `https://www.cmegroup.com/tools-information/quikstrike/open-interest-heatmap.html`
2. En el selector de producto elige **`S&P 500 (ES|ES)`** (o `NQ|NQ`, `GC`, `CL`, etc.).
3. En la barra superior del heatmap, cambia **`Strikes: 15`** a **`All`** (o `100`) para que cargue todo el rango de ±300 puntos.
4. Haz clic en el botón verde **`📤 Enviar Strikes a MT5`** (arriba a la derecha dentro del heatmap).
5. Verás una notificación verde confirmando cuántos niveles se enviaron y el offset aplicado (`US500 (offset -20)`).
6. En pocos segundos (o cambiando 1 segundo de temporalidad en MT5), tu gráfico mostrará automáticamente:
   - La línea gris **`OPEN DIA`** como referencia.
   - Los strikes más grandes en **±300 puntos** (línea verde para **CALL** dominante, línea roja para **PUT** dominante, y líneas más gruesas para los muros principales).

---

## Ajuste de Base (`ES` → `US500`)
* Por defecto, `bridge\cme_mt5_bridge.py` resta **`-20.0` puntos** a todos los strikes de **`ES`** para empatar con `US500` de IC Markets.
* Si en algún vencimiento futuro cambia la diferencia entre el futuro `ES` y `US500`, puedes ajustarla de dos maneras:
  - **En el gráfico de MT5:** parámetro **`InpExtraOffset`** de `CME_OpenInterest_Levels` (ej. `+2.0` o `-3.0`).
  - **En el puente:** editando el valor `-20.0` en la línea `"ES": ("US500", False, 1.0, -20.0)` de `bridge/cme_mt5_bridge.py`.
