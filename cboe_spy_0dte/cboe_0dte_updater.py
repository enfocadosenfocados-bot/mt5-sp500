r"""
=============================================================================
CBOE SPY & SPX 0DTE UPDATER -> METATRADER 5 (IC MARKETS SPY / US500)
=============================================================================
Descarga gratuitamente (sin login) las cadenas de opciones 0DTE desde CBOE:
  - https://cdn.cboe.com/api/global/delayed_quotes/options/SPY.json
  - https://cdn.cboe.com/api/global/delayed_quotes/options/_SPX.json

Calcula y guarda en Common\Files\:
  1) CBOE_0DTE_Levels.csv  -> Strikes con Vol, IV, Delta, Gamma, OI (Int)
  2) CBOE_0DTE_Summary.csv -> Max Pain, Net GEX 0DTE, Movimiento Esperado ATM,
                              Put/Call Ratios (Vol & OI)
=============================================================================
"""

import os
import re
import csv
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

SUMMARY_HEADERS = [
    "SOURCE", "EXPIRATION", "SPOT_REF", "RATIO",
    "MAX_PAIN_RAW", "MAX_PAIN_US500", "NET_GEX_M",
    "EXP_MOVE_RAW", "EXP_MOVE_US500",
    "TOT_CALL_VOL", "TOT_PUT_VOL", "TOT_CALL_OI", "TOT_PUT_OI",
    "UPDATED"
]


def get_dirs():
    appdata = os.environ.get("APPDATA", "")
    common_dir = os.path.join(appdata, "MetaQuotes", "Terminal", "Common", "Files")
    os.makedirs(common_dir, exist_ok=True)
    local_dir = os.path.dirname(os.path.abspath(__file__))
    return [common_dir, local_dir]


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
            "bid": float(o.get("bid") or 0.0),
            "ask": float(o.get("ask") or 0.0),
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
                "c_vol": 0, "c_iv": 0.0, "c_delta": 0.0, "c_gamma": 0.0, "c_oi": 0, "c_mid": 0.0,
                "p_vol": 0, "p_iv": 0.0, "p_delta": 0.0, "p_gamma": 0.0, "p_oi": 0, "p_mid": 0.0,
            }
        mid = (x["bid"] + x["ask"]) / 2.0 if (x["bid"] > 0 or x["ask"] > 0) else 0.0
        if x["cp"] == "C":
            by_strike[st]["c_vol"] += x["vol"]
            by_strike[st]["c_oi"]  += x["oi"]
            by_strike[st]["c_iv"]    = x["iv"]
            by_strike[st]["c_delta"] = x["delta"]
            by_strike[st]["c_gamma"] = x["gamma"]
            by_strike[st]["c_mid"]   = mid
        else:
            by_strike[st]["p_vol"] += x["vol"]
            by_strike[st]["p_oi"]  += x["oi"]
            by_strike[st]["p_iv"]    = x["iv"]
            by_strike[st]["p_delta"] = x["delta"]
            by_strike[st]["p_gamma"] = x["gamma"]
            by_strike[st]["p_mid"]   = mid

    return spot, front_exp, by_strike


def compute_analytics(spot, by_strike):
    strikes = sorted(by_strike.keys())
    if not strikes or spot <= 0:
        return 0.0, 0.0, 0.0, 0, 0, 0, 0

    # 1. Max Pain
    max_pain = strikes[0]
    min_pain_val = float("inf")
    for test_st in strikes:
        pain = 0.0
        for st in strikes:
            d = by_strike[st]
            if test_st > st:
                pain += (test_st - st) * d["c_oi"]
            elif test_st < st:
                pain += (st - test_st) * d["p_oi"]
        if pain < min_pain_val:
            min_pain_val = pain
            max_pain = test_st

    # 2. Net GEX (en millones $) y totales Vol/OI
    net_gex = 0.0
    tot_c_vol, tot_p_vol, tot_c_oi, tot_p_oi = 0, 0, 0, 0
    for st in strikes:
        d = by_strike[st]
        tot_c_vol += d["c_vol"]
        tot_p_vol += d["p_vol"]
        tot_c_oi  += d["c_oi"]
        tot_p_oi  += d["p_oi"]
        net_gex += (d["c_oi"] * d["c_gamma"] - d["p_oi"] * d["p_gamma"]) * 100.0 * spot * spot * 0.01

    # 3. Movimiento Esperado (ATM Straddle * 0.85)
    atm_st = min(strikes, key=lambda s: abs(s - spot))
    exp_move = (by_strike[atm_st]["c_mid"] + by_strike[atm_st]["p_mid"]) * 0.85

    return max_pain, round(net_gex / 1e6, 2), round(exp_move, 2), tot_c_vol, tot_p_vol, tot_c_oi, tot_p_oi


def update_once():
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    spy_spot, spy_exp, spy_map = fetch_cboe_chain(SPY_URL, {"SPY"})
    spx_spot, spx_exp, spx_map = fetch_cboe_chain(SPX_URL, {"SPX", "SPXW"})

    ratio = (spx_spot / spy_spot) if (spy_spot > 0 and spx_spot > 0) else 10.0
    rows_out = []
    summary_out = []

    for src, spot, exp, mp, r_mult in (
        ("SPY", spy_spot, spy_exp, spy_map, ratio),
        ("SPX", spx_spot, spx_exp, spx_map, 1.0),
    ):
        max_pain, net_gex_m, exp_move, tcv, tpv, tco, tpo = compute_analytics(spot, mp)
        summary_out.append([
            src, exp, round(spot, 2), round(r_mult, 5),
            round(max_pain, 2), round(max_pain * r_mult, 2), net_gex_m,
            round(exp_move, 2), round(exp_move * r_mult, 2),
            tcv, tpv, tco, tpo, now_str
        ])
        for st in sorted(mp.keys()):
            d = mp[st]
            if d["c_vol"] == 0 and d["p_vol"] == 0 and d["c_oi"] == 0 and d["p_oi"] == 0:
                continue
            rows_out.append([
                src, exp, round(spot, 2), round(r_mult, 5), st, round(st * r_mult, 2),
                d["c_vol"], d["c_iv"], d["c_delta"], d["c_gamma"], d["c_oi"],
                d["p_vol"], d["p_iv"], d["p_delta"], d["p_gamma"], d["p_oi"],
                now_str
            ])

    for d_path in get_dirs():
        with open(os.path.join(d_path, "CBOE_0DTE_Levels.csv"), "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(CSV_HEADERS)
            w.writerows(rows_out)
        with open(os.path.join(d_path, "CBOE_0DTE_Summary.csv"), "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(SUMMARY_HEADERS)
            w.writerows(summary_out)

    print(f"[{now_str}] CBOE OK | SPY:{spy_spot:.2f} (Exp:{spy_exp}) | SPX:{spx_spot:.2f} | Filas:{len(rows_out)}")


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
