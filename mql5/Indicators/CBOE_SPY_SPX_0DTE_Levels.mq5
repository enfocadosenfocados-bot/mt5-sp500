//+------------------------------------------------------------------+
//|                                   CBOE_SPY_SPX_0DTE_Levels.mq5   |
//|                                  Copyright 2026, Antigravity     |
//|      Niveles 0DTE CBOE (SPY / SPX): Vol, IV, Delta, Gamma, OI    |
//+------------------------------------------------------------------+
#property copyright   "Antigravity Quant Tools"
#property link        "https://github.com"
#property version     "1.00"
#property description "Plotea los 20 strikes arriba y 20 abajo desde la Apertura del Dia (0DTE SPY o SPX de CBOE) ordenados por Volumen intradia o OI, con paneles de proyeccion y guia siempre a la izquierda."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//+------------------------------------------------------------------+
//| ENUMERACIONES                                                    |
//+------------------------------------------------------------------+
enum ENUM_CBOE_SOURCE
{
   CBOE_SRC_SPY = 0,   // SPY 0DTE (Convertido a escala US500)
   CBOE_SRC_SPX = 1    // SPX 0DTE (Escala directa indice)
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
input int              InpMaxLinesShow    = 14;             // Maximo de lineas mas grandes a dibujar
input double           InpExtraOffset     = 0.0;            // Ajuste fino manual en puntos (opcional)
input int              InpReloadSeconds   = 60;             // Re-leer CSV cada N segundos

input group "=== Paneles Explicativos (SIEMPRE A LA IZQUIERDA) ===";
input bool             InpShowHudPanel    = true;           // Mostrar Panel de Proyeccion y Griegas
input bool             InpShowGuidePanel  = true;           // Mostrar Guia de Vol/IV/Delta/Gamma/Int
input int              InpLeftX           = 12;             // Margen izquierdo X
input int              InpTopY            = 24;             // Margen superior Y

input group "=== Colores de Lineas ===";
input color            InpColorCallMain   = clrLimeGreen;      // Call dominante (Top 1-2)
input color            InpColorCallSec    = clrMediumSeaGreen; // Call dominante (resto)
input color            InpColorPutMain    = clrCrimson;        // Put dominante (Top 1-2)
input color            InpColorPutSec     = clrTomato;         // Put dominante (resto)
input bool             InpShowOpenLine    = true;              // Mostrar linea Apertura del Dia

//--- Estructura de Strike CBOE
struct CboeStrike
{
   double raw_strike;
   double us500_strike;
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
   // Ganador del strike segun modo
   string dom_type;   // "CALL" o "PUT"
   long   dom_score;  // Vol o OI ganador
   long   dom_vol;
   long   dom_oi;
   double dom_iv;
   double dom_delta;
   double dom_gamma;
};

//--- Variables globales
string     g_prefix       = "CBOE0DTE_";
CboeStrike g_all[];
CboeStrike g_window[];
string     g_exp_date     = "-";
string     g_updated      = "-";
double     g_spot_ref     = 0.0;
double     g_ratio        = 10.0;
long       g_tot_call_vol = 0;
long       g_tot_put_vol  = 0;

//+------------------------------------------------------------------+
//| Formato compacto de volumen/OI (ej. 239.8k)                      |
//+------------------------------------------------------------------+
string FmtK(long v)
{
   if(v >= 1000000) return StringFormat("%.2fM", v / 1000000.0);
   if(v >= 1000)    return StringFormat("%.1fk", v / 1000.0);
   return IntegerToString(v);
}

//+------------------------------------------------------------------+
//| Cargar datos desde Common\Files\CBOE_0DTE_Levels.csv             |
//+------------------------------------------------------------------+
void LoadCboeCSV()
{
   ArrayResize(g_all, 0);
   g_exp_date     = "-";
   g_updated      = "Sin archivo";
   g_spot_ref     = 0.0;
   g_tot_call_vol = 0;
   g_tot_put_vol  = 0;

   string fn = "CBOE_0DTE_Levels.csv";
   int h = FileOpen(fn, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
      h = FileOpen(fn, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) return;

   string want_src = (InpSource == CBOE_SRC_SPY) ? "SPY" : "SPX";

   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      StringTrimLeft(line);
      StringTrimRight(line);
      if(StringLen(line) < 10 || StringFind(line, "SOURCE") == 0) continue;

      string cols[];
      int n = StringSplit(line, ',', cols);
      if(n < 17) continue;
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

      g_tot_call_vol += g_all[sz].c_vol;
      g_tot_put_vol  += g_all[sz].p_vol;

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
}

//+------------------------------------------------------------------+
//| Filtrar los 20 strikes arriba y 20 abajo de la Apertura del Dia  |
//+------------------------------------------------------------------+
void BuildWindowFromOpen(double daily_open)
{
   ArrayResize(g_window, 0);
   int n = ArraySize(g_all);
   if(n == 0 || daily_open <= 0) return;

   // g_all viene ordenado ascendentemente por strike; buscamos el indice mas cercano a daily_open
   int pivot = 0;
   double best_dist = MathAbs(g_all[0].us500_strike - daily_open);
   for(int i = 1; i < n; i++)
   {
      double d = MathAbs(g_all[i].us500_strike - daily_open);
      if(d < best_dist)
      {
         best_dist = d;
         pivot = i;
      }
   }

   int idx_from = MathMax(0, pivot - InpStrikesBelow);
   int idx_to   = MathMin(n - 1, pivot + InpStrikesAbove);

   for(int i = idx_from; i <= idx_to; i++)
   {
      if(g_all[i].dom_score <= 0) continue;
      int sz = ArraySize(g_window);
      ArrayResize(g_window, sz + 1);
      g_window[sz] = g_all[i];
   }

   // Ordenar la ventana descendentemente por dom_score (mayor Volumen u OI)
   int w = ArraySize(g_window);
   for(int i = 0; i < w - 1; i++)
   {
      for(int j = i + 1; j < w; j++)
      {
         if(g_window[j].dom_score > g_window[i].dom_score)
         {
            CboeStrike tmp = g_window[i];
            g_window[i] = g_window[j];
            g_window[j] = tmp;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OnInit / OnDeinit / OnTimer / OnCalculate                        |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "CBOE 0DTE SPY/SPX Levels");
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
//| Dibujar Lineas y Paneles en el Lado Izquierdo                    |
//+------------------------------------------------------------------+
void DrawChartAndPanels(double daily_open, double curr_price)
{
   ObjectsDeleteAll(0, g_prefix + "L_");
   ObjectsDeleteAll(0, g_prefix + "T_");

   if(InpShowOpenLine && daily_open > 0)
      DrawHLine("L_OPEN", daily_open, StringFormat("OPEN DIA (+%d/-%d strikes)", InpStrikesAbove, InpStrikesBelow), clrDimGray, STYLE_DASHDOT, 1);

   int w_size = ArraySize(g_window);
   int drawn  = 0;
   int c_rank = 0, p_rank = 0;

   // Buscar mejor Call Wall, Put Wall y Magnet #1 dentro de la ventana
   CboeStrike top_magnet, top_call, top_put, max_oi_lvl;
   bool has_magnet = false, has_call = false, has_put = false, has_oi = false;
   long best_oi = -1;

   for(int i = 0; i < w_size; i++)
   {
      if(!has_magnet) { top_magnet = g_window[i]; has_magnet = true; }
      if(g_window[i].dom_type == "CALL" && !has_call) { top_call = g_window[i]; has_call = true; }
      if(g_window[i].dom_type == "PUT"  && !has_put)  { top_put  = g_window[i]; has_put  = true; }
      if(g_window[i].dom_oi > best_oi) { best_oi = g_window[i].dom_oi; max_oi_lvl = g_window[i]; has_oi = true; }
   }

   string src_tag = (InpSource == CBOE_SRC_SPY) ? "SPY" : "SPX";

   for(int i = 0; i < w_size && drawn < InpMaxLinesShow; i++)
   {
      CboeStrike s = g_window[i];
      drawn++;

      color clr;
      ENUM_LINE_STYLE sty;
      int wd;
      string lbl;

      if(s.dom_type == "CALL")
      {
         c_rank++;
         bool is_big = (c_rank <= 2);
         clr = is_big ? InpColorCallMain : InpColorCallSec;
         sty = is_big ? STYLE_SOLID : STYLE_DOT;
         wd  = (c_rank == 1) ? 4 : (c_rank == 2 ? 3 : 1);
         lbl = StringFormat("%s %.0fC | Vol:%s OI:%s IV:%.0f%% D:%.2f G:%.3f",
                            src_tag, s.raw_strike, FmtK(s.dom_vol), FmtK(s.dom_oi),
                            s.dom_iv * 100.0, s.dom_delta, s.dom_gamma);
      }
      else
      {
         p_rank++;
         bool is_big = (p_rank <= 2);
         clr = is_big ? InpColorPutMain : InpColorPutSec;
         sty = is_big ? STYLE_SOLID : STYLE_DOT;
         wd  = (p_rank == 1) ? 4 : (p_rank == 2 ? 3 : 1);
         lbl = StringFormat("%s %.0fP | Vol:%s OI:%s IV:%.0f%% D:%.2f G:%.3f",
                            src_tag, s.raw_strike, FmtK(s.dom_vol), FmtK(s.dom_oi),
                            s.dom_iv * 100.0, s.dom_delta, s.dom_gamma);
      }

      DrawHLine("L_" + IntegerToString(drawn), s.us500_strike, lbl, clr, sty, wd);
   }

   //--- Panel 1: Estado en vivo, Volumen, Griegas y Proyeccion (SIEMPRE IZQUIERDA)
   if(InpShowHudPanel)
   {
      int x = InpLeftX, y = InpTopY, w = 445, h = 212;
      DrawBox("HUD_BG", x, y, w, h);

      double tot_v = (double)(g_tot_call_vol + g_tot_put_vol);
      double c_pct = (tot_v > 0) ? (g_tot_call_vol / tot_v) * 100.0 : 50.0;
      double p_pct = (tot_v > 0) ? (g_tot_put_vol  / tot_v) * 100.0 : 50.0;

      string proy = "Esperando datos de CBOE...";
      color  p_clr = clrSilver;
      if(has_magnet && curr_price > 0)
      {
         double dist_mag = top_magnet.us500_strike - curr_price;
         string dir_txt  = (dist_mag >= 0) ? "ARRIBA (Iman alcista)" : "ABAJO (Iman bajista)";
         if(MathAbs(dist_mag) <= 8.0)
            proy = StringFormat("SOBRE EL IMAN #%s (%.1f) -> Zona de consolidacion/giro", top_magnet.dom_type, top_magnet.us500_strike);
         else if(has_call && curr_price > top_call.us500_strike)
            proy = StringFormat("SOBRE CALL WALL %.1f -> Extension alcista o rechazo al Iman %.1f", top_call.us500_strike, top_magnet.us500_strike);
         else if(has_put && curr_price < top_put.us500_strike)
            proy = StringFormat("BAJO PUT WALL %.1f -> Panico bajista o rebote al Iman %.1f", top_put.us500_strike, top_magnet.us500_strike);
         else
            proy = StringFormat("Precio apunta %s -> %.1f (%s Vol:%s)", dir_txt, top_magnet.us500_strike, top_magnet.dom_type, FmtK(top_magnet.dom_vol));

         p_clr = (dist_mag >= 0) ? clrLimeGreen : clrTomato;
      }

      DrawLeftText("H0", x + 10, y + 8,  StringFormat("CBOE %s 0DTE (Exp:%s) | Open:%.1f (+%d/-%d)", src_tag, g_exp_date, daily_open, InpStrikesAbove, InpStrikesBelow), clrGold, 9, true);
      DrawLeftText("H1", x + 10, y + 25, "Sync: " + g_updated + " | Nota: CBOE ~15m delay (Auto cada 5 min)", clrSilver, 8, false);
      DrawLeftText("H2", x + 10, y + 39, "---------------------------------------------------------------------", C'60,70,90', 8, false);

      if(has_magnet)
         DrawLeftText("H3", x + 10, y + 53, StringFormat("IMAN #1 VOL: %.1f (%s %.0f%s) | Vol:%s OI:%s", top_magnet.us500_strike, src_tag, top_magnet.raw_strike, (top_magnet.dom_type=="CALL"?"C":"P"), FmtK(top_magnet.dom_vol), FmtK(top_magnet.dom_oi)), clrAqua, 8, true);
      else
         DrawLeftText("H3", x + 10, y + 53, "IMAN #1 VOL: Sin datos", clrSilver, 8, true);

      if(has_magnet)
         DrawLeftText("H4", x + 10, y + 69, StringFormat("   Griegas Iman -> IV: %.1f%% | Delta: %.2f | Gamma: %.4f", top_magnet.dom_iv * 100.0, top_magnet.dom_delta, top_magnet.dom_gamma), clrWhite, 8, false);
      else
         DrawLeftText("H4", x + 10, y + 69, "", clrWhite, 8, false);

      if(has_call)
         DrawLeftText("H5", x + 10, y + 87, StringFormat("CALL WALL: %.1f (%.0fC) | Vol:%s OI:%s IV:%.0f%% G:%.3f", top_call.us500_strike, top_call.raw_strike, FmtK(top_call.dom_vol), FmtK(top_call.dom_oi), top_call.dom_iv*100.0, top_call.dom_gamma), InpColorCallMain, 8, false);
      if(has_put)
         DrawLeftText("H6", x + 10, y + 103, StringFormat("PUT  WALL: %.1f (%.0fP) | Vol:%s OI:%s IV:%.0f%% G:%.3f", top_put.us500_strike, top_put.raw_strike, FmtK(top_put.dom_vol), FmtK(top_put.dom_oi), top_put.dom_iv*100.0, top_put.dom_gamma), InpColorPutMain, 8, false);
      if(has_oi)
         DrawLeftText("H7", x + 10, y + 119, StringFormat("MAYOR OI : %.1f (%s) | OI:%s Vol:%s", max_oi_lvl.us500_strike, max_oi_lvl.dom_type, FmtK(max_oi_lvl.dom_oi), FmtK(max_oi_lvl.dom_vol)), clrGold, 8, false);

      DrawLeftText("H8", x + 10, y + 137, StringFormat("FLUJO 0DTE: Calls %.0f%% (%s) vs Puts %.0f%% (%s)", c_pct, FmtK(g_tot_call_vol), p_pct, FmtK(g_tot_put_vol)), (c_pct >= p_pct ? clrLimeGreen : clrTomato), 8, true);
      DrawLeftText("H9", x + 10, y + 155, "PROYECCION HACIA DONDE VA EL PRECIO:", clrGold, 8, true);
      DrawLeftText("H10", x + 10, y + 172, proy, p_clr, 8, true);
      DrawLeftText("H11", x + 10, y + 190, StringFormat("Ref Spot %s: %.2f | Ratio US500/SPY: %.4f", src_tag, g_spot_ref, g_ratio), clrDarkGray, 8, false);
   }
   else
   {
      ObjectsDeleteAll(0, PREFIX_HUD());
   }

   //--- Panel 2: Guia explicativa de Vol / IV / Delta / Gamma / Int (SIEMPRE IZQUIERDA)
   if(InpShowGuidePanel)
   {
      int gx = InpLeftX, gy = InpTopY + 220, gw = 445, gh = 165;
      DrawBox("GUIDE_BG", gx, gy, gw, gh);

      DrawLeftText("G0", gx + 10, gy + 8,  "GUIA RAPIDA CBOE 0DTE (Vol / IV / Delta / Gamma / Int)", clrWhite, 8, true);
      DrawLeftText("G1", gx + 10, gy + 24, "---------------------------------------------------------------------", C'60,70,90', 8, false);
      DrawLeftText("G2", gx + 10, gy + 38, "Vol   : Contratos operados HOY. Es el iman vivo mas fuerte del dia.", clrAqua, 8, false);
      DrawLeftText("G3", gx + 10, gy + 54, "Int   : Open Interest (OI). Muros estructurales abiertos de dias previos.", clrGold, 8, false);
      DrawLeftText("G4", gx + 10, gy + 70, "IV    : Volatilidad Implicita. Si sube rapido, espera velas mas amplias.", clrSilver, 8, false);
      DrawLeftText("G5", gx + 10, gy + 86, "Delta : Probabilidad aprox. de llegar al strike (0.50=50%, 0.20=20%).", clrSilver, 8, false);
      DrawLeftText("G6", gx + 10, gy + 102,"Gamma : Aceleracion de cobertura MM. Gamma alta = iman o latigazo.", clrLimeGreen, 8, false);
      DrawLeftText("G7", gx + 10, gy + 122,"Nota de actualizacion: CBOE actualiza cada 15 min (script auto cada 5m).", clrOrange, 8, true);
      DrawLeftText("G8", gx + 10, gy + 140,"Lineas gruesas = Mayores imanes de Volumen/OI dentro de +-20 strikes.", clrSilver, 8, false);
   }

   ChartRedraw(0);
}

string PREFIX_HUD() { return g_prefix + "HUD_"; }

void DrawHLine(string key, double price, string label, color clr, ENUM_LINE_STYLE style, int width)
{
   string obj = g_prefix + key;
   ObjectCreate(0, obj, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj, OBJPROP_BACK, false);
   ObjectSetDouble(0,  obj, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_STYLE, style);
   ObjectSetInteger(0, obj, OBJPROP_WIDTH, width);
   ObjectSetString(0,  obj, OBJPROP_TEXT, label);
   ObjectSetString(0,  obj, OBJPROP_TOOLTIP, label + " @ " + DoubleToString(price, _Digits));

   string t_obj = g_prefix + "T_" + key;
   datetime t_pos = TimeCurrent() + PeriodSeconds(_Period) * 2;
   ObjectCreate(0, t_obj, OBJ_TEXT, 0, t_pos, price);
   ObjectSetInteger(0, t_obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, t_obj, OBJPROP_BACK, false);
   ObjectSetInteger(0, t_obj, OBJPROP_TIME, 0, t_pos);
   ObjectSetDouble(0,  t_obj, OBJPROP_PRICE, 0, price);
   ObjectSetString(0,  t_obj, OBJPROP_TEXT, "  " + label + " [" + DoubleToString(price, _Digits) + "]");
   ObjectSetInteger(0, t_obj, OBJPROP_COLOR, clr);
   ObjectSetString(0,  t_obj, OBJPROP_FONT, "Segoe UI Bold");
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
