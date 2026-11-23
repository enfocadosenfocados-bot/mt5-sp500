//+------------------------------------------------------------------+
//|                                    US_Market_Internals_Filter.mq5|
//|   Filtro Anti-Trampas: Amplitud Real US (US2000/US30/USTEC/US500)|
//|   + Soporte automatico para $ADD / $VOLD / $TICK si existen      |
//+------------------------------------------------------------------+
#property copyright "Antigravity Quant Tools"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots   3

//--- Plot 1: Breadth Composite (Histogram)
#property indicator_label1  "Amplitud US (%)"
#property indicator_type1   DRAW_COLOR_HISTOGRAM
#property indicator_color1  clrLimeGreen, clrTomato
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- Plot 2: US2000 Breadth Line (2000 acciones - Proxy $ADD)
#property indicator_label2  "US2000 (Proxy $ADD %)"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrGold
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//--- Plot 3: US500 % Line
#property indicator_label3  "US500 (%)"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDeepSkyBlue
#property indicator_style3  STYLE_DOT
#property indicator_width3  1

//--- Inputs
input group "=== Simbolos de tu Broker (IC Markets) ==="
input string   InpSymSP500   = "US500";   // Simbolo S&P 500
input string   InpSymNasdaq  = "USTEC";   // Simbolo Nasdaq 100
input string   InpSymRussell = "US2000";  // Simbolo Russell 2000 (Amplitud 2000 acciones)
input string   InpSymDow     = "US30";    // Simbolo Dow Jones 30

input group "=== Simbolos NYSE Reales (Si tu broker los tiene) ==="
input string   InpSymADD     = "$ADD";    // Simbolo NYSE Advance-Decline
input string   InpSymVOLD    = "$VOLD";   // Simbolo NYSE Up/Down Volume
input string   InpSymTICK    = "$TICK";   // Simbolo NYSE Tick

input group "=== Visualizacion ==="
input bool     InpShowHud    = true;      // Mostrar panel de veredicto anti-trampas

//--- Buffers
double BufComposite[];
double BufCompColor[];
double BufUS2000Pct[];
double BufUS500Pct[];

//--- State
bool   g_hasNyseNative = false;
const string PREFIX = "INT_FILT_";

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufComposite, INDICATOR_DATA);
   SetIndexBuffer(1, BufCompColor, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, BufUS2000Pct, INDICATOR_DATA);
   SetIndexBuffer(3, BufUS500Pct,  INDICATOR_DATA);

   // Select symbols in Market Watch so data stays synced
   SymbolSelect(InpSymSP500,   true);
   SymbolSelect(InpSymNasdaq,  true);
   SymbolSelect(InpSymRussell, true);
   SymbolSelect(InpSymDow,     true);

   g_hasNyseNative = (SymbolSelect(InpSymADD, true) && SymbolSelect(InpSymVOLD, true));

   IndicatorSetString(INDICATOR_SHORTNAME,
      g_hasNyseNative ? "NYSE Internals ($ADD / $VOLD / $TICK)"
                      : "US Market Breadth Filter (Proxy $ADD: US2000 vs US500/USTEC/US30)");
   IndicatorSetInteger(INDICATOR_DIGITS, 2);
   IndicatorSetInteger(INDICATOR_LEVELS, 1);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 0, 0.0);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 0, C'60,70,85');
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 0, STYLE_DASH);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PREFIX);
}

//+------------------------------------------------------------------+
//| Get % change from Daily Open at time t                           |
//+------------------------------------------------------------------+
double GetPctFromDailyOpen(const string sym, const datetime t)
{
   int shiftBar = iBarShift(sym, PERIOD_CURRENT, t, false);
   if(shiftBar < 0) return 0.0;

   double c = iClose(sym, PERIOD_CURRENT, shiftBar);
   int dayShift = iBarShift(sym, PERIOD_D1, t, false);
   if(dayShift < 0) return 0.0;

   double dOpen = iOpen(sym, PERIOD_D1, dayShift);
   if(dOpen <= 0.0) return 0.0;

   return ((c - dOpen) / dOpen) * 100.0;
}

