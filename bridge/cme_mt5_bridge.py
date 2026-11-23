r"""
=============================================================================
PUENTE LOCAL CME QUIKSTRIKE (CHROME EXTENSION) -> METATRADER 5 (IC MARKETS)
=============================================================================
Escucha en http://127.0.0.1:8765/update sin dependencias externas (solo stdlib).
Recibe todos los strikes grandes con mayor Open Interest desde la extension de
Chrome, aplica el ajuste de base Futuro->CFD (ej. ES -> US500: -20 puntos) y
actualiza automaticamente:
  1) %APPDATA%\MetaQuotes\Terminal\Common\Files\CME_OpenInterest.csv (Top 4)
  2) %APPDATA%\MetaQuotes\Terminal\Common\Files\CME_OpenInterest_Full.csv (Todos)
=============================================================================
"""

import os
import csv
import json
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler

HOST = "127.0.0.1"
PORT = 8765

# Mapeo CME_CODE -> (MT5_PREFIX, INVERT_FX, SCALE, PRICE_OFFSET)
# Nota: ES (Futuro S&P 500 CME) cotiza ~20 puntos arriba de US500 (IC Markets) => offset = -20.0
CME_TO_MT5 = {
    "NQ":  ("USTEC",  False, 1.0,   0.0),
    "ES":  ("US500",  False, 1.0, -20.0),
    "RTY": ("US2000", False, 1.0,   0.0),
    "RTO": ("US2000", False, 1.0,   0.0),
    "YM":  ("US30",   False, 1.0,   0.0),
    "GC":  ("XAUUSD", False, 1.0,   0.0),
    "OG":  ("XAUUSD", False, 1.0,   0.0),
    "SI":  ("XAGUSD", False, 1.0,   0.0),
    "SO":  ("XAGUSD", False, 1.0,   0.0),
    "CL":  ("XTIUSD", False, 1.0,   0.0),
    "LO":  ("XTIUSD", False, 1.0,   0.0),
    "ZC":  ("Corn",   False, 1.0,   0.0),
    "OZC": ("Corn",   False, 1.0,   0.0),
    "ZW":  ("Wheat",  False, 1.0,   0.0),
    "OZW": ("Wheat",  False, 1.0,   0.0),
    "ZS":  ("Sbean",  False, 1.0,   0.0),
    "OZS": ("Sbean",  False, 1.0,   0.0),
    "FV":  ("FV_",    False, 1.0,   0.0),
    "TY":  ("TY_",    False, 1.0,   0.0),
    "TN":  ("TY_",    False, 1.0,   0.0),
    "US":  ("US_",    False, 1.0,   0.0),
    "6E":  ("EURUSD", False, 1.0,   0.0),
    "EUU": ("EURUSD", False, 1.0,   0.0),
    "6A":  ("AUDUSD", False, 1.0,   0.0),
    "ADU": ("AUDUSD", False, 1.0,   0.0),
    "6B":  ("GBPUSD", False, 1.0,   0.0),
    "GBU": ("GBPUSD", False, 1.0,   0.0),
    "6C":  ("USDCAD", True,  1.0,   0.0),
    "CAU": ("USDCAD", True,  1.0,   0.0),
    "6S":  ("USDCHF", True,  1.0,   0.0),
    "CHU": ("USDCHF", True,  1.0,   0.0),
    "6J":  ("USDJPY", True,  100.0, 0.0),
    "JPU": ("USDJPY", True,  100.0, 0.0),
}

HEADERS_TOP4 = [
    "SYMBOL_PREFIX", "CME_CODE", "EXPIRATION",
    "CALL1_STRIKE", "CALL1_OI", "CALL2_STRIKE", "CALL2_OI",
    "PUT1_STRIKE", "PUT1_OI", "PUT2_STRIKE", "PUT2_OI", "UPDATED"
]

HEADERS_FULL = [
    "SYMBOL_PREFIX", "CME_CODE", "EXPIRATION",
    "TYPE", "STRIKE", "OI", "UPDATED"
]


def get_dirs():
    appdata = os.environ.get("APPDATA", "")
    common_dir = os.path.join(appdata, "MetaQuotes", "Terminal", "Common", "Files")
    os.makedirs(common_dir, exist_ok=True)
    local_dir = os.path.dirname(os.path.abspath(__file__))
    return [common_dir, local_dir]


def convert_strike(val, invert_fx, scale, offset):
    val = float(val or 0.0)
    if val <= 0:
        return 0.0
    if invert_fx:
        base = (1.0 / val) * scale if val > 0.1 else (1.0 / val)
        return round(base + offset, 5)
    return round((val * scale) + offset, 5)


