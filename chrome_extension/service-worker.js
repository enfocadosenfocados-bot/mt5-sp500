// Service worker MV3: reenvia los datos extraidos desde QuikStrike hacia el puente local Python -> MT5
const BRIDGE_URL = "http://127.0.0.1:8765/update";

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message && message.type === "SEND_CME_OI") {
    (async () => {
      try {
        const res = await fetch(BRIDGE_URL, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(message.payload)
        });
        if (!res.ok) {
          sendResponse({ ok: false, error: `HTTP ${res.status}` });
          return;
        }
        const data = await res.json();
        sendResponse({ ok: true, data });
      } catch (err) {
        sendResponse({
          ok: false,
          error: "Puente local no activo en puerto 8765. Inicia cme_mt5_bridge.py"
        });
      }
    })();
    return true;
  }
});