//+------------------------------------------------------------------+
//| Iteration                                                        |
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
   if(rates_total < 10) return(0);

   int start = (prev_calculated > 1) ? (prev_calculated - 1) : MathMax(0, rates_total - 500);

   double p500 = 0, pNas = 0, pRus = 0, pDow = 0;

   for(int i = start; i < rates_total; i++)
   {
      datetime t = time[i];

      if(g_hasNyseNative)
      {
         int sAdd = iBarShift(InpSymADD, PERIOD_CURRENT, t, false);
         double addVal = (sAdd >= 0) ? iClose(InpSymADD, PERIOD_CURRENT, sAdd) : 0.0;
         BufComposite[i] = addVal;
         BufCompColor[i] = (addVal >= 0.0) ? 0.0 : 1.0;
         BufUS2000Pct[i] = addVal;
         BufUS500Pct[i]  = GetPctFromDailyOpen(InpSymSP500, t);
      }
      else
      {
         p500 = GetPctFromDailyOpen(InpSymSP500,   t);
         pNas = GetPctFromDailyOpen(InpSymNasdaq,  t);
         pRus = GetPctFromDailyOpen(InpSymRussell, t);
         pDow = GetPctFromDailyOpen(InpSymDow,     t);

         // Weighted broad market score (Russell 2000 carries 40% breadth weight)
         double comp = (pRus * 0.40) + (pDow * 0.25) + (p500 * 0.20) + (pNas * 0.15);

         BufComposite[i] = comp;
         BufCompColor[i] = (comp >= 0.0) ? 0.0 : 1.0;
         BufUS2000Pct[i] = pRus;
         BufUS500Pct[i]  = p500;
      }
   }

   if(InpShowHud)
   {
      datetime tNow = time[rates_total - 1];
      p500 = GetPctFromDailyOpen(InpSymSP500,   tNow);
      pNas = GetPctFromDailyOpen(InpSymNasdaq,  tNow);
      pRus = GetPctFromDailyOpen(InpSymRussell, tNow);
      pDow = GetPctFromDailyOpen(InpSymDow,     tNow);
      UpdateHud(p500, pNas, pRus, pDow, tNow);
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Update Subwindow HUD                                             |
//+------------------------------------------------------------------+
void UpdateHud(double p500, double pNas, double pRus, double pDow, datetime tNow)
{
   int subWin = ChartWindowFind();
   if(subWin < 0) return;

   string line1 = "";
   string line2 = "";
   color  verClr = clrSilver;

   if(g_hasNyseNative)
   {
      double addV  = iClose(InpSymADD,  PERIOD_CURRENT, 0);
      double voldV = iClose(InpSymVOLD, PERIOD_CURRENT, 0);
      double tickV = SymbolSelect(InpSymTICK, true) ? iClose(InpSymTICK, PERIOD_CURRENT, 0) : 0.0;
      line1 = StringFormat("$ADD: %+.0f | $VOLD: %+.0f | $TICK: %+.0f", addV, voldV, tickV);
      if(addV > 400 && voldV > 0)       { line2 = "VEREDICTO: TENDENCIA ALCISTA REAL"; verClr = clrLimeGreen; }
      else if(addV < -400 && voldV < 0) { line2 = "VEREDICTO: TENDENCIA BAJISTA REAL"; verClr = clrTomato; }
      else                              { line2 = "VEREDICTO: MERCADO MIXTO / RANGO";  verClr = clrSilver; }
   }
   else
   {
      line1 = StringFormat("US500: %+.2f%% | USTEC: %+.2f%% | US2000(ADD): %+.2f%% | US30: %+.2f%%",
                           p500, pNas, pRus, pDow);

      int bullCount = (p500 > 0 ? 1 : 0) + (pNas > 0 ? 1 : 0) + (pRus > 0 ? 1 : 0) + (pDow > 0 ? 1 : 0);

      if(bullCount == 4)
      {
         line2  = "VEREDICTO: TENDENCIA ALCISTA CONFIRMADA (4/4 Verdes)";
         verClr = clrLimeGreen;
      }
      else if(bullCount == 0 && (p500 < 0 && pNas < 0 && pRus < 0 && pDow < 0))
      {
         line2  = "VEREDICTO: TENDENCIA BAJISTA CONFIRMADA (4/4 Rojos)";
         verClr = clrTomato;
      }
      else if(p500 > 0.05 && pRus < -0.05)
      {
         line2  = "ALERTA TRAMPA: US500 sube pero US2000(Amplitud) CAE -> Posible giro bajista!";
         verClr = clrOrange;
      }
      else if(p500 < -0.05 && pRus > 0.05)
      {
         line2  = "ALERTA DIVERGENCIA: US500 cae pero US2000(Amplitud) SUBE -> Posible rebote!";
         verClr = clrGold;
      }
      else
      {
         line2  = "VEREDICTO: MERCADO MIXTO / RANGO (Esperar alineacion)";
         verClr = clrSilver;
      }
   }

   SetLabel("L1", 12, 18, line1, clrWhite, 8, false, subWin);
   SetLabel("L2", 12, 34, line2, verClr,   8, true,  subWin);
}

//+------------------------------------------------------------------+
//| Helper label                                                     |
//+------------------------------------------------------------------+
void SetLabel(string id, int x, int y, string text, color clr, int sz, bool bold, int win)
{
   string name = PREFIX + id;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, win, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, sz);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Consolas Bold" : "Consolas");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}
//+------------------------------------------------------------------+
