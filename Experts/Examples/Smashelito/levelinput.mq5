//+------------------------------------------------------------------+
//|                                                LevelLogger.mq5   |
//+------------------------------------------------------------------+
#property script_show_inputs

//--- Inputs
input double InpLevel      = 6890.0;  // Price level to check
input int    InpCandleCount = 100;    // Number of candles to check
input string InpFileName    = "LevelLog.txt"; // Output file name

//+------------------------------------------------------------------+
//| Script start function                                            |
//+------------------------------------------------------------------+
void OnStart()
{
   //--- Get starting capital (balance)
   double starting_balance = AccountInfoDouble(ACCOUNT_BALANCE);

   //--- Make sure we have enough bars
   if(Bars(_Symbol, _Period) < InpCandleCount)
   {
      Print("Not enough candles available.");
      return;
   }

   int count = 0;

   //--- Loop through candles (skip current forming candle, start from index 1)
   for(int i = 1; i <= InpCandleCount; i++)
   {
      double high = iHigh(_Symbol, _Period, i);
      double low  = iLow(_Symbol, _Period, i);

      //--- Check if candle touched level
      if(low <= InpLevel && high >= InpLevel)
         count++;
   }

   //--- Open file for writing
   int file_handle = FileOpen(InpFileName, FILE_WRITE | FILE_TXT);

   if(file_handle == INVALID_HANDLE)
   {
      Print("Failed to open file. Error: ", GetLastError());
      return;
   }

   //--- Write data
   FileWrite(file_handle, "Symbol: ", _Symbol);
   FileWrite(file_handle, "Timeframe: ", EnumToString(_Period));
   FileWrite(file_handle, "Starting Balance: ", DoubleToString(starting_balance,2));
   FileWrite(file_handle, "Checked Candles: ", InpCandleCount);
   FileWrite(file_handle, "Level: ", DoubleToString(InpLevel,_Digits));
   FileWrite(file_handle, "Candles touching level: ", count);
   FileWrite(file_handle, "Time: ", TimeToString(TimeCurrent()));

   FileClose(file_handle);

   Print("Done. File saved to MQL5\\Files\\", InpFileName);
}
//+------------------------------------------------------------------+