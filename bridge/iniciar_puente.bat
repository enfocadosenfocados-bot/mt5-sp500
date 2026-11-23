@echo off
title Puente CME QuikStrike - MT5 (Puerto 8765)
echo ============================================================
echo  Iniciando Puente Local CME QuikStrike -> MetaTrader 5
echo  No cierres esta ventana mientras uses el boton en Chrome.
echo ============================================================
python "%~dp0cme_mt5_bridge.py"
if errorlevel 1 (
    echo.
    echo [!] No se encontro 'python' en el PATH. Verifica que Python 3 este instalado.
    pause
)
