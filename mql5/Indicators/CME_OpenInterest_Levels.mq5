//+------------------------------------------------------------------+
//|                                    CME_OpenInterest_Levels.mq5   |
//|                                  Copyright 2026, Antigravity     |
//|     Lineas Diarias de Open Interest CME (+-200 pts & Mayor C/P)  |
//+------------------------------------------------------------------+
#property copyright   "Antigravity Trading Tools"
#property link        "https://github.com"
#property version     "2.05"
#property description "Plotea los strikes con mayor Open Interest dentro de +-300 pts desde la Apertura del Dia de IC Markets. Muestra Call o Put mayor por strike, con lineas mas gruesas para los mas grandes."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//+------------------------------------------------------------------+
//| PARAMETROS DE ENTRADA                                            |
//+------------------------------------------------------------------+
input group "=== Filtro de Rango y Cantidad de Niveles ===";
input double          InpRangePoints     = 300.0;         // Rango arriba/abajo desde la Apertura del Dia (0 = sin filtro)
input int             InpMaxLevelsShow   = 20;            // Maximo de niveles mas grandes a dibujar en el rango
input long            InpMinOI           = 1;             // Open Interest minimo para dibujar
input bool            InpShowOpenLine    = true;          // Dibujar linea de Apertura del Dia (referencia)

input group "=== Ajuste de Base (Futuro CME vs CFD IC Markets) ===";
input double          InpExtraOffset     = 0.0;           // Offset extra manual (ES ya trae -20 desde el puente)
input bool            InpAutoLoadCSV     = true;          // Leer automaticamente CME_OpenInterest_Full.csv
input int             InpReloadMinutes   = 1;             // Recargar CSV cada N minutos
input bool            InpShowMiniBadge   = true;          // Mostrar etiqueta compacta en esquina superior

input group "=== Niveles Manuales de Respaldo (si > 0) ===";
input double          InpCall1Strike     = 0.0;           // Call Wall 1 Manual
input double          InpCall2Strike     = 0.0;           // Call Wall 2 Manual
input double          InpPut1Strike      = 0.0;           // Put Wall 1 Manual
input double          InpPut2Strike      = 0.0;           // Put Wall 2 Manual

input group "=== Diseno de Lineas ===";
input color           InpColorCallMain   = clrLimeGreen;      // Color Call dominante (Top 1-2)
input color           InpColorCallSec    = clrMediumSeaGreen; // Color Call dominante (resto)
input color           InpColorPutMain    = clrCrimson;        // Color Put dominante (Top 1-2)
input color           InpColorPutSec     = clrTomato;         // Color Put dominante (resto)

//--- Estructura por Strike unico (Call vs Put)
struct StrikeLevel
{
   double strike;
   long   call_oi;
   long   put_oi;
   string dom_type; // "CALL" o "PUT" (el que sea mayor)
   long   dom_oi;   // OI del lado ganador
};

//--- Variables internas
string      g_prefix      = "CMEOI_";
datetime    g_last_reload = 0;
int         g_last_day    = -1;

StrikeLevel g_levels[];
string      g_cme_code = "MANUAL";
string      g_exp_date = "Hoy";
string      g_updated  = "-";

//+------------------------------------------------------------------+
//| Agregar o combinar Call/Put en el mismo Strike                   |
//+------------------------------------------------------------------+
void UpsertStrike(double strike, string tipo, long oi)
{
   if(strike <= 0 || oi <= 0) return;
   double adj_strike = NormalizeDouble(strike + InpExtraOffset, _Digits);

   int sz = ArraySize(g_levels);
   int idx = -1;
   for(int i = 0; i < sz; i++)
   {
      if(MathAbs(g_levels[i].strike - adj_strike) < (_Point * 2.0 + 1e-6))
      {
         idx = i;
         break;
      }
   }

   if(idx < 0)
   {
      idx = sz;
      ArrayResize(g_levels, sz + 1);
      g_levels[idx].strike  = adj_strike;
      g_levels[idx].call_oi = 0;
      g_levels[idx].put_oi  = 0;
   }

   if(tipo == "CALL")
   {
      if(oi > g_levels[idx].call_oi) g_levels[idx].call_oi = oi;
   }
   else if(tipo == "PUT")
   {
      if(oi > g_levels[idx].put_oi) g_levels[idx].put_oi = oi;
   }

   // Determinar ganador unico en ese strike: el mayor entre Call y Put
   if(g_levels[idx].call_oi >= g_levels[idx].put_oi)
   {
      g_levels[idx].dom_type = "CALL";
      g_levels[idx].dom_oi   = g_levels[idx].call_oi;
   }
   else
   {
      g_levels[idx].dom_type = "PUT";
      g_levels[idx].dom_oi   = g_levels[idx].put_oi;
   }
}

