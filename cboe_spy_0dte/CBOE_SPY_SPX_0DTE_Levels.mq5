//+------------------------------------------------------------------+
//|                                   CBOE_SPY_SPX_0DTE_Levels.mq5   |
//|                                  Copyright 2026, Antigravity     |
//|  CBOE 0DTE: +-20 Strikes, Max Pain, Net GEX, Mov. Esperado & HUD |
//+------------------------------------------------------------------+
#property copyright   "Antigravity Quant Tools"
#property link        "https://github.com"
#property version     "1.11"
#property description "Plotea los 20 strikes arriba y 20 abajo de la Apertura (0DTE SPY/SPX CBOE) con etiquetas visibles encima de cada linea (Vol, OI, IV, Delta, Gamma), Max Pain, Net GEX y paneles a la izquierda."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//+------------------------------------------------------------------+
//| ENUMERACIONES                                                    |
//+------------------------------------------------------------------+
enum ENUM_CBOE_SOURCE
{
   CBOE_SRC_SPY = 0,   // SPY 0DTE (Auto-escala SPY ~708 o US500 ~7080)
   CBOE_SRC_SPX = 1    // SPX 0DTE (Escala indice)
};

enum ENUM_RANK_MODE
{
   RANK_BY_VOLUME = 0, // Ordenar por VOLUMEN intradia (Imanes en vivo)
   RANK_BY_OI     = 1  // Ordenar por OPEN INTEREST (Muros fijos)
};

//+------------------------------------------------------------------+
//| PARAMETROS DE ENTRADA                                            |
//+------------------------------------------------------------------+
input group "=== Fuente y Rango 0DTE (CBOE) ===";
input ENUM_CBOE_SOURCE InpSource          = CBOE_SRC_SPY;   // Fuente de Datos CBOE
input ENUM_RANK_MODE   InpRankMode        = RANK_BY_VOLUME; // Priorizar por Volumen o Open Interest
input int              InpStrikesAbove    = 20;             // Strikes por ENCIMA de la Apertura del Dia
input int              InpStrikesBelow    = 20;             // Strikes por DEBAJO de la Apertura del Dia
input int              InpMaxAboveShow    = 20;             // Cuantos strikes ARRIBA dibujar (20 = todos)
input int              InpMaxBelowShow    = 20;             // Cuantos strikes ABAJO dibujar (20 = todos)
input double           InpExtraOffset     = 0.0;            // Ajuste fino manual en puntos (opcional)
input int              InpReloadSeconds   = 60;             // Re-leer CSV cada N segundos

input group "=== Paneles Explicativos (SIEMPRE A LA IZQUIERDA) ===";
input bool             InpShowHudPanel    = true;           // Mostrar Panel de Proyeccion, Max Pain y GEX
input bool             InpShowGuidePanel  = true;           // Mostrar Guia de Vol/IV/Delta/Gamma/Int/GEX
input int              InpLeftX           = 12;             // Margen izquierdo X
input int              InpTopY            = 24;             // Margen superior Y

input group "=== Colores de Lineas ===";
input color            InpColorCallMain   = clrLimeGreen;      // Call dominante (Top 1-2)
input color            InpColorCallSec    = clrMediumSeaGreen; // Call dominante (resto)
input color            InpColorPutMain    = clrCrimson;        // Put dominante (Top 1-2)
input color            InpColorPutSec     = clrTomato;         // Put dominante (resto)
input color            InpColorMaxPain    = clrGold;           // Color linea Max Pain 0DTE
input bool             InpShowMaxPain     = true;              // Dibujar linea Max Pain 0DTE
input bool             InpShowOpenLine    = true;              // Mostrar linea Apertura del Dia

//--- Estructura de Strike CBOE
struct CboeStrike
{
   double raw_strike;
   double us500_strike;
   double chart_strike;
   long   c_vol;
   double c_iv;
   double c_delta;
   double c_gamma;
   long   c_oi;
   long   p_vol;
   double p_iv;
   double p_delta;
   double p_gamma;
   long   p_oi;
   string dom_type;
   long   dom_score;
   long   dom_vol;
   long   dom_oi;
   double dom_iv;
   double dom_delta;
   double dom_gamma;
};

