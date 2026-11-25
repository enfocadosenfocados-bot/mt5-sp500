r"""
=============================================================================
CBOE SPY & SPX 0DTE UPDATER -> METATRADER 5 (IC MARKETS US500)
=============================================================================
Descarga gratuitamente (sin login) las cadenas de opciones 0DTE desde CBOE:
  - https://cdn.cboe.com/api/global/delayed_quotes/options/SPY.json
  - https://cdn.cboe.com/api/global/delayed_quotes/options/_SPX.json

Extrae para cada strike del vencimiento 0DTE (o el mas cercano del dia):
  Vol (Volume), IV, Delta, Gamma, Int (Open Interest) para Calls y Puts.
Convierte los strikes de SPY a escala US500 usando el ratio real SPX/SPY.

Escribe automaticamente cada 5 minutos en:
  %APPDATA%\MetaQuotes\Terminal\Common\Files\CBOE_0DTE_Levels.csv
=============================================================================
"""

import os
import re
import csv
import sys
import time
import argparse
from datetime import datetime

import requests

SPY_URL = "https://cdn.cboe.com/api/global/delayed_quotes/options/SPY.json"
SPX_URL = "https://cdn.cboe.com/api/global/delayed_quotes/options/_SPX.json"

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Referer": "https://www.cboe.com/",
    "Accept": "application/json",
}

CSV_HEADERS = [
    "SOURCE", "EXPIRATION", "SPOT_REF", "RATIO", "RAW_STRIKE", "US500_STRIKE",
    "CALL_VOL", "CALL_IV", "CALL_DELTA", "CALL_GAMMA", "CALL_OI",
    "PUT_VOL", "PUT_IV", "PUT_DELTA", "PUT_GAMMA", "PUT_OI",
    "UPDATED"
]


def get_csv_paths():
    appdata = os.environ.get("APPDATA", "")
    common_dir = os.path.join(appdata, "MetaQuotes", "Terminal", "Common", "Files")
    os.makedirs(common_dir, exist_ok=True)
    common_csv = os.path.join(common_dir, "CBOE_0DTE_Levels.csv")
    local_csv = os.path.join(os.path.dirname(os.path.abspath(__file__)), "CBOE_0DTE_Levels.csv")
    return [common_csv, local_csv]


def fetch_cboe_chain(url, valid_prefixes):
    r = requests.get(url, headers=HEADERS, timeout=20)
    r.raise_for_status()
    data = r.json().get("data", {})
    spot = float(data.get("current_price") or 0.0)
    options = data.get("options", [])

    parsed = []
    for o in options:
        sym = o.get("option", "")
        m = re.match(r"^([A-Z0-9]+?)(\d{6})([CP])(\d{8})$", sym)
        if not m:
            continue
        pref, exp, cp, st_raw = m.groups()
        if pref not in valid_prefixes:
            continue
        strike = int(st_raw) / 1000.0
        parsed.append({
            "exp": exp,
            "cp": cp,
            "strike": strike,
            "vol": int(float(o.get("volume") or 0)),
            "iv": round(float(o.get("iv") or 0.0), 4),
            "delta": round(float(o.get("delta") or 0.0), 4),
            "gamma": round(float(o.get("gamma") or 0.0), 4),
            "oi": int(float(o.get("open_interest") or 0)),
        })

    if not parsed:
        return spot, "", {}

    today_yymmdd = datetime.now().strftime("%y%m%d")
    exps = sorted({x["exp"] for x in parsed if x["exp"] >= today_yymmdd})
    if not exps:
        exps = sorted({x["exp"] for x in parsed})
    front_exp = exps[0]

    by_strike = {}
    for x in parsed:
        if x["exp"] != front_exp:
            continue
        st = x["strike"]
        if st not in by_strike:
            by_strike[st] = {
                "c_vol": 0, "c_iv": 0.0, "c_delta": 0.0, "c_gamma": 0.0, "c_oi": 0,
                "p_vol": 0, "p_iv": 0.0, "p_delta": 0.0, "p_gamma": 0.0, "p_oi": 0,
            }
        if x["cp"] == "C":
            by_strike[st]["c_vol"] += x["vol"]
            by_strike[st]["c_oi"]  += x["oi"]
            by_strike[st]["c_iv"]    = x["iv"]
            by_strike[st]["c_delta"] = x["delta"]
            by_strike[st]["c_gamma"] = x["gamma"]
        else:
            by_strike[st]["p_vol"] += x["vol"]
            by_strike[st]["p_oi"]  += x["oi"]
            by_strike[st]["p_iv"]    = x["iv"]
            by_strike[st]["p_delta"] = x["delta"]
            by_strike[st]["p_gamma"] = x["gamma"]

    return spot, front_exp, by_strike


def update_once():
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    spy_spot, spy_exp, spy_map = fetch_cboe_chain(SPY_URL, {"SPY"})
    spx_spot, spx_exp, spx_map = fetch_cboe_chain(SPX_URL, {"SPX", "SPXW"})

    ratio = (spx_spot / spy_spot) if (spy_spot > 0 and spx_spot > 0) else 10.0
    rows_out = []

    for st in sorted(spy_map.keys()):
        d = spy_map[st]
        if d["c_vol"] == 0 and d["p_vol"] == 0 and d["c_oi"] == 0 and d["p_oi"] == 0:
            continue
        us500_st = round(st * ratio, 2)
        rows_out.append([
            "SPY", spy_exp, round(spy_spot, 2), round(ratio, 5), st, us500_st,
            d["c_vol"], d["c_iv"], d["c_delta"], d["c_gamma"], d["c_oi"],
            d["p_vol"], d["p_iv"], d["p_delta"], d["p_gamma"], d["p_oi"],
            now_str
        ])

    for st in sorted(spx_map.keys()):
        d = spx_map[st]
        if d["c_vol"] == 0 and d["p_vol"] == 0 and d["c_oi"] == 0 and d["p_oi"] == 0:
            continue
        rows_out.append([
            "SPX", spx_exp, round(spx_spot, 2), 1.0, st, round(st, 2),
            d["c_vol"], d["c_iv"], d["c_delta"], d["c_gamma"], d["c_oi"],
            d["p_vol"], d["p_iv"], d["p_delta"], d["p_gamma"], d["p_oi"],
            now_str
        ])

    for path in get_csv_paths():
        with open(path, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(CSV_HEADERS)
            w.writerows(rows_out)

    print(f"[{now_str}] CBOE OK | SPY:{spy_spot:.2f} (Exp:{spy_exp}) | SPX:{spx_spot:.2f} (Exp:{spx_exp}) | Ratio:{ratio:.4f} | Filas:{len(rows_out)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Actualizador CBOE SPY & SPX 0DTE para MT5")
    parser.add_argument("--once", action="store_true", help="Ejecutar una sola vez y salir")
    parser.add_argument("--interval", type=int, default=300, help="Segundos entre actualizaciones (defecto: 300 = 5 min)")
    args = parser.parse_args()

    if args.once:
        update_once()
    else:
        print(f"[*] Iniciando actualizador automatico CBOE SPY/SPX 0DTE cada {args.interval}s...")
        while True:
            try:
                update_once()
            except Exception as e:
                print(f"[!] Error consultando CBOE: {e}")
            time.sleep(max(60, args.interval))