//+------------------------------------------------------------------+
//| Ordenar todos los strikes descendentemente por el OI ganador     |
//+------------------------------------------------------------------+
void SortByDominantOIDesc()
{
   int n = ArraySize(g_levels);
   for(int i = 0; i < n - 1; i++)
   {
      for(int j = i + 1; j < n; j++)
      {
         if(g_levels[j].dom_oi > g_levels[i].dom_oi)
         {
            StrikeLevel tmp = g_levels[i];
            g_levels[i] = g_levels[j];
            g_levels[j] = tmp;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Leer CME_OpenInterest_Full.csv (o respaldo CME_OpenInterest.csv) |
//+------------------------------------------------------------------+
void LoadCSV()
{
   ArrayResize(g_levels, 0);
   g_cme_code = "MANUAL";
   g_exp_date = "Hoy";
   g_updated  = "-";

   if(InpCall1Strike > 0) UpsertStrike(InpCall1Strike, "CALL", 999999);
   if(InpCall2Strike > 0) UpsertStrike(InpCall2Strike, "CALL", 888888);
   if(InpPut1Strike  > 0) UpsertStrike(InpPut1Strike,  "PUT",  999999);
   if(InpPut2Strike  > 0) UpsertStrike(InpPut2Strike,  "PUT",  888888);

   if(!InpAutoLoadCSV)
   {
      SortByDominantOIDesc();
      return;
   }

   string sym = _Symbol;
   StringToUpper(sym);

   int h = FileOpen("CME_OpenInterest_Full.csv", FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
      h = FileOpen("CME_OpenInterest_Full.csv", FILE_READ | FILE_TXT | FILE_ANSI);

   if(h != INVALID_HANDLE)
   {
      while(!FileIsEnding(h))
      {
         string line = FileReadString(h);
         StringTrimLeft(line);
         StringTrimRight(line);
         if(StringLen(line) < 5 || StringFind(line, "SYMBOL_PREFIX") == 0) continue;

         string cols[];
         int n = StringSplit(line, ',', cols);
         if(n < 6) continue;

         string pref = cols[0];
         StringToUpper(pref);
         if(StringFind(sym, pref) == 0)
         {
            g_cme_code = cols[1];
            g_exp_date = cols[2];
            string tipo = cols[3];
            StringToUpper(tipo);
            double st = StringToDouble(cols[4]);
            long   oi = StringToInteger(cols[5]);
            if(n >= 7) g_updated = cols[6];

            UpsertStrike(st, tipo, oi);
         }
      }
      FileClose(h);
   }

   if(ArraySize(g_levels) == 0)
   {
      int h2 = FileOpen("CME_OpenInterest.csv", FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
      if(h2 == INVALID_HANDLE)
         h2 = FileOpen("CME_OpenInterest.csv", FILE_READ | FILE_TXT | FILE_ANSI);
      if(h2 != INVALID_HANDLE)
      {
         while(!FileIsEnding(h2))
         {
            string line = FileReadString(h2);
            StringTrimLeft(line);
            StringTrimRight(line);
            if(StringLen(line) < 5 || StringFind(line, "SYMBOL_PREFIX") == 0) continue;

            string cols[];
            int n = StringSplit(line, ',', cols);
            if(n < 11) continue;

            string pref = cols[0];
            StringToUpper(pref);
            if(StringFind(sym, pref) == 0)
            {
               g_cme_code = cols[1];
               g_exp_date = cols[2];
               UpsertStrike(StringToDouble(cols[3]), "CALL", StringToInteger(cols[4]));
               UpsertStrike(StringToDouble(cols[5]), "CALL", StringToInteger(cols[6]));
               UpsertStrike(StringToDouble(cols[7]), "PUT",  StringToInteger(cols[8]));
               UpsertStrike(StringToDouble(cols[9]), "PUT",  StringToInteger(cols[10]));
               if(n >= 12) g_updated = cols[11];
               break;
            }
         }
         FileClose(h2);
      }
   }

   SortByDominantOIDesc();
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "CME OI Levels [" + _Symbol + "]");
   LoadCSV();
   g_last_reload = TimeCurrent();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, g_prefix);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
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

   double daily_open_arr[];
   double anchor_price = open[0];
   if(CopyOpen(_Symbol, PERIOD_D1, 0, 1, daily_open_arr) > 0 && daily_open_arr[0] > 0)
      anchor_price = daily_open_arr[0];

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   bool new_day = (g_last_day != -1 && dt.day != g_last_day);
   g_last_day = dt.day;

   if(new_day || (TimeCurrent() - g_last_reload >= InpReloadMinutes * 60))
   {
      LoadCSV();
      g_last_reload = TimeCurrent();
   }

   DrawFilteredLevels(anchor_price);
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Dibujar los niveles dominantes dentro de +-InpRangePoints        |
//+------------------------------------------------------------------+
void DrawFilteredLevels(double anchor_price)
{
   ObjectsDeleteAll(0, g_prefix + "L_");
   ObjectsDeleteAll(0, g_prefix + "T_");

   if(InpShowOpenLine && anchor_price > 0)
   {
      string open_lbl = (InpRangePoints > 0) ? StringFormat("OPEN DIA (Ref +-%.0f)", InpRangePoints) : "OPEN DIA";
      DrawOILine("L_OPEN", anchor_price, open_lbl, clrDimGray, STYLE_DASHDOT, 1);
   }

   int total_levels = ArraySize(g_levels);
   int drawn_total  = 0;
   int call_rank    = 0;
   int put_rank     = 0;
   double top_call  = 0, top_put = 0;

   for(int i = 0; i < total_levels && drawn_total < InpMaxLevelsShow; i++)
   {
      double st = g_levels[i].strike;
      long   oi = g_levels[i].dom_oi;
      string tp = g_levels[i].dom_type;

      if(oi < InpMinOI) continue;
      if(InpRangePoints > 0.0 && MathAbs(st - anchor_price) > InpRangePoints)
         continue;

      drawn_total++;

      color clr;
      ENUM_LINE_STYLE sty;
      int wd;
      string lbl;

      if(tp == "CALL")
      {
         call_rank++;
         if(call_rank == 1) top_call = st;
         bool is_big = (call_rank <= 2 || oi >= 1000);
         clr = is_big ? InpColorCallMain : InpColorCallSec;
         sty = is_big ? STYLE_SOLID : STYLE_DOT;
         wd  = (call_rank == 1) ? 4 : (is_big ? 3 : 1);
         lbl = StringFormat("CALL #%d (OI:%I64d)", call_rank, oi);
      }
      else
      {
         put_rank++;
         if(put_rank == 1) top_put = st;
         bool is_big = (put_rank <= 2 || oi >= 1000);
         clr = is_big ? InpColorPutMain : InpColorPutSec;
         sty = is_big ? STYLE_SOLID : STYLE_DOT;
         wd  = (put_rank == 1) ? 4 : (is_big ? 3 : 1);
         lbl = StringFormat("PUT #%d (OI:%I64d)", put_rank, oi);
      }

      DrawOILine("L_" + IntegerToString(drawn_total), st, lbl, clr, sty, wd);
   }

   if(InpShowMiniBadge)
   {
      string range_txt = (InpRangePoints > 0) ? StringFormat("Open %s +-%.0f", DoubleToString(anchor_price, _Digits), InpRangePoints) : "ALL";
      string badge = StringFormat("CME %s (%s) | %s | C:%d P:%d | C1:%s P1:%s",
                                  g_cme_code, g_exp_date, range_txt,
                                  call_rank, put_rank,
                                  (top_call > 0 ? DoubleToString(top_call, _Digits) : "-"),
                                  (top_put  > 0 ? DoubleToString(top_put,  _Digits) : "-"));
      string obj = g_prefix + "BADGE";
      if(ObjectFind(0, obj) < 0)
      {
         ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
         ObjectSetInteger(0, obj, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
         ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, obj, OBJPROP_BACK, false);
      }
      ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, 12);
      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, 18);
      ObjectSetString(0,  obj, OBJPROP_TEXT, badge);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, clrGold);
      ObjectSetString(0,  obj, OBJPROP_FONT, "Segoe UI Bold");
      ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 8);
   }

   ChartRedraw(0);
}

void DrawOILine(string key, double price, string label, color clr, ENUM_LINE_STYLE style, int width)
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

   // Etiqueta a la derecha de la vela actual sin solaparse
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
//+------------------------------------------------------------------+
