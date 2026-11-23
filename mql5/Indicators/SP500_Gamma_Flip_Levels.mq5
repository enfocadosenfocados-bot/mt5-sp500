//+------------------------------------------------------------------+
//|                                     SP500_Gamma_Flip_Levels.mq5  |
//|         SPX / ES Gamma Flip, Call/Put Walls & GEX Regime HUD     |
//|     Data source: github.com/dhawalc/spx-gamma-levels (CBOE)      |
//+------------------------------------------------------------------+
#property copyright "Antigravity Quant Tools"
#property version   "1.10"
#property indicator_chart_window
#property indicator_plots 0

//--- Input Parameters
input group "=== Fuente de Datos ==="
input string   InpJsonFileName     = "gex_latest.json"; // Archivo en MQL5\Files\
input int      InpRefreshSeconds   = 60;     // Re-leer archivo cada N segundos

input group "=== Ajuste de Plataforma (Basis / Diferencia de Puntos) ==="
input double   InpBasisOffset      = 0.0;    // Ajuste en puntos (0.0 para SPX->US500 | -20.0 si metes datos de Futuro ES)

input group "=== Niveles Manuales (Si no existe el JSON o quieres sobreescribir) ==="
input bool     InpUseManualLevels  = false;  // Usar niveles manuales en lugar del JSON
input double   InpManualFlip       = 7428.50;// Gamma Flip manual
input double   InpManualVolTrigger = 7438.36;// Vol Trigger manual
input double   InpManualCallWall   = 8100.00;// Call Wall manual
input double   InpManualPutWall    = 7100.00;// Put Wall manual
input double   InpManualAbsGamma   = 7000.00;// Abs Gamma Strike manual

input group "=== Apariencia y Panel ==="
input bool     InpShowPanel        = true;   // Mostrar panel de estado GEX
input bool     InpShowGuidePanel   = true;   // Mostrar recuadro explicativo al lado
input ENUM_BASE_CORNER InpPanelCorner = CORNER_RIGHT_UPPER; // Esquina del panel (no tapa tu panel izquierdo)
input bool     InpShowLineLabels   = true;   // Mostrar etiquetas de texto en las lineas
input color    InpColorFlip        = clrGold;        // Color Gamma Flip
input color    InpColorVolTrigger  = clrOrange;      // Color Vol Trigger
input color    InpColorCallWall    = clrLimeGreen;   // Color Call Wall
input color    InpColorPutWall     = clrTomato;      // Color Put Wall
input color    InpColorAbsGamma    = clrDeepSkyBlue; // Color Abs Gamma Strike

//--- Constants
const string   PREFIX = "GEX_IND_";

//--- Global State
double   g_flip       = 0.0;
double   g_volTrigger = 0.0;
double   g_callWall   = 0.0;
double   g_putWall    = 0.0;
double   g_absGamma   = 0.0;
double   g_netGexB    = 0.0;
double   g_spxSpot    = 0.0;
string   g_date       = "-";
string   g_oiDate     = "-";
string   g_regime     = "-";
string   g_statusMsg  = "Inicializando...";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   EventSetTimer(MathMax(5, InpRefreshSeconds));
   LoadLevels();
   DrawAll();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, PREFIX);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   LoadLevels();
   DrawAll();
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total > 0)
      UpdatePanel(close[rates_total - 1]);
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Load levels from manual inputs or MQL5\Files\gex_latest.json     |
//+------------------------------------------------------------------+
void LoadLevels()
{
   if(InpUseManualLevels)
   {
      ApplyManual("Modo Manual Activo");
      return;
   }

   if(FileIsExist(InpJsonFileName))
   {
      int handle = FileOpen(InpJsonFileName, FILE_READ | FILE_TXT | FILE_ANSI);
      if(handle != INVALID_HANDLE)
      {
         string json = "";
         while(!FileIsEnding(handle))
            json += FileReadString(handle) + "\n";
         FileClose(handle);

         double rawFlip    = ExtractJsonDouble(json, "zero_gamma_flip");
         double rawTrigger = ExtractJsonDouble(json, "vol_trigger");
         double rawCall    = ExtractJsonDouble(json, "call_wall");
         double rawPut     = ExtractJsonDouble(json, "put_wall");
         double rawAbs     = ExtractJsonDouble(json, "abs_gamma_strike");
         double rawNetGex  = ExtractJsonDouble(json, "net_gex_dollars");
         g_spxSpot         = ExtractJsonDouble(json, "spot");
         g_date            = ExtractJsonString(json, "date");
         g_oiDate          = ExtractJsonString(json, "oi_settle_date");
         g_regime          = ExtractJsonString(json, "gamma_regime");

         if(rawFlip > 0.0)
         {
            g_flip       = rawFlip + InpBasisOffset;
            g_volTrigger = (rawTrigger > 0.0) ? (rawTrigger + InpBasisOffset) : 0.0;
            g_callWall   = (rawCall > 0.0)    ? (rawCall + InpBasisOffset)    : 0.0;
            g_putWall    = (rawPut > 0.0)     ? (rawPut + InpBasisOffset)     : 0.0;
            g_absGamma   = (rawAbs > 0.0)     ? (rawAbs + InpBasisOffset)     : 0.0;
            g_netGexB    = rawNetGex / 1e9;
            g_statusMsg  = "JSON OK (" + InpJsonFileName + ")";
            return;
         }
      }
   }

   ApplyManual("Fallback Manual (Sin JSON)");
}

