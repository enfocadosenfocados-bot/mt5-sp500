//+------------------------------------------------------------------+
//|                                       DailyVolumeProfilePOC.mq5  |
//|                                  Copyright 2026, Antigravity     |
//|   Volume Profile, POC, VWAP Hoy/Ayer, Sesiones & CME OI Walls    |
//+------------------------------------------------------------------+
#property copyright   "Antigravity Trading Tools"
#property link        "https://github.com"
#property version     "2.20"
#property description "Perfil de Volumen Diario, POC Hoy/Ayer, VWAP Hoy/Ayer, Max/Min Sesiones y Lineas de Open Interest de CME Group."
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- Plot 1: VWAP del Dia (curva intradia)
#property indicator_label1  "VWAP Hoy"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrYellow
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- Plot 2: VWAP del Dia Anterior (linea fija proyectada)
#property indicator_label2  "VWAP Ayer"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrMagenta
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

//+------------------------------------------------------------------+
//| ENUMERACIONES                                                    |
//+------------------------------------------------------------------+
enum ENUM_VOL_MODE
{
   VOL_MODE_AUTO = 0,   // Deteccion automatica (Real si existe, sino Tick)
   VOL_MODE_TICK = 1,   // Tick Volume (Forex / CFDs)
   VOL_MODE_REAL = 2    // Real Volume (Futuros / Acciones / Cripto)
};

enum ENUM_PROFILE_SIDE
{
   SIDE_DAY_OPEN   = 0, // Dibujar desde la apertura del dia hacia la derecha
   SIDE_RIGHT_EDGE = 1  // Dibujar pegado al precio actual hacia la izquierda
};

//+------------------------------------------------------------------+
//| PARAMETROS DE ENTRADA                                            |
//+------------------------------------------------------------------+
input group "=== Configuracion del Perfil de Volumen ===";
input ENUM_VOL_MODE      InpVolMode         = VOL_MODE_AUTO;  // Modo de Volumen
input int                InpLevelsCount     = 50;             // Numero de niveles del perfil
input double             InpValueAreaPct    = 70.0;           // Porcentaje Value Area (% VA)
input int                InpMaxBarsWidth    = 35;             // Ancho maximo del histograma (en velas)
input ENUM_PROFILE_SIDE  InpProfileSide     = SIDE_DAY_OPEN;  // Posicion del histograma

input group "=== VWAP Hoy y VWAP Ayer ===";
input bool               InpShowVWAPToday   = true;           // Mostrar VWAP del Dia (Curva)
input color              InpColorVWAPToday  = clrYellow;      // Color VWAP Hoy
input bool               InpShowVWAPYest    = true;           // Mostrar VWAP de Ayer (Linea Fija)
input color              InpColorVWAPYest   = clrMagenta;     // Color VWAP Ayer

input group "=== POC de Hoy y Value Area ===";
input color              InpColorPOC        = clrRed;         // Color POC de Hoy
input int                InpWidthPOC        = 2;              // Grosor linea POC Hoy
input bool               InpExtendPOC       = true;           // Extender linea POC hacia adelante
input color              InpColorVAH_VAL    = clrAqua;        // Color lineas VAH y VAL
input ENUM_LINE_STYLE    InpStyleVAH_VAL    = STYLE_DASH;     // Estilo lineas VAH y VAL

input group "=== POC FIJO del Dia Anterior ===";
input bool               InpShowYesterday   = true;           // Mostrar POC y Datos de Ayer
input color              InpColorYPOC       = clrGold;        // Color POC Ayer (FIJO)
input int                InpWidthYPOC       = 2;              // Grosor POC Ayer
input ENUM_LINE_STYLE    InpStyleYPOC       = STYLE_SOLID;    // Estilo POC Ayer

input group "=== Maximos y Minimos por Sesion (Horas Broker) ===";
input bool               InpShowSessions    = true;           // Mostrar Max/Min de Sesiones
input int                InpAsiaStart       = 0;              // Asia Inicio
input int                InpAsiaEnd         = 8;              // Asia Fin
input color              InpAsiaColor       = clrMediumPurple;// Color Asia
input int                InpLondonStart     = 8;              // Londres Inicio
input int                InpLondonEnd       = 16;             // Londres Fin
input color              InpLondonColor     = clrRoyalBlue;   // Color Londres
input int                InpNYStart         = 14;             // Nueva York Inicio
input int                InpNYEnd           = 22;             // Nueva York Fin
input color              InpNYColor         = clrDarkOrange;  // Color Nueva York