def upsert_csv_data(payload):
    cme_code = str(payload.get("cme_code", "UNKNOWN")).upper().strip()
    mt5_prefix, invert_fx, scale, offset = CME_TO_MT5.get(cme_code, (cme_code, False, 1.0, 0.0))

    raw_calls = payload.get("all_calls") or []
    raw_puts = payload.get("all_puts") or []

    if not raw_calls:
        for k in ("call1", "call2"):
            if payload.get(k, {}).get("strike", 0) > 0:
                raw_calls.append(payload[k])
    if not raw_puts:
        for k in ("put1", "put2"):
            if payload.get(k, {}).get("strike", 0) > 0:
                raw_puts.append(payload[k])

    conv_calls = [
        {"strike": convert_strike(x.get("strike", 0), invert_fx, scale, offset), "oi": int(x.get("oi", 0))}
        for x in raw_calls if float(x.get("strike", 0) or 0) > 0
    ]
    conv_puts = [
        {"strike": convert_strike(x.get("strike", 0), invert_fx, scale, offset), "oi": int(x.get("oi", 0))}
        for x in raw_puts if float(x.get("strike", 0) or 0) > 0
    ]

    if invert_fx:
        conv_calls, conv_puts = conv_puts, conv_calls

    conv_calls.sort(key=lambda x: x["oi"], reverse=True)
    conv_puts.sort(key=lambda x: x["oi"], reverse=True)

    c1 = conv_calls[0] if len(conv_calls) > 0 else {"strike": 0.0, "oi": 0}
    c2 = conv_calls[1] if len(conv_calls) > 1 else {"strike": 0.0, "oi": 0}
    p1 = conv_puts[0]  if len(conv_puts)  > 0 else {"strike": 0.0, "oi": 0}
    p2 = conv_puts[1]  if len(conv_puts)  > 1 else {"strike": 0.0, "oi": 0}

    exp = str(payload.get("expiration", "Hoy")).replace(",", " ").strip()
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M")

    top4_row = [
        mt5_prefix, cme_code, exp,
        c1["strike"], c1["oi"], c2["strike"], c2["oi"],
        p1["strike"], p1["oi"], p2["strike"], p2["oi"],
        now_str
    ]

    full_new_rows = []
    for item in conv_calls:
        full_new_rows.append([mt5_prefix, cme_code, exp, "CALL", item["strike"], item["oi"], now_str])
    for item in conv_puts:
        full_new_rows.append([mt5_prefix, cme_code, exp, "PUT", item["strike"], item["oi"], now_str])

    for d in get_dirs():
        # 1. Actualizar CME_OpenInterest.csv (Top 4)
        top4_path = os.path.join(d, "CME_OpenInterest.csv")
        rows = []
        found = False
        if os.path.exists(top4_path):
            with open(top4_path, "r", newline="", encoding="utf-8") as f:
                for idx, row in enumerate(csv.reader(f)):
                    if idx == 0 or not row:
                        continue
                    if row[0].upper() == mt5_prefix.upper():
                        rows.append(top4_row)
                        found = True
                    else:
                        rows.append(row)
        if not found:
            rows.append(top4_row)
        with open(top4_path, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(HEADERS_TOP4)
            w.writerows(rows)

        # 2. Actualizar CME_OpenInterest_Full.csv (Todos los strikes grandes)
        full_path = os.path.join(d, "CME_OpenInterest_Full.csv")
        kept_rows = []
        if os.path.exists(full_path):
            with open(full_path, "r", newline="", encoding="utf-8") as f:
                for idx, row in enumerate(csv.reader(f)):
                    if idx == 0 or not row:
                        continue
                    if row[0].upper() != mt5_prefix.upper():
                        kept_rows.append(row)
        kept_rows.extend(full_new_rows)
        with open(full_path, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(HEADERS_FULL)
            w.writerows(kept_rows)

    print(f"[{now_str}] ACTUALIZADO {mt5_prefix} ({cme_code}, offset {offset}) -> {len(full_new_rows)} strikes | C1:{c1['strike']} ({c1['oi']}) | P1:{p1['strike']} ({p1['oi']})")
    return {
        "mt5_symbol": mt5_prefix,
        "cme_code": cme_code,
        "offset": offset,
        "total_levels": len(full_new_rows),
        "call1": c1["strike"],
        "call2": c2["strike"],
        "put1": p1["strike"],
        "put2": p2["strike"],
    }


class BridgeHandler(BaseHTTPRequestHandler):
    def _send_json(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        self._send_json(200, {"status": "ok", "service": "CME-MT5 Bridge", "port": PORT, "es_offset": -20.0})

    def do_POST(self):
        if self.path != "/update":
            self._send_json(404, {"error": "Not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length)
            payload = json.loads(raw.decode("utf-8"))
            res = upsert_csv_data(payload)
            self._send_json(200, res)
        except Exception as e:
            self._send_json(500, {"error": str(e)})

    def log_message(self, format, *args):
        return


if __name__ == "__main__":
    print(f"[*] Puente CME QuikStrike -> MT5 escuchando en http://{HOST}:{PORT}")
    print(f"[*] Carpeta MT5: {get_dirs()[0]}")
    HTTPServer((HOST, PORT), BridgeHandler).serve_forever()