//+------------------------------------------------------------------+
//| Apply manual fallback levels                                     |
//+------------------------------------------------------------------+
void ApplyManual(string msg)
{
   g_flip       = InpManualFlip + InpBasisOffset;
   g_volTrigger = InpManualVolTrigger + InpBasisOffset;
   g_callWall   = InpManualCallWall + InpBasisOffset;
   g_putWall    = InpManualPutWall + InpBasisOffset;
   g_absGamma   = InpManualAbsGamma + InpBasisOffset;
   g_date       = "Manual";
   g_oiDate     = "Manual";
   g_statusMsg  = msg;
}

//+------------------------------------------------------------------+
//| Draw all lines and HUD panel                                     |
//+------------------------------------------------------------------+
void DrawAll()
{
   DrawLevelLine("Flip",       g_flip,       InpColorFlip,       STYLE_SOLID, 2, "GAMMA FLIP (Zero GEX)");
   DrawLevelLine("VolTrigger", g_volTrigger, InpColorVolTrigger, STYLE_DASH,  1, "VOL TRIGGER");
   DrawLevelLine("CallWall",   g_callWall,   InpColorCallWall,   STYLE_SOLID, 2, "CALL WALL");
   DrawLevelLine("PutWall",    g_putWall,    InpColorPutWall,    STYLE_SOLID, 2, "PUT WALL");
   DrawLevelLine("AbsGamma",   g_absGamma,   InpColorAbsGamma,   STYLE_DOT,   1, "ABS GAMMA");

   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   UpdatePanel(price);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Draw horizontal line + optional label                            |
//+------------------------------------------------------------------+
void DrawLevelLine(string id, double price, color clr, ENUM_LINE_STYLE style, int width, string title)
{
   string lineName  = PREFIX + "LINE_" + id;
   string labelName = PREFIX + "LBL_" + id;

   if(price <= 0.0)
   {
      ObjectDelete(0, lineName);
      ObjectDelete(0, labelName);
      return;
   }

   if(ObjectFind(0, lineName) < 0)
      ObjectCreate(0, lineName, OBJ_HLINE, 0, 0, price);

   ObjectSetDouble(0, lineName, OBJPROP_PRICE, price);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, style);
   ObjectSetInteger(0, lineName, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, lineName, OBJPROP_BACK, true);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);

   if(InpShowLineLabels)
   {
      datetime tRight = iTime(_Symbol, PERIOD_CURRENT, 0) + PeriodSeconds(PERIOD_CURRENT) * 4;
      if(ObjectFind(0, labelName) < 0)
         ObjectCreate(0, labelName, OBJ_TEXT, 0, tRight, price);

      ObjectSetInteger(0, labelName, OBJPROP_TIME, tRight);
      ObjectSetDouble(0, labelName, OBJPROP_PRICE, price);
      ObjectSetString(0, labelName, OBJPROP_TEXT, StringFormat("  %s (%.2f)", title, price));
      ObjectSetInteger(0, labelName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, labelName, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
   }
   else
   {
      ObjectDelete(0, labelName);
   }
}