input group "=== CME Open Interest (2, 3 o 4 Niveles) ===";
input bool               InpShowOI          = true;           // Mostrar Lineas de Open Interest (CME)
input int                InpOINumLevels     = 4;              // Cantidad de Niveles OI (2, 3 o 4)
input bool               InpAutoLoadOICSV   = true;           // Cargar auto desde Common/Files/CME_OpenInterest.csv
input double             InpManualCall1     = 0.0;            // Manual Call Wall 1 (0 = usar CSV)
input double             InpManualCall2     = 0.0;            // Manual Call Wall 2 (0 = usar CSV)
input double             InpManualPut1      = 0.0;            // Manual Put Wall 1  (0 = usar CSV)
input double             InpManualPut2      = 0.0;            // Manual Put Wall 2  (0 = usar CSV)
input color              InpColorCallWall   = clrLimeGreen;   // Color Call Walls (Resistencias Opciones)
input color              InpColorPutWall    = clrCrimson;     // Color Put Walls (Soportes Opciones)

input group "=== Colores del Histograma ===";
input color              InpColorVA         = clrDodgerBlue;  // Barras dentro del Value Area
input color              InpColorNonVA      = clrDarkSlateGray;// Barras fuera del Value Area
input color              InpColorPocBar     = clrCrimson;     // Barra del nivel POC

input group "=== Panel Informativo y Proyeccion ===";
input bool               InpShowHUD         = true;           // Mostrar Panel informativo
input int                InpHudX            = 12;             // Posicion X
input int                InpHudY            = 24;             // Posicion Y
input color              InpHudBg           = C'14,18,28';    // Color Fondo Panel

//--- Buffers del indicador
double BufferVWAPToday[];
double BufferVWAPYest[];

//--- Variables internas
string   g_prefix          = "DVP_";
bool     g_use_real_volume = false;
int      g_drawn_bars      = 0;
datetime g_last_csv_reload = 0;

//--- Variables de Open Interest
double g_call1 = 0, g_call2 = 0;
double g_put1  = 0, g_put2  = 0;
long   g_call1_oi = 0, g_call2_oi = 0;
long   g_put1_oi  = 0, g_put2_oi  = 0;
string g_oi_exp   = "";