//--- Variables globales
string     g_prefix       = "CBOE0DTE_";
CboeStrike g_all[];
CboeStrike g_above[];
CboeStrike g_below[];
string     g_exp_date     = "-";
string     g_updated      = "Sin archivo";
double     g_spot_ref     = 0.0;
double     g_ratio        = 10.0;
long       g_tot_call_vol = 0;
long       g_tot_put_vol  = 0;
long       g_tot_call_oi  = 0;
long       g_tot_put_oi   = 0;

//--- Summary analytics
double     g_max_pain_raw   = 0.0;
double     g_max_pain_us500 = 0.0;
double     g_net_gex_m      = 0.0;
double     g_exp_move_raw   = 0.0;
double     g_exp_move_us500 = 0.0;

//+------------------------------------------------------------------+
//| Formato compacto de volumen/OI                                   |
//+------------------------------------------------------------------+
string FmtK(long v)
{
   if(v >= 1000000) return StringFormat("%.2fM", v / 1000000.0);
   if(v >= 1000)    return StringFormat("%.1fk", v / 1000.0);
   return IntegerToString(v);
}

//+------------------------------------------------------------------+
//| Ordenar arreglo de strikes descendentemente por dom_score        |
//+------------------------------------------------------------------+
void SortDescByScore(CboeStrike &arr[])
{
   int n = ArraySize(arr);
   for(int i = 0; i < n - 1; i++)
   {
      for(int j = i + 1; j < n; j++)
      {
         if(arr[j].dom_score > arr[i].dom_score)
         {
            CboeStrike tmp = arr[i];
            arr[i] = arr[j];
            arr[j] = tmp;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Cargar CBOE_0DTE_Levels.csv y CBOE_0DTE_Summary.csv              |
//+------------------------------------------------------------------+
void LoadCboeCSV()
{
   ArrayResize(g_all, 0);
   g_exp_date       = "-";
   g_updated        = "Sin archivo";
   g_spot_ref       = 0.0;
   g_tot_call_vol   = 0;
   g_tot_put_vol    = 0;
   g_tot_call_oi    = 0;
   g_tot_put_oi     = 0;
   g_max_pain_raw   = 0.0;
   g_max_pain_us500 = 0.0;
   g_net_gex_m      = 0.0;
   g_exp_move_raw   = 0.0;
   g_exp_move_us500 = 0.0;

   string want_src = (InpSource == CBOE_SRC_SPY) ? "SPY" : "SPX";

   // 1. Leer Summary CSV (Max Pain, Net GEX, Exp Move, Totales)
   int hs = FileOpen("CBOE_0DTE_Summary.csv", FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(hs == INVALID_HANDLE)
      hs = FileOpen("CBOE_0DTE_Summary.csv", FILE_READ | FILE_TXT | FILE_ANSI);
   if(hs != INVALID_HANDLE)
   {
      while(!FileIsEnding(hs))
      {
         string line = FileReadString(hs);
         StringTrimLeft(line);
         StringTrimRight(line);
         if(StringLen(line) < 10 || StringFind(line, "SOURCE") == 0) continue;
         string cols[];
         if(StringSplit(line, ',', cols) >= 14 && cols[0] == want_src)
         {
            g_max_pain_raw   = StringToDouble(cols[4]);
            g_max_pain_us500 = StringToDouble(cols[5]);
            g_net_gex_m      = StringToDouble(cols[6]);
            g_exp_move_raw   = StringToDouble(cols[7]);
            g_exp_move_us500 = StringToDouble(cols[8]);
            g_tot_call_vol   = StringToInteger(cols[9]);
            g_tot_put_vol    = StringToInteger(cols[10]);
            g_tot_call_oi    = StringToInteger(cols[11]);
            g_tot_put_oi     = StringToInteger(cols[12]);
            break;
         }
      }
      FileClose(hs);
   }

   // 2. Leer Levels CSV (Strikes completos)
   int h = FileOpen("CBOE_0DTE_Levels.csv", FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
      h = FileOpen("CBOE_0DTE_Levels.csv", FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) return;

   long sum_cv = 0, sum_pv = 0, sum_co = 0, sum_po = 0;

   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      StringTrimLeft(line);
      StringTrimRight(line);
      if(StringLen(line) < 10 || StringFind(line, "SOURCE") == 0) continue;

      string cols[];
      if(StringSplit(line, ',', cols) < 17) continue;
      if(cols[0] != want_src) continue;

      g_exp_date = cols[1];
      g_spot_ref = StringToDouble(cols[2]);
      g_ratio    = StringToDouble(cols[3]);
      g_updated  = cols[16];

      int sz = ArraySize(g_all);
      ArrayResize(g_all, sz + 1);
      g_all[sz].raw_strike   = StringToDouble(cols[4]);
      g_all[sz].us500_strike = NormalizeDouble(StringToDouble(cols[5]) + InpExtraOffset, _Digits);

      g_all[sz].c_vol   = StringToInteger(cols[6]);
      g_all[sz].c_iv    = StringToDouble(cols[7]);
      g_all[sz].c_delta = StringToDouble(cols[8]);
      g_all[sz].c_gamma = StringToDouble(cols[9]);
      g_all[sz].c_oi    = StringToInteger(cols[10]);

      g_all[sz].p_vol   = StringToInteger(cols[11]);
      g_all[sz].p_iv    = StringToDouble(cols[12]);
      g_all[sz].p_delta = StringToDouble(cols[13]);
      g_all[sz].p_gamma = StringToDouble(cols[14]);
      g_all[sz].p_oi    = StringToInteger(cols[15]);

      sum_cv += g_all[sz].c_vol;
      sum_pv += g_all[sz].p_vol;
      sum_co += g_all[sz].c_oi;
      sum_po += g_all[sz].p_oi;

      long c_metric = (InpRankMode == RANK_BY_VOLUME) ? g_all[sz].c_vol : g_all[sz].c_oi;
      long p_metric = (InpRankMode == RANK_BY_VOLUME) ? g_all[sz].p_vol : g_all[sz].p_oi;

      if(c_metric >= p_metric)
      {
         g_all[sz].dom_type  = "CALL";
         g_all[sz].dom_score = c_metric;
         g_all[sz].dom_vol   = g_all[sz].c_vol;
         g_all[sz].dom_oi    = g_all[sz].c_oi;
         g_all[sz].dom_iv    = g_all[sz].c_iv;
         g_all[sz].dom_delta = g_all[sz].c_delta;
         g_all[sz].dom_gamma = g_all[sz].c_gamma;
      }
      else
      {
         g_all[sz].dom_type  = "PUT";
         g_all[sz].dom_score = p_metric;
         g_all[sz].dom_vol   = g_all[sz].p_vol;
         g_all[sz].dom_oi    = g_all[sz].p_oi;
         g_all[sz].dom_iv    = g_all[sz].p_iv;
         g_all[sz].dom_delta = g_all[sz].p_delta;
         g_all[sz].dom_gamma = g_all[sz].p_gamma;
      }
   }
   FileClose(h);

   if(g_tot_call_vol == 0) g_tot_call_vol = sum_cv;
   if(g_tot_put_vol  == 0) g_tot_put_vol  = sum_pv;
   if(g_tot_call_oi  == 0) g_tot_call_oi  = sum_co;
   if(g_tot_put_oi   == 0) g_tot_put_oi   = sum_po;
}

//+------------------------------------------------------------------+
//| Separar 20 strikes ARRIBA y 20 strikes ABAJO de la Apertura      |
//+------------------------------------------------------------------+
void BuildWindowFromOpen(double daily_open)
{
   ArrayResize(g_above, 0);
   ArrayResize(g_below, 0);
   int n = ArraySize(g_all);
   if(n == 0 || daily_open <= 0) return;

   bool use_raw = (InpSource == CBOE_SRC_SPY && daily_open < 2000.0);
   for(int i = 0; i < n; i++)
   {
      g_all[i].chart_strike = use_raw ? NormalizeDouble(g_all[i].raw_strike + InpExtraOffset, _Digits)
                                      : g_all[i].us500_strike;
   }

   int pivot = 0;
   double best_dist = MathAbs(g_all[0].chart_strike - daily_open);
   for(int i = 1; i < n; i++)
   {
      double d = MathAbs(g_all[i].chart_strike - daily_open);
      if(d < best_dist)
      {
         best_dist = d;
         pivot = i;
      }
   }

   // 20 strikes por ENCIMA de la apertura (pivot + 1 .. pivot + InpStrikesAbove)
   int above_to = MathMin(n - 1, pivot + InpStrikesAbove);
   for(int i = pivot + 1; i <= above_to; i++)
   {
      if(g_all[i].dom_score <= 0) continue;
      int sz = ArraySize(g_above);
      ArrayResize(g_above, sz + 1);
      g_above[sz] = g_all[i];
   }

   // 20 strikes por DEBAJO / EN la apertura (pivot - InpStrikesBelow .. pivot)
   int below_from = MathMax(0, pivot - InpStrikesBelow);
   for(int i = below_from; i <= pivot; i++)
   {
      if(g_all[i].dom_score <= 0) continue;
      int sz = ArraySize(g_below);
      ArrayResize(g_below, sz + 1);
      g_below[sz] = g_all[i];
   }

   SortDescByScore(g_above);
   SortDescByScore(g_below);
}

//+------------------------------------------------------------------+
//| OnInit / OnDeinit / OnTimer / OnCalculate                        |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "CBOE 0DTE SPY/SPX + MaxPain & GEX");
   EventSetTimer(MathMax(15, InpReloadSeconds));
   LoadCboeCSV();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, g_prefix);
   ChartRedraw(0);
}

void OnTimer()
{
   LoadCboeCSV();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      datetime t_pos = GetRightEdgeTime();
      int total = ObjectsTotal(0, 0, OBJ_TEXT);
      string t_pref = g_prefix + "T_";
      for(int i = 0; i < total; i++)
      {
         string name = ObjectName(0, i, 0, OBJ_TEXT);
         if(StringFind(name, t_pref) == 0)
            ObjectSetInteger(0, name, OBJPROP_TIME, 0, t_pos);
      }
      ChartRedraw(0);
   }
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &real_volume[],
                const int &spread[])
{
   if(rates_total < 1) return 0;

   ArraySetAsSeries(open, true);
   ArraySetAsSeries(close, true);

   double daily_open_arr[];
   double daily_open = open[0];
   if(CopyOpen(_Symbol, PERIOD_D1, 0, 1, daily_open_arr) > 0 && daily_open_arr[0] > 0)
      daily_open = daily_open_arr[0];

   double curr_price = close[0];

   BuildWindowFromOpen(daily_open);
   DrawChartAndPanels(daily_open, curr_price);

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Dibujar los 20 arriba + 20 abajo + Max Pain + Paneles Izquierda  |
//+------------------------------------------------------------------+
void DrawChartAndPanels(double daily_open, double curr_price)
{
   ObjectsDeleteAll(0, g_prefix + "L_");
   ObjectsDeleteAll(0, g_prefix + "T_");

   bool use_raw = (InpSource == CBOE_SRC_SPY && daily_open < 2000.0);
   string src_tag = (InpSource == CBOE_SRC_SPY) ? "SPY" : "SPX";

   if(InpShowOpenLine && daily_open > 0)
      DrawHLine("L_OPEN", daily_open, StringFormat("OPEN DIA (+%d/-%d strikes)", InpStrikesAbove, InpStrikesBelow), clrDimGray, STYLE_DASHDOT, 1);

   double max_pain_chart = use_raw ? g_max_pain_raw : g_max_pain_us500;
   double exp_move_chart = use_raw ? g_exp_move_raw : g_exp_move_us500;

   if(InpShowMaxPain && max_pain_chart > 0)
      DrawHLine("L_MAXPAIN", max_pain_chart, "MAX PAIN 0DTE (Iman Cierre)", InpColorMaxPain, STYLE_DASHDOTDOT, 2);

   // Encontrar Iman #1 global, Call Wall global y Put Wall global en los +-20 strikes
   CboeStrike top_magnet, top_call, top_put, max_oi_lvl;
   bool has_magnet = false, has_call = false, has_put = false, has_oi = false;
   long best_score = -1, best_call_s = -1, best_put_s = -1, best_oi = -1;

   int na = ArraySize(g_above);
   int nb = ArraySize(g_below);

   for(int i = 0; i < na; i++)
   {
      if(g_above[i].dom_score > best_score) { best_score = g_above[i].dom_score; top_magnet = g_above[i]; has_magnet = true; }
      if(g_above[i].dom_type == "CALL" && g_above[i].dom_score > best_call_s) { best_call_s = g_above[i].dom_score; top_call = g_above[i]; has_call = true; }
      if(g_above[i].dom_type == "PUT"  && g_above[i].dom_score > best_put_s)  { best_put_s  = g_above[i].dom_score; top_put  = g_above[i]; has_put  = true; }
      if(g_above[i].dom_oi > best_oi) { best_oi = g_above[i].dom_oi; max_oi_lvl = g_above[i]; has_oi = true; }
   }
   for(int i = 0; i < nb; i++)
   {
      if(g_below[i].dom_score > best_score) { best_score = g_below[i].dom_score; top_magnet = g_below[i]; has_magnet = true; }
      if(g_below[i].dom_type == "CALL" && g_below[i].dom_score > best_call_s) { best_call_s = g_below[i].dom_score; top_call = g_below[i]; has_call = true; }
      if(g_below[i].dom_type == "PUT"  && g_below[i].dom_score > best_put_s)  { best_put_s  = g_below[i].dom_score; top_put  = g_below[i]; has_put  = true; }
      if(g_below[i].dom_oi > best_oi) { best_oi = g_below[i].dom_oi; max_oi_lvl = g_below[i]; has_oi = true; }
   }

   // Dibujar los 20 strikes por ENCIMA de la Apertura
   int drawn_above = MathMin(na, InpMaxAboveShow);
   for(int i = 0; i < drawn_above; i++)
   {
      CboeStrike s = g_above[i];
      bool is_top = (i < 2);
      color clr = (s.dom_type == "CALL") ? (is_top ? InpColorCallMain : InpColorCallSec)
                                         : (is_top ? InpColorPutMain  : InpColorPutSec);
      ENUM_LINE_STYLE sty = is_top ? STYLE_SOLID : STYLE_DOT;
      int wd = (i == 0) ? 3 : (i == 1 ? 2 : 1);
      string lbl = StringFormat("%s %.0f%s | V:%s OI:%s IV:%.0f%% D:%.2f G:%.3f",
                                src_tag, s.raw_strike, (s.dom_type == "CALL" ? "C" : "P"),
                                FmtK(s.dom_vol), FmtK(s.dom_oi), s.dom_iv * 100.0, s.dom_delta, s.dom_gamma);
      DrawHLine("L_ABV_" + IntegerToString(i), s.chart_strike, lbl, clr, sty, wd);
   }

   // Dibujar los 20 strikes por DEBAJO de la Apertura
   int drawn_below = MathMin(nb, InpMaxBelowShow);
   for(int i = 0; i < drawn_below; i++)
   {
      CboeStrike s = g_below[i];
      bool is_top = (i < 2);
      color clr = (s.dom_type == "CALL") ? (is_top ? InpColorCallMain : InpColorCallSec)
                                         : (is_top ? InpColorPutMain  : InpColorPutSec);
      ENUM_LINE_STYLE sty = is_top ? STYLE_SOLID : STYLE_DOT;
      int wd = (i == 0) ? 4 : (i == 1 ? 3 : 1);
      string lbl = StringFormat("%s %.0f%s | V:%s OI:%s IV:%.0f%% D:%.2f G:%.3f",
                                src_tag, s.raw_strike, (s.dom_type == "CALL" ? "C" : "P"),
                                FmtK(s.dom_vol), FmtK(s.dom_oi), s.dom_iv * 100.0, s.dom_delta, s.dom_gamma);
      DrawHLine("L_BLW_" + IntegerToString(i), s.chart_strike, lbl, clr, sty, wd);
   }

   //--- Panel 1: Estado en vivo, Max Pain, Net GEX, Mov. Esperado y Proyeccion (SIEMPRE IZQUIERDA)
   if(InpShowHudPanel)
   {
      int x = InpLeftX, y = InpTopY, w = 585, h = 278;
      DrawBox("HUD_BG", x, y, w, h);

      double tot_v = (double)(g_tot_call_vol + g_tot_put_vol);
      double c_pct = (tot_v > 0) ? (g_tot_call_vol / tot_v) * 100.0 : 50.0;
      double p_pct = (tot_v > 0) ? (g_tot_put_vol  / tot_v) * 100.0 : 50.0;
      double pc_vol_ratio = (g_tot_call_vol > 0) ? (double)g_tot_put_vol / (double)g_tot_call_vol : 1.0;
      double pc_oi_ratio  = (g_tot_call_oi  > 0) ? (double)g_tot_put_oi  / (double)g_tot_call_oi  : 1.0;

      string gex_txt = (g_net_gex_m >= 0)
         ? StringFormat("+%.1fM (+GEX: MMs frenan velas / Rango)", g_net_gex_m)
         : StringFormat("%.1fM (-GEX: Alta volatilidad / Aceleracion)", g_net_gex_m);
      color gex_clr = (g_net_gex_m >= 0) ? clrLimeGreen : clrTomato;

      double exp_hi = (curr_price > 0 && exp_move_chart > 0) ? (daily_open + exp_move_chart) : 0.0;
      double exp_lo = (curr_price > 0 && exp_move_chart > 0) ? (daily_open - exp_move_chart) : 0.0;

      string proy = "Esperando datos...";
      color  p_clr = clrSilver;
      if(has_magnet && curr_price > 0)
      {
         double dist_mp  = (max_pain_chart > 0) ? (max_pain_chart - curr_price) : 0.0;
         double dist_mag = top_magnet.chart_strike - curr_price;
         string mp_dir   = (dist_mp >= 0) ? "ARRIBA" : "ABAJO";

         if(g_net_gex_m < 0 && has_put && curr_price < top_put.chart_strike)
            proy = StringFormat("-GEX bajo PUT WALL %s -> Aceleracion bajista | Iman cierre MaxPain %s", DoubleToString(top_put.chart_strike, _Digits), DoubleToString(max_pain_chart, _Digits));
         else if(has_call && curr_price > top_call.chart_strike)
            proy = StringFormat("Sobre CALL WALL %s -> Ruptura alcista o pullback hacia %s", DoubleToString(top_call.chart_strike, _Digits), DoubleToString(max_pain_chart, _Digits));
         else if(max_pain_chart > 0)
            proy = StringFormat("Iman Vol #%s (%s) | MaxPain %s (%s %+.1f) -> Sesgo %s", top_magnet.dom_type, DoubleToString(top_magnet.chart_strike, _Digits), DoubleToString(max_pain_chart, _Digits), mp_dir, dist_mp, (dist_mp >= 0 ? "ALCISTA" : "BAJISTA"));
         else
            proy = StringFormat("Iman Vol #%s -> %s (Vol:%s)", top_magnet.dom_type, DoubleToString(top_magnet.chart_strike, _Digits), FmtK(top_magnet.dom_vol));

         p_clr = (dist_mp >= 0 || dist_mag >= 0) ? clrLimeGreen : clrTomato;
      }

      DrawLeftText("H0", x + 10, y + 8,  StringFormat("CBOE %s 0DTE (Exp:%s) | Open:%s | Dibujados: +%d / -%d", src_tag, g_exp_date, DoubleToString(daily_open, _Digits), drawn_above, drawn_below), clrGold, 9, true);
      DrawLeftText("H1", x + 10, y + 25, "Sync: " + g_updated + " | CBOE ~15m delay (Auto cada 5 min)", clrSilver, 8, false);
      DrawLeftText("H2", x + 10, y + 39, "------------------------------------------------------------------------------", C'60,70,90', 8, false);

      if(has_magnet)
      {
         DrawLeftText("H3", x + 10, y + 53, StringFormat("IMAN #1 VOL: %s (%s %.0f%s) | Vol:%s OI:%s", DoubleToString(top_magnet.chart_strike, _Digits), src_tag, top_magnet.raw_strike, (top_magnet.dom_type=="CALL"?"C":"P"), FmtK(top_magnet.dom_vol), FmtK(top_magnet.dom_oi)), clrAqua, 8, true);
         DrawLeftText("H4", x + 10, y + 69, StringFormat("   Griegas -> IV: %.1f%% | Delta: %.2f | Gamma: %.4f", top_magnet.dom_iv * 100.0, top_magnet.dom_delta, top_magnet.dom_gamma), clrWhite, 8, false);
      }

      if(has_call)
         DrawLeftText("H5", x + 10, y + 87, StringFormat("CALL WALL  : %s (%.0fC) | Vol:%s OI:%s IV:%.0f%% G:%.3f", DoubleToString(top_call.chart_strike, _Digits), top_call.raw_strike, FmtK(top_call.dom_vol), FmtK(top_call.dom_oi), top_call.dom_iv*100.0, top_call.dom_gamma), InpColorCallMain, 8, false);
      if(has_put)
         DrawLeftText("H6", x + 10, y + 103, StringFormat("PUT  WALL  : %s (%.0fP) | Vol:%s OI:%s IV:%.0f%% G:%.3f", DoubleToString(top_put.chart_strike, _Digits), top_put.raw_strike, FmtK(top_put.dom_vol), FmtK(top_put.dom_oi), top_put.dom_iv*100.0, top_put.dom_gamma), InpColorPutMain, 8, false);
      if(has_oi)
         DrawLeftText("H7", x + 10, y + 119, StringFormat("MAYOR OI   : %s (%s) | OI:%s Vol:%s", DoubleToString(max_oi_lvl.chart_strike, _Digits), max_oi_lvl.dom_type, FmtK(max_oi_lvl.dom_oi), FmtK(max_oi_lvl.dom_vol)), clrGold, 8, false);

      DrawLeftText("H8",  x + 10, y + 139, StringFormat("MAX PAIN 0DTE: %s (Dist: %+.1f) | Mov.Esp: +-%s [%s - %s]", DoubleToString(max_pain_chart, _Digits), (max_pain_chart - curr_price), DoubleToString(exp_move_chart, _Digits), DoubleToString(exp_lo, _Digits), DoubleToString(exp_hi, _Digits)), InpColorMaxPain, 8, true);
      DrawLeftText("H9",  x + 10, y + 157, "NET GEX 0DTE : " + gex_txt, gex_clr, 8, true);
      DrawLeftText("H10", x + 10, y + 175, StringFormat("FLUJO 0DTE   : Calls %.0f%% (%s) vs Puts %.0f%% (%s) | P/C Vol:%.2f OI:%.2f", c_pct, FmtK(g_tot_call_vol), p_pct, FmtK(g_tot_put_vol), pc_vol_ratio, pc_oi_ratio), (c_pct >= p_pct ? clrLimeGreen : clrTomato), 8, false);

      DrawLeftText("H11", x + 10, y + 195, "------------------------------------------------------------------------------", C'60,70,90', 8, false);
      DrawLeftText("H12", x + 10, y + 209, "PROYECCION MULTI-FACTOR (HACIA DONDE VA EL PRECIO):", clrGold, 8, true);
      DrawLeftText("H13", x + 10, y + 227, proy, p_clr, 8, true);
      DrawLeftText("H14", x + 10, y + 248, StringFormat("Ref Spot %s: %.2f | Ratio US500/SPY: %.4f", src_tag, g_spot_ref, g_ratio), clrDarkGray, 8, false);
   }

   //--- Panel 2: Guia Completa (SIEMPRE IZQUIERDA)
   if(InpShowGuidePanel)
   {
      int gx = InpLeftX, gy = InpTopY + 286, gw = 585, gh = 205;
      DrawBox("GUIDE_BG", gx, gy, gw, gh);

      DrawLeftText("G0", gx + 10, gy + 8,  "GUIA PRO CBOE 0DTE: COMO LEER CADA DATO Y SABER A DONDE VA", clrWhite, 8, true);
      DrawLeftText("G1", gx + 10, gy + 24, "------------------------------------------------------------------------------", C'60,70,90', 8, false);
      DrawLeftText("G2", gx + 10, gy + 38, "Vol      : Contratos operados HOY. Es el iman vivo mas fuerte del dia.", clrAqua, 8, false);
      DrawLeftText("G3", gx + 10, gy + 54, "Int (OI) : Open Interest abierto de dias previos (muros estructurales).", clrGold, 8, false);
      DrawLeftText("G4", gx + 10, gy + 70, "IV       : Volatilidad Implicita. Si sube rapido, velas mas amplias.", clrSilver, 8, false);
      DrawLeftText("G5", gx + 10, gy + 86, "Delta    : Probabilidad aprox. de llegar al strike (0.50=50%, 0.20=20%).", clrSilver, 8, false);
      DrawLeftText("G6", gx + 10, gy + 102,"Gamma    : Aceleracion cobertura MM. Gamma alta = iman o latigazo fuerte.", clrLimeGreen, 8, false);
      DrawLeftText("G7", gx + 10, gy + 118,"Max Pain : Nivel donde expiran mas opciones sin valor (iman al cierre).", InpColorMaxPain, 8, false);
      DrawLeftText("G8", gx + 10, gy + 134,"Net GEX  : +GEX = MMs compran caidas/venden subidas | -GEX = aceleran.", clrTomato, 8, false);
      DrawLeftText("G9", gx + 10, gy + 150,"Mov.Esp  : Rango normal de hoy segun precio del Straddle ATM de CBOE.", clrSilver, 8, false);
      DrawLeftText("G10",gx + 10, gy + 172,"Actualizacion: CBOE cada 15 min (el script refresca auto cada 5 min).", clrOrange, 8, true);
   }

   ChartRedraw(0);
}

datetime GetRightEdgeTime()
{
   datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 <= 0) t0 = TimeCurrent();
   int p_sec     = MathMax(60, PeriodSeconds(_Period));
   int first_vis = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
   int vis_bars  = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
   int right_bar = first_vis - vis_bars + 2;

   if(right_bar >= 0)
   {
      datetime tr = iTime(_Symbol, _Period, right_bar);
      if(tr > 0) return tr;
   }
   return t0 + (datetime)((-right_bar) * p_sec);
}

void DrawHLine(string key, double price, string label, color clr, ENUM_LINE_STYLE style, int width)
{
   string obj = g_prefix + key;
   ObjectCreate(0, obj, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj, OBJPROP_BACK, true);
   ObjectSetDouble(0,  obj, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_STYLE, style);
   ObjectSetInteger(0, obj, OBJPROP_WIDTH, width);
   ObjectSetString(0,  obj, OBJPROP_TEXT, label);
   ObjectSetString(0,  obj, OBJPROP_TOOLTIP, label + " @ " + DoubleToString(price, _Digits));

   // Etiqueta anclada a la derecha, justo ENCIMA de la linea y sin salirse de la pantalla
   string t_obj = g_prefix + "T_" + key;
   datetime t_pos = GetRightEdgeTime();
   ObjectCreate(0, t_obj, OBJ_TEXT, 0, t_pos, price);
   ObjectSetInteger(0, t_obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, t_obj, OBJPROP_BACK, false);
   ObjectSetInteger(0, t_obj, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);
   ObjectSetInteger(0, t_obj, OBJPROP_TIME, 0, t_pos);
   ObjectSetDouble(0,  t_obj, OBJPROP_PRICE, 0, price);
   ObjectSetString(0,  t_obj, OBJPROP_TEXT, label + " [" + DoubleToString(price, _Digits) + "] ");
   ObjectSetInteger(0, t_obj, OBJPROP_COLOR, clr);
   ObjectSetString(0,  t_obj, OBJPROP_FONT, "Consolas Bold");
   ObjectSetInteger(0, t_obj, OBJPROP_FONTSIZE, 8);
}

void DrawBox(string name, int x, int y, int w, int h)
{
   string obj = g_prefix + name;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, C'16,20,28');
   ObjectSetInteger(0, obj, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, C'60,70,90');
   ObjectSetInteger(0, obj, OBJPROP_BACK, false);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
}

void DrawLeftText(string id, int x, int y, string text, color clr, int fontSize, bool bold)
{
   string obj = g_prefix + "TXT_" + id;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetString(0,  obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0,  obj, OBJPROP_FONT, bold ? "Consolas Bold" : "Consolas");
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
}
//+------------------------------------------------------------------+
