//+------------------------------------------------------------------+
//|                                              GEX_Update_Data.mq5 |
//|   Descarga los niveles GEX / Gamma Flip de SPX a MQL5\Files      |
//+------------------------------------------------------------------+
#property copyright "Antigravity Quant Tools"
#property version   "1.00"
#property script_show_inputs

input string InpJsonUrl      = "https://raw.githubusercontent.com/dhawalc/spx-gamma-levels/main/data/latest.json";
input string InpJsonFileName = "gex_latest.json";

void OnStart()
{
   char post[];
   char result[];
   string resHeaders = "";
   ResetLastError();

   int code = WebRequest("GET", InpJsonUrl, "", 5000, post, result, resHeaders);
   if(code == 200)
   {
      int handle = FileOpen(InpJsonFileName, FILE_WRITE | FILE_BIN);
      if(handle != INVALID_HANDLE)
      {
         FileWriteArray(handle, result);
         FileClose(handle);
         Print("GEX_Update_Data: Niveles actualizados correctamente en MQL5\\Files\\", InpJsonFileName);
         Alert("Niveles GEX actualizados correctamente.");
      }
      else
      {
         Print("GEX_Update_Data: Error abriendo archivo para escribir. Err=", GetLastError());
      }
   }
   else
   {
      int err = GetLastError();
      if(err == 4014)
         Alert("Permite https://raw.githubusercontent.com en Herramientas > Opciones > Asesores Expertos > WebRequest");
      else
         Alert(StringFormat("Error descargando GEX: HTTP %d (Err %d)", code, err));
   }
}
//+------------------------------------------------------------------+