//+------------------------------------------------------------------+
//| Helper: Cargar CSV multi-activo de Open Interest de CME          |
//+------------------------------------------------------------------+
void LoadCmeOpenInterestCSV()
{
   g_call1 = InpManualCall1;
   g_call2 = InpManualCall2;
   g_put1  = InpManualPut1;
   g_put2  = InpManualPut2;
   g_call1_oi = 0; g_call2_oi = 0;
   g_put1_oi  = 0; g_put2_oi  = 0;
   g_oi_exp   = "Manual";

   if(!InpAutoLoadOICSV) return;

   string filename = "CME_OpenInterest.csv";
   // Primero busca en carpeta comun (compartida por todos los MT5), luego en local MQL5/Files
   int handle = FileOpen(filename, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(handle == INVALID_HANDLE)
      handle = FileOpen(filename, FILE_READ | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;

   string sym_upper = _Symbol;
   StringToUpper(sym_upper);

   while(!FileIsEnding(handle))
   {
      string line = FileReadString(handle);
      StringTrimLeft(line);
      StringTrimRight(line);
      if(StringLen(line) < 5 || StringFind(line, "SYMBOL_PREFIX") == 0) continue;

      string cols[];
      int count = StringSplit(line, ',', cols);
      if(count < 11) continue;

      string prefix = cols[0];
      StringToUpper(prefix);

      if(StringFind(sym_upper, prefix) == 0)
      {
         g_oi_exp   = cols[2];
         if(InpManualCall1 <= 0) g_call1    = StringToDouble(cols[3]);
         g_call1_oi = StringToInteger(cols[4]);
         if(InpManualCall2 <= 0) g_call2    = StringToDouble(cols[5]);
         g_call2_oi = StringToInteger(cols[6]);
         if(InpManualPut1  <= 0) g_put1     = StringToDouble(cols[7]);
         g_put1_oi  = StringToInteger(cols[8]);
         if(InpManualPut2  <= 0) g_put2     = StringToDouble(cols[9]);
         g_put2_oi  = StringToInteger(cols[10]);
         break;
      }
   }
   FileClose(handle);
}

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufferVWAPToday, INDICATOR_DATA);
   SetIndexBuffer(1, BufferVWAPYest,  INDICATOR_DATA);

   ArraySetAsSeries(BufferVWAPToday, true);
   ArraySetAsSeries(BufferVWAPYest,  true);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpColorVWAPToday);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpColorVWAPYest);

   IndicatorSetString(INDICATOR_SHORTNAME, "Volume Profile + VWAP + CME OI");

   if(InpVolMode == VOL_MODE_AUTO)
   {
      double realVolTest = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_REAL);
      g_use_real_volume = (realVolTest > 0);
   }
   else
   {
      g_use_real_volume = (InpVolMode == VOL_MODE_REAL);
   }

   LoadCmeOpenInterestCSV();
   g_last_csv_reload = TimeCurrent();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, g_prefix);
   ChartRedraw(0);
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
                const long &real_volume[],
                const int &spread[])
{
   if(rates_total < 5) return 0;

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(tick_volume, true);
   ArraySetAsSeries(real_volume, true);

   // Recargar CSV cada 5 minutos por si se actualizo a las 00:00 del broker
   if(TimeCurrent() - g_last_csv_reload >= 300)
   {
      LoadCmeOpenInterestCSV();
      g_last_csv_reload = TimeCurrent();
   }

   // Inicializar buffers VWAP
   int init_limit = (prev_calculated == 0) ? rates_total - 1 : MathMin(rates_total - 1, rates_total - prev_calculated + 5);
   for(int i = init_limit; i >= 0; i--)
   {
      BufferVWAPToday[i] = EMPTY_VALUE;
      BufferVWAPYest[i]  = EMPTY_VALUE;
   }

   // 1. Identificar rango de velas de HOY y de AYER
   MqlDateTime dt_curr, dt_bar;
   TimeToStruct(time[0], dt_curr);

   int today_start_bar = 0;
   int yest_start_bar  = -1;
   int yest_end_bar    = -1;
   int day_counter     = 0;
   int prev_day        = dt_curr.day;
   int prev_mon        = dt_curr.mon;

   for(int i = 0; i < rates_total; i++)
   {
      TimeToStruct(time[i], dt_bar);
      if(dt_bar.day != prev_day || dt_bar.mon != prev_mon || dt_bar.year != dt_curr.year)
      {
         day_counter++;
         prev_day = dt_bar.day;
         prev_mon = dt_bar.mon;
         if(day_counter == 1)
         {
            today_start_bar = i - 1;
            yest_end_bar    = i;
         }
         else if(day_counter == 2)
         {
            yest_start_bar = i - 1;
            break;
         }
      }
   }
   if(today_start_bar < 0) today_start_bar = 0;
   if(yest_start_bar < 0)  yest_start_bar = rates_total - 1;

   datetime today_open_time = time[today_start_bar];
   datetime curr_time       = time[0];

   // 2. Calcular VWAP de HOY (de inicio del dia hacia vela 0)
   double cum_pv_today = 0.0;
   double cum_v_today  = 0.0;
   double vwap_today_val = 0.0;

   for(int i = today_start_bar; i >= 0; i--)
   {
      double bv = (g_use_real_volume && real_volume[i] > 0) ? (double)real_volume[i] : (double)tick_volume[i];
      if(bv <= 0) bv = 1.0;
      double tp = (high[i] + low[i] + close[i]) / 3.0;
      cum_pv_today += tp * bv;
      cum_v_today  += bv;
      vwap_today_val = cum_pv_today / cum_v_today;
      if(InpShowVWAPToday)
         BufferVWAPToday[i] = vwap_today_val;
   }

   // 3. Calcular VWAP de AYER (curva en ayer + valor final proyectado en hoy)
   double cum_pv_yest   = 0.0;
   double cum_v_yest    = 0.0;
   double vwap_yest_val = 0.0;

   if(yest_end_bar > 0 && yest_start_bar >= yest_end_bar)
   {
      for(int i = yest_start_bar; i >= yest_end_bar; i--)
      {
         double bv = (g_use_real_volume && real_volume[i] > 0) ? (double)real_volume[i] : (double)tick_volume[i];
         if(bv <= 0) bv = 1.0;
         double tp = (high[i] + low[i] + close[i]) / 3.0;
         cum_pv_yest += tp * bv;
         cum_v_yest  += bv;
         vwap_yest_val = cum_pv_yest / cum_v_yest;
         if(InpShowVWAPYest)
            BufferVWAPYest[i] = vwap_yest_val;
      }
      // Proyectar el VWAP final de ayer como linea fija durante todo hoy
      if(InpShowVWAPYest && vwap_yest_val > 0)
      {
         for(int i = today_start_bar; i >= 0; i--)
            BufferVWAPYest[i] = vwap_yest_val;
      }
   }

   // 4. Calcular Perfil, POC y Sesiones de HOY
   double today_high = high[0], today_low = low[0], today_vol = 0;
   double buy_vol = 0, sell_vol = 0;

   double a_high = 0, a_low = 9999999; datetime a_t1 = 0, a_t2 = 0; bool a_active = false;
   double l_high = 0, l_low = 9999999; datetime l_t1 = 0, l_t2 = 0; bool l_active = false;
   double n_high = 0, n_low = 9999999; datetime n_t1 = 0, n_t2 = 0; bool n_active = false;

   for(int i = 0; i <= today_start_bar; i++)
   {
      if(high[i] > today_high) today_high = high[i];
      if(low[i]  < today_low)  today_low  = low[i];

      double bv = (g_use_real_volume && real_volume[i] > 0) ? (double)real_volume[i] : (double)tick_volume[i];
      today_vol += bv;

      if(close[i] >= open[i]) buy_vol += bv;
      else                    sell_vol += bv;

      TimeToStruct(time[i], dt_bar);
      int hr = dt_bar.hour;

      if(hr >= InpAsiaStart && hr < InpAsiaEnd)
      {
         if(high[i] > a_high) a_high = high[i];
         if(low[i]  < a_low)  a_low  = low[i];
         if(a_t1 == 0 || time[i] < a_t1) a_t1 = time[i];
         if(time[i] > a_t2) a_t2 = time[i];
         a_active = true;
      }
      if(hr >= InpLondonStart && hr < InpLondonEnd)
      {
         if(high[i] > l_high) l_high = high[i];
         if(low[i]  < l_low)  l_low  = low[i];
         if(l_t1 == 0 || time[i] < l_t1) l_t1 = time[i];
         if(time[i] > l_t2) l_t2 = time[i];
         l_active = true;
      }
      if(hr >= InpNYStart && hr < InpNYEnd)
      {
         if(high[i] > n_high) n_high = high[i];
         if(low[i]  < n_low)  n_low  = low[i];
         if(n_t1 == 0 || time[i] < n_t1) n_t1 = time[i];
         if(time[i] > n_t2) n_t2 = time[i];
         n_active = true;
      }
   }

   double range = today_high - today_low;
   if(range <= 0 || today_vol <= 0) return(rates_total);

   int num_levels = (InpLevelsCount >= 10 && InpLevelsCount <= 150) ? InpLevelsCount : 50;
   double step_price = range / (double)num_levels;
   if(step_price < _Point && _Point > 0)
   {
      step_price = _Point;
      num_levels = (int)MathCeil(range / step_price) + 1;
   }

   double vol_profile[];
   ArrayResize(vol_profile, num_levels);
   ArrayInitialize(vol_profile, 0.0);

   for(int i = 0; i <= today_start_bar; i++)
   {
      double bv = (g_use_real_volume && real_volume[i] > 0) ? (double)real_volume[i] : (double)tick_volume[i];
      if(bv <= 0) continue;

      int low_idx  = (int)MathFloor((low[i]  - today_low) / step_price);
      int high_idx = (int)MathFloor((high[i] - today_low) / step_price);

      if(low_idx < 0) low_idx = 0;
      if(high_idx >= num_levels) high_idx = num_levels - 1;

      int span = (high_idx - low_idx) + 1;
      double vol_per_lvl = bv / (double)span;

      for(int k = low_idx; k <= high_idx; k++) vol_profile[k] += vol_per_lvl;
   }

   double max_vol = 0;
   int poc_idx = 0;
   for(int k = 0; k < num_levels; k++)
   {
      if(vol_profile[k] > max_vol)
      {
         max_vol = vol_profile[k];
         poc_idx = k;
      }
   }
   double today_poc_price = today_low + (poc_idx * step_price) + (step_price * 0.5);

   // Value Area Hoy
   double target_va = today_vol * (InpValueAreaPct / 100.0);
   double curr_va   = vol_profile[poc_idx];
   int up_idx = poc_idx, down_idx = poc_idx;

   while(curr_va < target_va && (up_idx < num_levels - 1 || down_idx > 0))
   {
      double next_up   = (up_idx < num_levels - 1) ? vol_profile[up_idx + 1] : 0.0;
      double next_down = (down_idx > 0)           ? vol_profile[down_idx - 1] : 0.0;

      if(next_up >= next_down && up_idx < num_levels - 1)
      {
         up_idx++;
         curr_va += vol_profile[up_idx];
      }
      else if(down_idx > 0)
      {
         down_idx--;
         curr_va += vol_profile[down_idx];
      }
      else if(up_idx < num_levels - 1)
      {
         up_idx++;
         curr_va += vol_profile[up_idx];
      }
      else break;
   }
   double today_vah = today_low + (up_idx * step_price) + step_price;
   double today_val = today_low + (down_idx * step_price);

   // 5. POC FIJO DE AYER
   double y_poc_price = 0, y_total_vol = 0, y_high = 0, y_low = 0;
   if(InpShowYesterday && yest_end_bar > 0 && yest_start_bar >= yest_end_bar)
   {
      y_high = high[yest_end_bar];
      y_low  = low[yest_end_bar];
      for(int i = yest_end_bar; i <= yest_start_bar; i++)
      {
         if(high[i] > y_high) y_high = high[i];
         if(low[i]  < y_low)  y_low  = low[i];
         double bv = (g_use_real_volume && real_volume[i] > 0) ? (double)real_volume[i] : (double)tick_volume[i];
         y_total_vol += bv;
      }
      double y_range = y_high - y_low;
      if(y_range > 0)
      {
         double y_step = y_range / 50.0;
         double y_profile[];
         ArrayResize(y_profile, 50);
         ArrayInitialize(y_profile, 0.0);

         for(int i = yest_end_bar; i <= yest_start_bar; i++)
         {
            double bv = (g_use_real_volume && real_volume[i] > 0) ? (double)real_volume[i] : (double)tick_volume[i];
            int l_idx = (int)MathFloor((low[i]  - y_low) / y_step);
            int h_idx = (int)MathFloor((high[i] - y_low) / y_step);
            if(l_idx < 0) l_idx = 0;
            if(h_idx >= 50) h_idx = 49;
            int span = (h_idx - l_idx) + 1;
            double v_level = bv / (double)span;
            for(int k = l_idx; k <= h_idx; k++) y_profile[k] += v_level;
         }
         double y_max = 0; int y_max_idx = 0;
         for(int k = 0; k < 50; k++)
         {
            if(y_profile[k] > y_max) { y_max = y_profile[k]; y_max_idx = k; }
         }
         y_poc_price = y_low + (y_max_idx * y_step) + (y_step * 0.5);
      }
   }

   // 6. Renderizar todo
   RenderVisuals(today_open_time, curr_time, today_low, step_price, num_levels,
                 vol_profile, max_vol, poc_idx, today_poc_price,
                 down_idx, up_idx, today_vah, today_val, today_vol,
                 y_poc_price, y_total_vol, vwap_today_val, vwap_yest_val,
                 a_active, a_high, a_low, a_t1,
                 l_active, l_high, l_low, l_t1,
                 n_active, n_high, n_low, n_t1,
                 buy_vol, sell_vol, close[0]);

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Renderizar todos los elementos graficos                          |
//+------------------------------------------------------------------+
void RenderVisuals(datetime day_start, datetime curr_time,
                   double min_price, double step_price, int num_levels,
                   const double &vol_profile[], double max_vol,
                   int poc_idx, double today_poc,
                   int val_idx, int vah_idx, double today_vah, double today_val,
                   double today_vol, double y_poc, double y_vol,
                   double vwap_today, double vwap_yest,
                   bool a_act, double a_h, double a_l, datetime a_t1,
                   bool l_act, double l_h, double l_l, datetime l_t1,
                   bool n_act, double n_h, double n_l, datetime n_t1,
                   double buy_v, double sell_v, double current_price)
{
   int p_sec = PeriodSeconds(_Period);
   if(p_sec <= 0) p_sec = 60;

   if(num_levels < g_drawn_bars)
   {
      for(int k = num_levels; k < g_drawn_bars; k++)
         ObjectDelete(0, g_prefix + "B_" + IntegerToString(k));
   }
   g_drawn_bars = num_levels;

   // A. Barras Horizontales de Volumen
   for(int k = 0; k < num_levels; k++)
   {
      double p1 = min_price + (k * step_price);
      double p2 = p1 + step_price;
      double v  = vol_profile[k];

      int bar_len = (max_vol > 0) ? (int)MathRound((v / max_vol) * InpMaxBarsWidth) : 0;
      if(bar_len < 1 && v > 0) bar_len = 1;

      datetime t1, t2;
      if(InpProfileSide == SIDE_DAY_OPEN)
      {
         t1 = day_start;
         t2 = day_start + (bar_len * p_sec);
      }
      else
      {
         t2 = curr_time;
         t1 = curr_time - (bar_len * p_sec);
      }

      string b_name = g_prefix + "B_" + IntegerToString(k);
      color b_clr   = (k >= val_idx && k <= vah_idx) ? InpColorVA : InpColorNonVA;
      if(k == poc_idx) b_clr = InpColorPocBar;

      if(ObjectFind(0, b_name) < 0)
      {
         ObjectCreate(0, b_name, OBJ_RECTANGLE, 0, t1, p2, t2, p1);
         ObjectSetInteger(0, b_name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, b_name, OBJPROP_BACK, true);
         ObjectSetInteger(0, b_name, OBJPROP_FILL, true);
      }
      else
      {
         ObjectSetInteger(0, b_name, OBJPROP_TIME, 0, t1);
         ObjectSetDouble(0,  b_name, OBJPROP_PRICE, 0, p2);
         ObjectSetInteger(0, b_name, OBJPROP_TIME, 1, t2);
         ObjectSetDouble(0,  b_name, OBJPROP_PRICE, 1, p1);
      }
      ObjectSetInteger(0, b_name, OBJPROP_COLOR, b_clr);
      ObjectSetInteger(0, b_name, OBJPROP_BGCOLOR, b_clr);
   }

   datetime line_end = curr_time + (p_sec * 25);

   // B. Linea POC de Hoy, VAH, VAL
   DrawRayLine("L_POC", "◄ POC HOY", day_start, line_end, today_poc, InpColorPOC, STYLE_SOLID, InpWidthPOC);
   DrawRayLine("L_VAH", "VAH", day_start, line_end, today_vah, InpColorVAH_VAL, InpStyleVAH_VAL, 1);
   DrawRayLine("L_VAL", "VAL", day_start, line_end, today_val, InpColorVAH_VAL, InpStyleVAH_VAL, 1);

   // C. Etiquetas de VWAP Hoy y VWAP Ayer
   if(InpShowVWAPToday && vwap_today > 0)
      DrawTextTag("TAG_VWAP_T", line_end, vwap_today, "  VWAP Hoy: " + DoubleToString(vwap_today, _Digits), InpColorVWAPToday);
   if(InpShowVWAPYest && vwap_yest > 0)
      DrawTextTag("TAG_VWAP_Y", line_end, vwap_yest, "  VWAP Ayer: " + DoubleToString(vwap_yest, _Digits), InpColorVWAPYest);

   // D. Linea POC FIJO DE AYER
   if(InpShowYesterday && y_poc > 0)
      DrawRayLine("L_YPOC", "◄ POC AYER", day_start, line_end, y_poc, InpColorYPOC, InpStyleYPOC, InpWidthYPOC);

   // E. Maximos y Minimos de Sesiones
   if(InpShowSessions)
   {
      if(a_act && a_h > 0 && a_l < 9999999)
      {
         DrawSessionLine("S_ASIA_H", "Asia H", a_t1, line_end, a_h, InpAsiaColor);
         DrawSessionLine("S_ASIA_L", "Asia L", a_t1, line_end, a_l, InpAsiaColor);
      }
      if(l_act && l_h > 0 && l_l < 9999999)
      {
         DrawSessionLine("S_LON_H", "Lon H", l_t1, line_end, l_h, InpLondonColor);
         DrawSessionLine("S_LON_L", "Lon L", l_t1, line_end, l_l, InpLondonColor);
      }
      if(n_act && n_h > 0 && n_l < 9999999)
      {
         DrawSessionLine("S_NY_H", "NY H", n_t1, line_end, n_h, InpNYColor);
         DrawSessionLine("S_NY_L", "NY L", n_t1, line_end, n_l, InpNYColor);
      }
   }

   // F. LINEAS DE OPEN INTEREST DE CME GROUP (2, 3 o 4 niveles)
   if(InpShowOI)
   {
      int lvls = MathMax(2, MathMin(4, InpOINumLevels));
      if(g_call1 > 0)
         DrawRayLine("OI_C1", "▲ CALL 1 (OI:" + IntegerToString(g_call1_oi) + ")", day_start, line_end, g_call1, InpColorCallWall, STYLE_SOLID, 2);
      if(g_put1 > 0)
         DrawRayLine("OI_P1", "▼ PUT 1 (OI:" + IntegerToString(g_put1_oi) + ")", day_start, line_end, g_put1, InpColorPutWall, STYLE_SOLID, 2);
      if(lvls >= 3 && g_call2 > 0)
         DrawRayLine("OI_C2", "▲ CALL 2 (OI:" + IntegerToString(g_call2_oi) + ")", day_start, line_end, g_call2, InpColorCallWall, STYLE_DASH, 1);
      if(lvls >= 4 && g_put2 > 0)
         DrawRayLine("OI_P2", "▼ PUT 2 (OI:" + IntegerToString(g_put2_oi) + ")", day_start, line_end, g_put2, InpColorPutWall, STYLE_DASH, 1);
   }

   // G. Proyeccion de Puja y Objetivo
   double total_delta = buy_v + sell_v;
   double buy_pct  = (total_delta > 0) ? (buy_v / total_delta) * 100.0 : 50.0;
   double sell_pct = (total_delta > 0) ? (sell_v / total_delta) * 100.0 : 50.0;

   string winner_str = "";
   color  winner_clr = clrWhite;
   string target_str = "";

   if(current_price < today_val)
   {
      winner_str = "VENDEDORES (Imbalance Bajista)";
      winner_clr = clrRed;
      target_str = StringFormat("Rechazo->POC %.1f | Put1 %.1f", today_poc, g_put1);
   }
   else if(current_price > today_vah)
   {
      winner_str = "COMPRADORES (Imbalance Alcista)";
      winner_clr = clrLime;
      target_str = StringFormat("Alcista->Call1 %.1f | VAH %.1f", g_call1, today_vah);
   }
   else if(current_price >= today_poc)
   {
      winner_str = "COMPRADORES (Sobre POC)";
      winner_clr = clrSpringGreen;
      target_str = StringFormat("Obj: VAH %.1f | VWAP %.1f", today_vah, vwap_today);
   }
   else
   {
      winner_str = "VENDEDORES (Bajo POC)";
      winner_clr = clrOrangeRed;
      target_str = StringFormat("Obj: VAL %.1f | VWAP %.1f", today_val, vwap_today);
   }

   // H. HUD Compacto (adaptado para ventanas multiples)
   if(InpShowHUD)
   {
      int hx = InpHudX, hy = InpHudY, hw = 250, hh = 215;
      DrawRectLabel("HUD_BG", hx, hy, hw, hh, InpHudBg);

      DrawLabelText("H_Title", hx + 8, hy + 6,  _Symbol + " | VP + VWAP + CME OI", clrCyan, 8, true);

      DrawLabelText("H_Poc",   hx + 8, hy + 24, "POC Hoy: " + DoubleToString(today_poc, _Digits) + " | Ayer: " + DoubleToString(y_poc, _Digits), InpColorPOC, 8, true);
      DrawLabelText("H_Vwap",  hx + 8, hy + 40, "VWAP Hoy: " + DoubleToString(vwap_today, _Digits) + " | Ayer: " + DoubleToString(vwap_yest, _Digits), InpColorVWAPToday, 8, true);
      DrawLabelText("H_VA",    hx + 8, hy + 56, "VAH: " + DoubleToString(today_vah, _Digits) + " | VAL: " + DoubleToString(today_val, _Digits), InpColorVAH_VAL, 8);

      DrawLabelText("H_OiT",   hx + 8, hy + 76, "CME OI (" + g_oi_exp + "):", clrGold, 8, true);
      DrawLabelText("H_OiC",   hx + 8, hy + 92, "Call1: " + DoubleToString(g_call1, _Digits) + " | Call2: " + DoubleToString(g_call2, _Digits), InpColorCallWall, 8);
      DrawLabelText("H_OiP",   hx + 8, hy + 108,"Put1:  " + DoubleToString(g_put1, _Digits)  + " | Put2:  " + DoubleToString(g_put2, _Digits), InpColorPutWall, 8);

      DrawLabelText("H_Win",   hx + 8, hy + 130, winner_str, winner_clr, 8, true);
      DrawLabelText("H_Delta", hx + 8, hy + 146, StringFormat("Compra %.0f%% | Venta %.0f%%", buy_pct, sell_pct), clrSilver, 8);
      DrawLabelText("H_Proy",  hx + 8, hy + 166, target_str, clrWhite, 8);
      DrawLabelText("H_Vol",   hx + 8, hy + 188, StringFormat("Vol Hoy: %.0f | Ayer: %.0f", today_vol, y_vol), clrLime, 8);
   }

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Helpers de dibujo                                                |
//+------------------------------------------------------------------+
void DrawTextTag(string name, datetime t, double price, string text, color clr)
{
   string obj = g_prefix + name;
   if(ObjectFind(0, obj) < 0)
   {
      ObjectCreate(0, obj, OBJ_TEXT, 0, t, price);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   }
   ObjectSetInteger(0, obj, OBJPROP_TIME, 0, t);
   ObjectSetDouble(0,  obj, OBJPROP_PRICE, 0, price);
   ObjectSetString(0,  obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetString(0,  obj, OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 8);
}

void DrawRayLine(string name, string label, datetime t1, datetime t2, double price, color clr, ENUM_LINE_STYLE style, int width)
{
   string objName = g_prefix + name;
   if(ObjectFind(0, objName) < 0)
   {
      ObjectCreate(0, objName, OBJ_TREND, 0, t1, price, t2, price);
      ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   }
   else
   {
      ObjectSetInteger(0, objName, OBJPROP_TIME, 0, t1);
      ObjectSetDouble(0,  objName, OBJPROP_PRICE, 0, price);
      ObjectSetInteger(0, objName, OBJPROP_TIME, 1, t2);
      ObjectSetDouble(0,  objName, OBJPROP_PRICE, 1, price);
   }
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, objName, OBJPROP_STYLE, style);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, width);

   DrawTextTag(name + "_TXT", t2, price, "  " + label + ": " + DoubleToString(price, _Digits), clr);
}

void DrawSessionLine(string name, string label, datetime t1, datetime t2, double price, color clr)
{
   DrawRayLine(name, label, t1, t2, price, clr, STYLE_DOT, 1);
}

void DrawRectLabel(string name, int x, int y, int w, int h, color bg)
{
   string obj = g_prefix + name;
   if(ObjectFind(0, obj) < 0)
   {
      ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, obj, OBJPROP_COLOR, C'50,55,75');
   }
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);
}

void DrawLabelText(string name, int x, int y, string text, color clr, int font_size = 8, bool bold = false)
{
   string obj = g_prefix + name;
   if(ObjectFind(0, obj) < 0)
   {
      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, obj, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetString(0, obj, OBJPROP_FONT, bold ? "Arial Bold" : "Segoe UI");
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, font_size);
}
//+------------------------------------------------------------------+