//+------------------------------------------------------------------+
//| Update HUD Panel                                                 |
//+------------------------------------------------------------------+
void UpdatePanel(double currentPrice)
{
   if(!InpShowPanel)
   {
      ObjectsDeleteAll(0, PREFIX + "HUD_");
      return;
   }

   string bgName = PREFIX + "HUD_BG";
   int xBase = (InpPanelCorner == CORNER_RIGHT_UPPER || InpPanelCorner == CORNER_RIGHT_LOWER) ? 285 : 15;
   int yBase = (InpPanelCorner == CORNER_LEFT_LOWER  || InpPanelCorner == CORNER_RIGHT_LOWER) ? 210 : 25;

   if(ObjectFind(0, bgName) < 0)
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);

   ObjectSetInteger(0, bgName, OBJPROP_CORNER, InpPanelCorner);
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, xBase);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, yBase);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, 270);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, 195);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, C'18,22,30');
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_COLOR, C'60,70,90');
   ObjectSetInteger(0, bgName, OBJPROP_BACK, false);
   ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);

   // Determine live regime relative to Gamma Flip
   string liveRegime = "NEUTRAL";
   color  regimeClr  = clrGold;
   double distFlip   = (g_flip > 0.0) ? (currentPrice - g_flip) : 0.0;

   if(g_flip > 0.0)
   {
      if(MathAbs(distFlip) <= (currentPrice * 0.002))
      {
         liveRegime = "NEUTRAL (Sobre Flip)";
         regimeClr  = clrGold;
      }
      else if(distFlip > 0.0)
      {
         liveRegime = "GEX POSITIVO (Rango/Rebotes)";
         regimeClr  = clrLimeGreen;
      }
      else
      {
         liveRegime = "GEX NEGATIVO (Volatilidad)";
         regimeClr  = clrTomato;
      }
   }

   int xText = (InpPanelCorner == CORNER_RIGHT_UPPER || InpPanelCorner == CORNER_RIGHT_LOWER) ? (xBase - 12) : (xBase + 12);
   bool isLower = (InpPanelCorner == CORNER_LEFT_LOWER || InpPanelCorner == CORNER_RIGHT_LOWER);
   int yDir  = isLower ? -1 : 1;
   int yStep = 17;

   SetHudText("T0", xText, yBase + yDir * (8 + yStep * 0), "SP500 GAMMA FLIP & WALLS", clrWhite, 9, true);
   SetHudText("T1", xText, yBase + yDir * (8 + yStep * 1), "Regimen: " + liveRegime, regimeClr, 8, true);
   SetHudText("T2", xText, yBase + yDir * (8 + yStep * 2), StringFormat("Gamma Flip : %.2f (Dist: %+.1f)", g_flip, distFlip), InpColorFlip, 8, false);
   SetHudText("T3", xText, yBase + yDir * (8 + yStep * 3), StringFormat("Vol Trigger: %.2f", g_volTrigger), InpColorVolTrigger, 8, false);
   SetHudText("T4", xText, yBase + yDir * (8 + yStep * 4), StringFormat("Call Wall  : %.2f", g_callWall), InpColorCallWall, 8, false);
   SetHudText("T5", xText, yBase + yDir * (8 + yStep * 5), StringFormat("Put Wall   : %.2f", g_putWall), InpColorPutWall, 8, false);
   SetHudText("T6", xText, yBase + yDir * (8 + yStep * 6), StringFormat("Abs Gamma  : %.2f", g_absGamma), InpColorAbsGamma, 8, false);
   SetHudText("T7", xText, yBase + yDir * (8 + yStep * 7), StringFormat("Net GEX: $%.2fB | Basis: %+.1f", g_netGexB, InpBasisOffset), clrSilver, 8, false);
   SetHudText("T8", xText, yBase + yDir * (8 + yStep * 8), StringFormat("Fecha: %s (OI: %s)", g_date, g_oiDate), clrDarkGray, 8, false);
   SetHudText("T9", xText, yBase + yDir * (8 + yStep * 9), "Estado: " + g_statusMsg, clrSilver, 8, false);

   UpdateGuidePanel(currentPrice, distFlip);
}

