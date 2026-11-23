//+------------------------------------------------------------------+
//|                                            US500_CVD_Trigger.mq5 |
//|   Cumulative Volume Delta (CVD) + Absorption Divergence Detector |
//+------------------------------------------------------------------+
#property copyright "Antigravity Quant Tools"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 5
#property indicator_plots   2

//--- Plot 1: CVD Line (Color)
#property indicator_label1  "CVD"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrLimeGreen, clrTomato
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- Plot 2: CVD Signal EMA
#property indicator_label2  "CVD Signal"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDimGray
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

//--- Inputs
input group "=== Configuracion CVD ==="
input int      InpResetHour       = 0;     // Hora servidor para reiniciar CVD (0=Medianoche, 16=Apertura NY)
input int      InpResetMinute     = 0;     // Minuto de reinicio (ej. 30 para 16:30 IC Markets)
input int      InpSignalPeriod    = 14;    // Periodo EMA de senal sobre el CVD
input int      InpDivLookback     = 12;    // Velas para detectar divergencia/absorcion
input bool     InpUseRealTicks    = true;  // Usar ticks reales en velas recientes (si el broker los tiene)
input int      InpMaxTickBars     = 300;   // Maximo de velas recientes para consultar ticks reales

input group "=== Visualizacion ==="
input bool     InpShowHud         = true;  // Mostrar lectura en vivo en la subventana
input bool     InpShowDivMarkers  = true;  // Dibujar puntos de absorcion en el CVD

//--- Buffers
double BufCVD[];
double BufCVDColor[];
double BufSignal[];
double BufDelta[];
double BufZero[];

//--- Constants
const string PREFIX = "CVD_TRIG_";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufCVD,      INDICATOR_DATA);
   SetIndexBuffer(1, BufCVDColor, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, BufSignal,   INDICATOR_DATA);
   SetIndexBuffer(3, BufDelta,    INDICATOR_CALCULATIONS);
   SetIndexBuffer(4, BufZero,     INDICATOR_CALCULATIONS);

   IndicatorSetString(INDICATOR_SHORTNAME, "US500 CVD Trigger (Delta & Absorcion)");
   IndicatorSetInteger(INDICATOR_DIGITS, 0);
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
//| Calculate bar delta (Ticks if available, else normalized candle) |
//+------------------------------------------------------------------+
double CalcBarDelta(const int i,
                    const int rates_total,
                    const datetime &time[],
                    const double high,
                    const double low,
                    const double close,
                    const long tick_vol)
{
   // Try real tick direction for recent bars
   if(InpUseRealTicks && (rates_total - 1 - i) <= InpMaxTickBars)
   {
      datetime tStart = time[i];
      datetime tEnd   = (i + 1 < rates_total) ? time[i + 1] : (TimeCurrent() + 1);
      MqlTick ticks[];
      int count = CopyTicksRange(_Symbol, ticks, COPY_TICKS_ALL, (ulong)tStart * 1000, (ulong)tEnd * 1000 - 1);
      if(count > 2)
      {
         double buyVol = 0.0, sellVol = 0.0;
         double prevBid = ticks[0].bid;
         int lastDir = 0;
         for(int t = 1; t < count; t++)
         {
            double v = (ticks[t].volume > 0) ? (double)ticks[t].volume : 1.0;
            if((ticks[t].flags & TICK_FLAG_BUY) != 0 && (ticks[t].flags & TICK_FLAG_SELL) == 0)
               lastDir = 1;
            else if((ticks[t].flags & TICK_FLAG_SELL) != 0 && (ticks[t].flags & TICK_FLAG_BUY) == 0)
               lastDir = -1;
            else if(ticks[t].bid > prevBid)
               lastDir = 1;
            else if(ticks[t].bid < prevBid)
               lastDir = -1;

            if(lastDir > 0) buyVol += v;
            else if(lastDir < 0) sellVol += v;

            prevBid = ticks[t].bid;
         }
         if(buyVol + sellVol > 0.0)
            return(buyVol - sellVol);
      }
   }

   // Fallback: Normalized Candle Range Delta
   double range = high - low;
   if(range <= 0.0) return 0.0;
   double buyRatio = (close - low) / range;
   return((double)tick_vol * (2.0 * buyRatio - 1.0));
}

