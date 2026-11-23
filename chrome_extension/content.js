// Content Script ejecutado directamente dentro del iframe de https://cmegroup-tools.quikstrike.net/*
(() => {
  if (document.getElementById("cme-mt5-sync-btn")) return;

  function detectProductCode() {
    const bodyText = document.body ? document.body.innerText : "";
    const match = bodyText.match(/\(([A-Z0-9]{1,5})\|([A-Z0-9]{1,5})\)/);
    if (match) return match[2].toUpperCase();

    const h = document.querySelector("h1, h2, h3, .title, .header-title");
    if (h) {
      const m2 = h.innerText.match(/\(([A-Z0-9]{1,5})\|([A-Z0-9]{1,5})\)/);
      if (m2) return m2[2].toUpperCase();
    }
    return "UNKNOWN";
  }

  function parseStrike(raw) {
    const s = (raw || "").trim();
    if (!s) return NaN;
    // Ej. "27,500" o "27,500.25" (miles con coma)
    if (/^\d{1,3}(,\d{3})+(\.\d+)?$/.test(s)) return parseFloat(s.replace(/,/g, ""));
    // Ej. "27.500" o "27.500,25" (miles con punto)
    if (/^\d{1,3}(\.\d{3})+(,\d+)?$/.test(s)) return parseFloat(s.replace(/\./g, "").replace(",", "."));
    // Ej. "7197,25" o "1,0550" (decimal con coma)
    if (s.includes(",") && !s.includes(".")) return parseFloat(s.replace(",", "."));
    return parseFloat(s);
  }

  function parseOI(raw) {
    // El Open Interest siempre es entero; elimina puntos y comas de miles ("3.489" -> 3489, "3,489" -> 3489)
    const digits = (raw || "").replace(/[^\d]/g, "");
    return digits ? parseInt(digits, 10) : 0;
  }

  function extractHeatmapData() {
    const cmeCode = detectProductCode();
    let expiration = "Operativa Hoy";

    const headers = Array.from(document.querySelectorAll("th, thead td"));
    for (const h of headers) {
      const t = (h.innerText || "").trim().replace(/\s+/g, " ");
      if (/DTE/i.test(t) || /\d+\s*d/i.test(t) || /(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2}/i.test(t)) {
        expiration = t.slice(0, 28);
        break;
      }
    }

    const calls = [];
    const puts = [];

    const tables = Array.from(document.querySelectorAll("table"));
    let bestRows = [];
    for (const tbl of tables) {
      const rows = Array.from(tbl.querySelectorAll("tr"));
      if (rows.length > bestRows.length) {
        bestRows = rows;
      }
    }

    for (const row of bestRows) {
      const cells = Array.from(row.querySelectorAll("td")).map(td => (td.innerText || "").trim());
      if (cells.length < 3) continue;

      const strike = parseStrike(cells[0]);
      const callOi = parseOI(cells[1]);
      const putOi  = parseOI(cells[2]);

      if (!isNaN(strike) && strike > 0) {
        if (callOi > 0) calls.push({ strike, oi: callOi });
        if (putOi > 0)  puts.push({ strike, oi: putOi });
      }
    }

    calls.sort((a, b) => b.oi - a.oi);
    puts.sort((a, b) => b.oi - a.oi);

    return {
      cme_code: cmeCode,
      expiration,
      call1: calls[0] || { strike: 0, oi: 0 },
      call2: calls[1] || { strike: 0, oi: 0 },
      put1:  puts[0]  || { strike: 0, oi: 0 },
      put2:  puts[1]  || { strike: 0, oi: 0 },
      // Enviamos TODOS los strikes extraidos de la tabla ordenados por mayor OI
      all_calls: calls,
      all_puts:  puts,
      total_rows_scanned: bestRows.length
    };
  }

  function showToast(msg, ok = true) {
    let toast = document.getElementById("cme-mt5-toast");
    if (!toast) {
      toast = document.createElement("div");
      toast.id = "cme-mt5-toast";
      Object.assign(toast.style, {
        position: "fixed",
        top: "52px",
        right: "14px",
        zIndex: "999999",
        padding: "10px 14px",
        borderRadius: "8px",
        fontFamily: "Segoe UI, Arial, sans-serif",
        fontSize: "12px",
        fontWeight: "600",
        color: "#ffffff",
        boxShadow: "0 4px 16px rgba(0,0,0,0.35)",
        maxWidth: "380px",
        transition: "opacity 0.25s ease"
      });
      document.body.appendChild(toast);
    }
    toast.style.background = ok ? "#0f766e" : "#b91c1c";
    toast.textContent = msg;
    toast.style.opacity = "1";
    clearTimeout(toast._timer);
    toast._timer = setTimeout(() => {
      toast.style.opacity = "0";
    }, 5500);
  }

  function mountButton() {
    if (!document.body || document.getElementById("cme-mt5-sync-btn")) return;

    const btn = document.createElement("button");
    btn.id = "cme-mt5-sync-btn";
    btn.type = "button";
    btn.textContent = "📤 Enviar Strikes a MT5";
    Object.assign(btn.style, {
      position: "fixed",
      top: "10px",
      right: "14px",
      zIndex: "999999",
      padding: "8px 14px",
      background: "#16a34a",
      color: "#ffffff",
      border: "1px solid #15803d",
      borderRadius: "8px",
      cursor: "pointer",
      fontFamily: "Segoe UI, Arial, sans-serif",
      fontSize: "12px",
      fontWeight: "700",
      boxShadow: "0 3px 10px rgba(0,0,0,0.3)"
    });

    btn.addEventListener("click", async () => {
      const payload = extractHeatmapData();
      if (payload.call1.strike === 0 && payload.put1.strike === 0) {
        showToast("No se detectaron filas de Open Interest todavia. Espera a que cargue la matriz.", false);
        return;
      }

      btn.disabled = true;
      btn.textContent = "Enviando...";
      try {
        const resp = await chrome.runtime.sendMessage({
          type: "SEND_CME_OI",
          payload
        });
        if (resp && resp.ok) {
          const d = resp.data;
          const offTxt = d.offset !== 0 ? ` (offset ${d.offset > 0 ? "+" : ""}${d.offset})` : "";
          showToast(
            `✅ ${d.mt5_symbol}${offTxt} enviado (${d.total_levels} niveles) | C1: ${d.call1} | P1: ${d.put1}`,
            true
          );
        } else {
          showToast(`❌ ${resp ? resp.error : "Error al enviar a MT5"}`, false);
        }
      } catch (e) {
        showToast(`❌ Error de extension: ${e.message}`, false);
      } finally {
        btn.disabled = false;
        btn.textContent = "📤 Enviar Strikes a MT5";
      }
    });

    document.body.appendChild(btn);
  }

  mountButton();
})();
