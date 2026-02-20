//+------------------------------------------------------------------+
//| VISUAL DEBUGGING FUNCTIONS                                        |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Draw Horizontal Line on Chart                                     |
//+------------------------------------------------------------------+
void DrawTradeLine(string name, double price, color lineColor, int width = 1, int style = STYLE_SOLID)
{
   string objName = name;
   
   // Delete existing line if it exists
   if(ObjectFind(0, objName) >= 0)
      ObjectDelete(0, objName);
   
   if(price <= 0) return; // Don't draw invalid prices
   
   // Create new horizontal line
   if(ObjectCreate(0, objName, OBJ_HLINE, 0, 0, price))
   {
      ObjectSetInteger(0, objName, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, objName, OBJPROP_STYLE, style);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, objName, OBJPROP_BACK, false);
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, objName, OBJPROP_SELECTED, false);
      ObjectSetString(0, objName, OBJPROP_TEXT, name);
   }
}

//+------------------------------------------------------------------+
//| Update Visual Levels for All Positions                            |
//+------------------------------------------------------------------+
void UpdateAllPositionVisuals()
{
   if(!InpEnableVisualLevels) return;
   
   CPositionInfo pos;
   
   // First, delete all old lines to prevent orphans
   DeleteAllTradeLines();
   
   // Draw lines for each position
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Symbol() != _Symbol) continue;
      if(pos.Magic() != InpMagicNumber) continue;
      
      ulong ticket = pos.Ticket();
      double entry = pos.PriceOpen();
      double currentSL = pos.StopLoss();
      double currentTP = pos.TakeProfit();
      
      bool isBuy = (pos.Type() == POSITION_TYPE_BUY);
      
      string ticketStr = IntegerToString(ticket);
      string prefix = "SE_" + IntegerToString(InpMagicNumber) + "_";
      
      // Entry Line (Blue)
      DrawTradeLine(prefix + "Entry_" + ticketStr, entry, clrDodgerBlue, 2, STYLE_SOLID);
      
      // Current Stop Loss
      if(currentSL > 0)
      {
         // Check if it's at break-even or trailing
         double distance = MathAbs(entry - currentSL);
         double pointDistance = distance / _Point;
         
         if(pointDistance < 10) // Very close to entry = Break-even
         {
            DrawTradeLine(prefix + "BE_" + ticketStr, currentSL, clrLimeGreen, 2, STYLE_SOLID);
         }
         else
         {
            // Trailing stop (Orange)
            DrawTradeLine(prefix + "Trail_" + ticketStr, currentSL, clrOrange, 2, STYLE_SOLID);
         }
      }
      
      // Take Profit (Purple)
      if(currentTP > 0)
      {
         DrawTradeLine(prefix + "TP_" + ticketStr, currentTP, clrMediumOrchid, 2, STYLE_DASH);
      }
      
      // Calculate and draw initial SL based on ATR (Red dotted line for reference)
      int atrHandle = iATR(_Symbol, PERIOD_CURRENT, 20);
      double atrBuffer[];
      ArraySetAsSeries(atrBuffer, true);
      if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0)
      {
         double atr = atrBuffer[0];
         double initialSL = isBuy ? entry - (atr * 1.5) : entry + (atr * 1.5);
         DrawTradeLine(prefix + "InitSL_" + ticketStr, initialSL, clrRed, 1, STYLE_DOT);
      }
      IndicatorRelease(atrHandle);
   }
}

//+------------------------------------------------------------------+
//| Delete All Visual Objects                                         |
//+------------------------------------------------------------------+
void DeleteAllTradeLines()
{
   string prefix = "SE_" + IntegerToString(InpMagicNumber) + "_";
   int total = ObjectsTotal(0, 0, OBJ_HLINE);
   
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, OBJ_HLINE);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}