//+------------------------------------------------------------------+
//| Update Side Guide & Live Market Interpretation Panel             |
//+------------------------------------------------------------------+
void UpdateGuidePanel(double currentPrice, double distFlip)
{
   if(!InpShowGuidePanel)
   {
      ObjectsDeleteAll(0, PREFIX + "GUIDE_");
      return;
   }

   bool isRight = (InpPanelCorner == CORNER_RIGHT_UPPER || InpPanelCorner == CORNER_RIGHT_LOWER);
   bool isLower = (InpPanelCorner == CORNER_LEFT_LOWER  || InpPanelCorner == CORNER_RIGHT_LOWER);

   int gWidth  = 430;
   int gHeight = 232;
   int xBase   = isRight ? 285 : 15;
   int gXBase  = isRight ? (xBase + 10 + gWidth) : (xBase + 270 + 10);
   int gYBase  = isLower ? (gHeight + 15) : 25;

   string bgName = PREFIX + "GUIDE_BG";
   if(ObjectFind(0, bgName) < 0)
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);

   ObjectSetInteger(0, bgName, OBJPROP_CORNER, InpPanelCorner);
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, gXBase);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, gYBase);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, gWidth);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, gHeight);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, C'18,22,30');
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_COLOR, C'60,70,90');
   ObjectSetInteger(0, bgName, OBJPROP_BACK, false);
   ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);

   // Dynamic live interpretation of current market state
   string liveState = "Esperando niveles...";
   color  liveClr   = clrSilver;

   if(g_flip > 0.0 && currentPrice > 0.0)
   {
      if(distFlip > 0.0)
      {
         if(g_callWall > 0.0 && MathAbs(currentPrice - g_callWall) <= currentPrice * 0.003)
         {
            liveState = "AHORA: Cerca de CALL WALL -> Techo, posible freno/giro bajista.";
            liveClr   = InpColorCallWall;
         }
         else
         {
            liveState = "AHORA: Sobre FLIP (+GEX) -> MMs frenan velas; operar rebotes.";
            liveClr   = clrLimeGreen;
         }
      }
      else
      {
         if(g_putWall > 0.0 && currentPrice < g_putWall)
         {
            liveState = "AHORA: Bajo PUT WALL (-GEX) -> Panico/aceleracion bajista!";
            liveClr   = clrTomato;
         }
         else if(g_putWall > 0.0 && MathAbs(currentPrice - g_putWall) <= currentPrice * 0.003)
         {
            liveState = "AHORA: Sobre PUT WALL (-GEX) -> Zona critica: rebote o cascada.";
            liveClr   = clrOrange;
         }
         else
         {
            liveState = "AHORA: Bajo FLIP (-GEX) -> Alta volatilidad; MMs persiguen precio.";
            liveClr   = clrTomato;
         }
      }

      if(g_absGamma > 0.0 && MathAbs(currentPrice - g_absGamma) <= currentPrice * 0.0035)
      {
         liveState += " [Iman ABS]";
      }
   }

   int xText = isRight ? (gXBase - 12) : (gXBase + 12);
   int yDir  = isLower ? -1 : 1;
   int yStep = 16;

   SetGuideText("G0",  xText, gYBase + yDir * (8 + yStep * 0),  "GUIA RAPIDA: QUE ESTA PASANDO EN EL MERCADO", clrWhite, 9, true);
   SetGuideText("G1",  xText, gYBase + yDir * (8 + yStep * 1),  liveState, liveClr, 8, true);
   SetGuideText("G2",  xText, gYBase + yDir * (8 + yStep * 2),  "-------------------------------------------------------------------", C'60,70,90', 8, false);
   SetGuideText("G3",  xText, gYBase + yDir * (8 + yStep * 3),  "1. GAMMA FLIP (Dorada): Interruptor del mercado (GEX = 0)", InpColorFlip, 8, true);
   SetGuideText("G4",  xText, gYBase + yDir * (8 + yStep * 4),  "   Arriba: MMs compran caidas/venden subidas (Rango/Rebotes)", clrSilver, 8, false);
   SetGuideText("G5",  xText, gYBase + yDir * (8 + yStep * 5),  "   Abajo : MMs persiguen precio (Tendencia rapida/Panico)", clrSilver, 8, false);
   SetGuideText("G6",  xText, gYBase + yDir * (8 + yStep * 6),  "2. VOL TRIGGER (Naranja): Alarma temprana; perderlo dispara vol.", InpColorVolTrigger, 8, false);
   SetGuideText("G7",  xText, gYBase + yDir * (8 + yStep * 7),  "3. CALL WALL (Verde): Techo maximo; MMs venden futuros al llegar", InpColorCallWall, 8, false);
   SetGuideText("G8",  xText, gYBase + yDir * (8 + yStep * 8),  "4. PUT WALL (Roja): Suelo principal (+GEX=Rebote | -GEX=Acelera)", InpColorPutWall, 8, false);
   SetGuideText("G9",  xText, gYBase + yDir * (8 + yStep * 9),  "   Si rompe Put Wall en -GEX, acelera fuerte hacia abajo", clrSilver, 8, false);
   SetGuideText("G10", xText, gYBase + yDir * (8 + yStep * 10), "5. ABS GAMMA (Azul): Iman de liquidez; pausas y consolidacion", InpColorAbsGamma, 8, false);
   SetGuideText("G11", xText, gYBase + yDir * (8 + yStep * 11), "   Mayor concentracion total de Gamma: atrae el precio", clrSilver, 8, false);
}