//+------------------------------------------------------------------+
//| Check if bar i starts a new session                              |
//+------------------------------------------------------------------+
bool IsNewSession(datetime tPrev, datetime tCurr)
{
   MqlDateTime dtPrev, dtCurr;
   TimeToStruct(tPrev, dtPrev);
   TimeToStruct(tCurr, dtCurr);

   int minPrev = dtPrev.hour * 60 + dtPrev.min;
   int minCurr = dtCurr.hour * 60 + dtCurr.min;
   int target  = InpResetHour * 60 + InpResetMinute;

   if(dtCurr.day != dtPrev.day || dtCurr.mon != dtPrev.mon || dtCurr.year != dtPrev.year)
   {
      if(target == 0) return true;
      if(minCurr >= target) return true;
   }
   else
   {
      if(minPrev < target && minCurr >= target) return true;
   }
   return false;
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
   if(rates_total < 20) return(0);

   int start = (prev_calculated > 1) ? (prev_calculated - 1) : 0;
   double alpha = 2.0 / (InpSignalPeriod + 1.0);

   for(int i = start; i < rates_total; i++)
   {
      double delta = CalcBarDelta(i, rates_total, time, high[i], low[i], close[i], tick_volume[i]);
      BufDelta[i] = delta;

      if(i == 0 || IsNewSession(time[i - 1], time[i]))
         BufCVD[i] = delta;
      else
         BufCVD[i] = BufCVD[i - 1] + delta;

      if(i == 0)
      {
         BufSignal[i]   = BufCVD[i];
         BufCVDColor[i] = (BufCVD[i] >= 0.0) ? 0.0 : 1.0;
      }
      else
      {
         BufSignal[i]   = BufSignal[i - 1] + alpha * (BufCVD[i] - BufSignal[i - 1]);
         BufCVDColor[i] = (BufCVD[i] >= BufCVD[i - 1]) ? 0.0 : 1.0;
      }
   }

   // Detect Absorption / Divergence on latest closed bar
   int last = rates_total - 1;
   string estado = "NEUTRAL";
   color  estClr = clrSilver;

   if(last > InpDivLookback + 2)
   {
      int idxLowPrice  = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW,  InpDivLookback, 1);
      int idxHighPrice = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, InpDivLookback, 1);

      // Convert iLowest/iHighest (shift from 0) to array index
      int arrLowIdx  = rates_total - 1 - idxLowPrice;
      int arrHighIdx = rates_total - 1 - idxHighPrice;

      bool bullAbs = (low[last - 1] <= low[arrLowIdx] && BufCVD[last - 1] > BufCVD[arrLowIdx] && BufDelta[last - 1] > 0);
      bool bearAbs = (high[last - 1] >= high[arrHighIdx] && BufCVD[last - 1] < BufCVD[arrHighIdx] && BufDelta[last - 1] < 0);

      if(bullAbs)
      {
         estado = "ABSORCION ALCISTA (Posible Rebote)";
         estClr = clrLimeGreen;
         if(InpShowDivMarkers) DrawMarker(time[last - 1], BufCVD[last - 1], true);
      }
      else if(bearAbs)
      {
         estado = "ABSORCION BAJISTA (Posible Giro)";
         estClr = clrTomato;
         if(InpShowDivMarkers) DrawMarker(time[last - 1], BufCVD[last - 1], false);
      }
      else if(BufCVD[last] > BufSignal[last] && BufDelta[last] > 0)
      {
         estado = "INICIATIVA COMPRADORA";
         estClr = clrLimeGreen;
      }
      else if(BufCVD[last] < BufSignal[last] && BufDelta[last] < 0)
      {
         estado = "INICIATIVA VENDEDORA";
         estClr = clrTomato;
      }
   }

   if(InpShowHud)
      UpdateHud(BufDelta[last], BufCVD[last], estado, estClr);

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Draw absorption arrow in subwindow                               |
//+------------------------------------------------------------------+
void DrawMarker(datetime t, double val, bool bull)
{
   int subWin = ChartWindowFind();
   if(subWin < 0) return;

   string name = PREFIX + "DIV_" + IntegerToString((long)t);
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROW, subWin, t, val);

   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, bull ? 233 : 234);
   ObjectSetInteger(0, name, OBJPROP_COLOR, bull ? clrLimeGreen : clrTomato);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Update subwindow HUD                                             |
//+------------------------------------------------------------------+
void UpdateHud(double lastDelta, double cvd, string estado, color estClr)
{
   int subWin = ChartWindowFind();
   if(subWin < 0) return;

   string name = PREFIX + "HUD_TXT";
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, subWin, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 12);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 18);
   ObjectSetString(0, name, OBJPROP_TEXT,
      StringFormat("Delta Vela: %+.0f  |  CVD Dia: %+.0f  |  %s", lastDelta, cvd, estado));
   ObjectSetInteger(0, name, OBJPROP_COLOR, estClr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas Bold");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}
//+------------------------------------------------------------------+