//+------------------------------------------------------------------+
//| Helper to draw Guide text                                        |
//+------------------------------------------------------------------+
void SetGuideText(string id, int x, int y, string text, color clr, int fontSize, bool bold)
{
   string name = PREFIX + "GUIDE_" + id;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, InpPanelCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Consolas Bold" : "Consolas");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Helper to draw HUD text                                          |
//+------------------------------------------------------------------+
void SetHudText(string id, int x, int y, string text, color clr, int fontSize, bool bold)
{
   string name = PREFIX + "HUD_" + id;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, InpPanelCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Consolas Bold" : "Consolas");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Minimal JSON String Extractor                                    |
//+------------------------------------------------------------------+
string ExtractJsonString(const string &json, const string key)
{
   string pattern = "\"" + key + "\"";
   int pos = StringFind(json, pattern);
   if(pos < 0) return "";
   int colon = StringFind(json, ":", pos + StringLen(pattern));
   if(colon < 0) return "";
   int q1 = StringFind(json, "\"", colon + 1);
   if(q1 < 0) return "";
   int q2 = StringFind(json, "\"", q1 + 1);
   if(q2 < 0) return "";
   return StringSubstr(json, q1 + 1, q2 - q1 - 1);
}

//+------------------------------------------------------------------+
//| Minimal JSON Double Extractor                                    |
//+------------------------------------------------------------------+
double ExtractJsonDouble(const string &json, const string key)
{
   string pattern = "\"" + key + "\"";
   int pos = StringFind(json, pattern);
   if(pos < 0) return 0.0;
   int colon = StringFind(json, ":", pos + StringLen(pattern));
   if(colon < 0) return 0.0;

   int start = colon + 1;
   int len   = StringLen(json);
   while(start < len)
   {
      ushort ch = StringGetCharacter(json, start);
      if(ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n')
         break;
      start++;
   }

   int end = start;
   while(end < len)
   {
      ushort ch = StringGetCharacter(json, end);
      if(ch == ',' || ch == '}' || ch == ' ' || ch == '\r' || ch == '\n')
         break;
      end++;
   }

   string numStr = StringSubstr(json, start, end - start);
   return StringToDouble(numStr);
}
//+------------------------------------------------------------------+
