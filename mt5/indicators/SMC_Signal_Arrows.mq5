//+------------------------------------------------------------------+
//|                                          SMC_Signal_Arrows.mq5  |
//|                SMC Signal Arrows - Non-Repainting                |
//|   BUY/SELL arrows at high-confluence SMC setups (bar 1+ only)   |
//|                   Fase 3 - Commercial SMC Suite                  |
//|                    Copyright 2026, Infernal Labs             |
//+------------------------------------------------------------------+
#property copyright   "Infernal Labs"
#property link        "https://www.mql5.com"
#property version     "1.00"
#property description "Non-repainting SMC signal arrows on confirmed bars only"
#property description "OB + FVG + Liquidity + BOS/CHoCH + MTF confluence"
#property description "Automatic SL/TP levels based on OB zones + ATR"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//--- Plot 0: BUY arrows
#property indicator_label1  "SMC Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- Plot 1: SELL arrows
#property indicator_label2  "SMC Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//+------------------------------------------------------------------+
//| INCLUDES                                                         |
//+------------------------------------------------------------------+
#include "../portafolio_manager/Include/SMC_OrderBlocks.mqh"
#include "../portafolio_manager/Include/SMC_FairValueGap.mqh"
#include "../portafolio_manager/Include/SMC_LiquiditySweep.mqh"
#include "../portafolio_manager/Include/SMC_StructureBreak.mqh"
#include "../portafolio_manager/Include/MTF_Confluence.mqh"
#include "../portafolio_manager/Include/NewsFilter.mqh"

#define OBJ_PFX "SMCSA_"

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input group "=== SIGNAL ==="
input double          InpMinScore     = 7.0;
input double          InpMinScoreStr  = 9.0;
input bool            InpNewsFilter   = true;

input group "=== SL/TP ==="
input double          InpRR_TP1       = 1.5;
input double          InpRR_TP2       = 3.0;
input bool            InpShowSLTP     = true;

input group "=== MULTI-TIMEFRAME ==="
input ENUM_TIMEFRAMES InpHTF          = PERIOD_H4;
input ENUM_TIMEFRAMES InpMTF_TF       = PERIOD_H1;
input ENUM_TIMEFRAMES InpLTF          = PERIOD_M15;
input int             InpOBLookback   = 50;
input int             InpFVGLookback  = 50;
input int             InpLiqLookback  = 20;
input int             InpStructLookback = 20;
input int             InpEMAPeriod    = 50;
input int             InpRSIPeriod    = 14;
input int             InpBrokerUTCOffset = 0;

input group "=== ALERTS ==="
input bool            InpAlert        = true;
input bool            InpPushAlert    = false;
input bool            InpEmailAlert   = false;
input int             InpAlertBar     = 1;

input group "=== DISPLAY ==="
input color           InpBuyColor     = clrLime;
input color           InpSellColor    = clrRed;
input color           InpSLColor      = clrOrangeRed;
input color           InpTP1Color     = C'0,180,0';
input color           InpTP2Color     = clrLimeGreen;
input int             InpFontSize     = 8;

//+------------------------------------------------------------------+
//| MODULE INSTANCES (single symbol = current chart)                 |
//+------------------------------------------------------------------+
CSMCOrderBlocks    g_ob;
CSMCFairValueGap   g_fvg;
CSMCLiquiditySweep g_liq;
CSMCStructureBreak g_str;
CMTFConfluence     g_mtf;
CNewsFilter        g_news;

//+------------------------------------------------------------------+
//| INDICATOR BUFFERS                                                |
//+------------------------------------------------------------------+
double g_buyBuf[];
double g_sellBuf[];

//+------------------------------------------------------------------+
//| STATE                                                            |
//+------------------------------------------------------------------+
datetime g_lastSignalTime = 0;
int      g_buyCount       = 0;
int      g_sellCount      = 0;
double   g_lastScore      = 0.0;
int      g_lastDir        = 0;
datetime g_lastAlertTime  = 0;

// Info panel position (top-right)
int g_panelX = 0;
int g_panelY = 30;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   // Buffer setup
   SetIndexBuffer(0, g_buyBuf,  INDICATOR_DATA);
   SetIndexBuffer(1, g_sellBuf, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);

   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, 0);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, 0);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // Initialize modules
   if(!g_ob.Init(_Symbol, _Period, InpOBLookback, 5, 2.0))
   {
      Print("[SMCSA] ERROR: OB init failed.");
      return INIT_FAILED;
   }
   if(!g_fvg.Init(_Symbol, _Period, InpFVGLookback, 10, 0.5))
   {
      Print("[SMCSA] ERROR: FVG init failed.");
      return INIT_FAILED;
   }
   if(!g_liq.Init(_Symbol, _Period, InpLiqLookback))
   {
      Print("[SMCSA] ERROR: LIQ init failed.");
      return INIT_FAILED;
   }
   if(!g_str.Init(_Symbol, _Period, InpStructLookback))
   {
      Print("[SMCSA] ERROR: STR init failed.");
      return INIT_FAILED;
   }
   if(!g_mtf.Init(_Symbol, InpHTF, InpMTF_TF, InpLTF, InpEMAPeriod, InpRSIPeriod))
   {
      Print("[SMCSA] ERROR: MTF init failed.");
      return INIT_FAILED;
   }
   g_news.Init(_Symbol, 30, 30, true);

   // Pixel position for info panel (top-right corner)
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   g_panelX = MathMax(chartW - 270, 10);
   g_panelY = 30;

   EventSetTimer(1);
   DeleteAllObjects();
   Print("[SMCSA] Initialized on ", _Symbol, " ", EnumToString(_Period));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   g_ob.Deinit();
   g_fvg.Deinit();
   g_liq.Deinit();
   g_str.Deinit();
   g_mtf.Deinit();
   DeleteAllObjects();
}

//+------------------------------------------------------------------+
//| OnCalculate - NON-REPAINTING                                     |
//| Signals placed only on bars 1+ (confirmed bars), never bar 0    |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
{
   if(rates_total < 10) return 0;

   // Update all modules
   g_ob.Update();
   g_fvg.Update();
   g_liq.Update();
   g_str.Update();
   g_mtf.Update();
   g_news.Update();

   // NON-REPAINTING: only process newly confirmed bars
   // startBar is the first bar we need to (re-)evaluate
   int startBar;
   if(prev_calculated <= 0)
      startBar = rates_total - 1;   // first full run: process all history
   else
      startBar = rates_total - prev_calculated; // only new bar(s)

   // Clamp: never process bar 0 (forming), always start from bar 1 minimum
   if(startBar < 1) startBar = 1;

   // CRITICAL: never touch already-processed bars (index < prev_calculated - 1)
   // This guarantees non-repainting: once a bar is computed it is never changed.
   for(int i = startBar; i >= 1; i--)
   {
      // Skip if this bar was already processed in a prior call
      if(prev_calculated > 0 && i < prev_calculated - 1)
         continue;

      // Initialize buffers to EMPTY for this bar if not already set
      // (only on fresh bars; we never reset already-written values)
      if(g_buyBuf[i]  == 0) g_buyBuf[i]  = EMPTY_VALUE;
      if(g_sellBuf[i] == 0) g_sellBuf[i] = EMPTY_VALUE;

      // Calculate score at this confirmed bar
      ENUM_HTF_BIAS bias = g_mtf.GetBias();
      double align       = g_mtf.GetAlignmentScore();
      int dir = (bias == BIAS_BULLISH || bias == BIAS_STRONG_BULLISH) ?  1
              : (bias == BIAS_BEARISH || bias == BIAS_STRONG_BEARISH) ? -1 : 0;

      double sMTF  = ScoreMTF(bias, align);
      double sOB   = g_ob.GetConfluenceScore(dir);
      double sFVG  = g_fvg.GetConfluenceScore(dir);
      double sStr  = g_str.GetConfluenceScore(dir);
      double sLiq  = g_liq.GetConfluenceScore(dir);
      double sKZ   = ScoreKZ();
      double total = MathMin(sMTF + sOB + sFVG + sStr + sLiq + sKZ, 12.0);

      // Update current score state (for the info panel)
      if(i == 1)
      {
         g_lastScore = total;
         g_lastDir   = dir;
      }

      // Skip if score below threshold or direction neutral
      if(total < InpMinScore || dir == 0) continue;

      // Skip if news blackout
      if(InpNewsFilter && !g_news.IsTradingAllowed()) continue;

      // Skip if we already have a signal at this bar time
      if(time[i] == g_lastSignalTime) continue;

      // === PLACE SIGNAL ===
      double entry = close[i];
      double sl    = CalcSL(dir, i, close, low, high);
      if(sl <= 0) continue;  // no valid SL, skip

      double slDist = MathAbs(entry - sl);
      if(slDist < _Point) continue;

      double tp1 = (dir > 0) ? entry + slDist * InpRR_TP1 : entry - slDist * InpRR_TP1;
      double tp2 = (dir > 0) ? entry + slDist * InpRR_TP2 : entry - slDist * InpRR_TP2;

      // Set arrow buffers — NON-REPAINTING: only on bar i (confirmed)
      if(dir > 0)
      {
         g_buyBuf[i]  = low[i]  - 5.0 * _Point;
         g_sellBuf[i] = EMPTY_VALUE;
      }
      else
      {
         g_sellBuf[i] = high[i] + 5.0 * _Point;
         g_buyBuf[i]  = EMPTY_VALUE;
      }

      // Draw SL/TP lines on chart
      if(InpShowSLTP)
      {
         string ts = IntegerToString((long)time[i]);
         DrawHLine(OBJ_PFX + "SL_"  + ts, sl,  InpSLColor,  STYLE_DOT,  1);
         DrawHLine(OBJ_PFX + "TP1_" + ts, tp1, InpTP1Color, STYLE_DASH, 1);
         DrawHLine(OBJ_PFX + "TP2_" + ts, tp2, InpTP2Color, STYLE_DOT,  1);
      }

      // Draw signal label
      string dirStr  = (dir > 0) ? "BUY" : "SELL";
      color  lblCol  = (total >= InpMinScoreStr) ? InpBuyColor : clrMediumSeaGreen;
      if(dir < 0) lblCol = (total >= InpMinScoreStr) ? InpSellColor : clrIndianRed;

      string labelTxt = StringFormat("%s  %.1f/12  SL:%s  TP1:%s  TP2:%s",
                                     dirStr,
                                     total,
                                     DoubleToString(sl,  _Digits),
                                     DoubleToString(tp1, _Digits),
                                     DoubleToString(tp2, _Digits));

      double lblPrice = (dir > 0) ? low[i]  - 12.0 * _Point
                                  : high[i] + 12.0 * _Point;
      DrawChartLabel(OBJ_PFX + "LBL_" + IntegerToString((long)time[i]),
                     time[i], lblPrice, labelTxt, lblCol, InpFontSize - 1);

      // Track signal counts
      if(dir > 0) g_buyCount++;
      else        g_sellCount++;
      g_lastSignalTime = time[i];

      // Fire alert on the bar matching InpAlertBar
      if(InpAlert && i == InpAlertBar)
      {
         if(TimeCurrent() - g_lastAlertTime >= PeriodSeconds(_Period))
         {
            string msg = StringFormat("[SMCSA] %s  %s  Score=%.1f/12  SL=%s  TP1=%s  TP2=%s  %s",
                                      _Symbol, dirStr, total,
                                      DoubleToString(sl, _Digits),
                                      DoubleToString(tp1, _Digits),
                                      DoubleToString(tp2, _Digits),
                                      KZName());
            Alert(msg);
            if(InpPushAlert)  SendNotification(msg);
            if(InpEmailAlert) SendMail("[SMCSA] " + _Symbol + " " + dirStr, msg);
            g_lastAlertTime = TimeCurrent();
            Print(msg);
         }
      }
   }

   // Draw info panel (top-right) using current-bar data
   DrawInfoPanel();

   return rates_total;
}

//+------------------------------------------------------------------+
//| OnTimer - refresh info panel every second                        |
//+------------------------------------------------------------------+
void OnTimer()
{
   g_news.Update();
   g_mtf.Update();
   DrawInfoPanel();
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Calculate Stop Loss level                                        |
//| dir > 0: buy SL below nearest bullish OB or ATR fallback        |
//| dir < 0: sell SL above nearest bearish OB or ATR fallback       |
//+------------------------------------------------------------------+
double CalcSL(int dir, int bar,
              const double &close[], const double &low[], const double &high[])
{
   // Try nearest OB first
   OrderBlock ob;
   if(g_ob.GetNearestOB(dir, ob))
   {
      if(dir > 0 && ob.bottom > 0)
         return ob.bottom - _Point;
      if(dir < 0 && ob.top > 0)
         return ob.top + _Point;
   }

   // Fallback: 1.5 x ATR from bar close
   int hATR = iATR(_Symbol, _Period, 14);
   if(hATR != INVALID_HANDLE)
   {
      double atr[1];
      if(CopyBuffer(hATR, 0, bar, 1, atr) > 0)
      {
         IndicatorRelease(hATR);
         return (dir > 0) ? close[bar] - atr[0] * 1.5
                          : close[bar] + atr[0] * 1.5;
      }
      IndicatorRelease(hATR);
   }

   // Last fallback: swing high/low from recent bars
   if(dir > 0)
   {
      double swingLow = low[bar];
      for(int k = bar; k <= MathMin(bar + 5, ArraySize(low) - 1); k++)
         if(low[k] < swingLow) swingLow = low[k];
      return swingLow - _Point;
   }
   else
   {
      double swingHigh = high[bar];
      for(int k = bar; k <= MathMin(bar + 5, ArraySize(high) - 1); k++)
         if(high[k] > swingHigh) swingHigh = high[k];
      return swingHigh + _Point;
   }
}

//+------------------------------------------------------------------+
//| Info panel - top-right, shows live score + last signal           |
//+------------------------------------------------------------------+
void DrawInfoPanel()
{
   // Refresh panel X in case chart was resized
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   g_panelX = MathMax(chartW - 265, 10);

   color COL_MAIN_BG = C'13,13,22';
   color COL_HEADER  = C'0,55,88';
   color COL_ACCENT  = C'0,120,180';
   color COL_ROW_A   = C'18,18,30';

   int x  = g_panelX;
   int y  = g_panelY;
   int fs = InpFontSize;
   int fsS = MathMax(fs - 1, 7);
   int lh  = fs + 7;
   int pw  = 255;
   int px  = x + 8;

   int row = 0;
   #define IY (y + row * lh)

   // Background
   DashPanel("IP_BG",  x-2, IY-4, pw+4, lh*8+10, COL_MAIN_BG);
   DashPanel("IP_HDR", x-2, IY-2, pw+4, lh+4,    COL_HEADER);

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   DashLabel("IP_H0", px, IY+3, "SMC SIGNAL ARROWS", clrWhite, fs, true);
   row++;

   DashPanel("IP_SEP0", x-2, IY, pw+4, 2, COL_ACCENT);
   row++;

   // Current score
   ENUM_HTF_BIAS bias = g_mtf.GetBias();
   double align       = g_mtf.GetAlignmentScore();
   int dir = (bias == BIAS_BULLISH || bias == BIAS_STRONG_BULLISH) ?  1
           : (bias == BIAS_BEARISH || bias == BIAS_STRONG_BEARISH) ? -1 : 0;
   double sMTF = ScoreMTF(bias, align);
   double sOB  = g_ob.GetConfluenceScore(dir);
   double sFVG = g_fvg.GetConfluenceScore(dir);
   double sStr = g_str.GetConfluenceScore(dir);
   double sLiq = g_liq.GetConfluenceScore(dir);
   double sKZ  = ScoreKZ();
   double live = MathMin(sMTF + sOB + sFVG + sStr + sLiq + sKZ, 12.0);

   DashPanel("IP_R0", x-2, IY, pw+4, lh+2, COL_ROW_A);
   DashLabel("IP_L0", px, IY+2,
             StringFormat("Live:  %.1f / 12.0   %s", live, MakeBar(live, 12.0, 12)),
             ScoreCol(live), fsS);
   row++;

   // Direction
   string dirTxt = (dir > 0) ? "Bias: BULLISH" : (dir < 0) ? "Bias: BEARISH" : "Bias: NEUTRAL";
   color  dirCol = (dir > 0) ? clrLime : (dir < 0) ? clrOrangeRed : clrSilver;
   DashPanel("IP_R1", x-2, IY, pw+4, lh+2, COL_ROW_A);
   DashLabel("IP_L1", px, IY+2, dirTxt, dirCol, fsS, dir != 0);
   row++;

   // Session
   DashPanel("IP_R2", x-2, IY, pw+4, lh+2, COL_ROW_A);
   DashLabel("IP_L2", px, IY+2, "KZ: " + KZName(), C'0,200,230', fsS);
   row++;

   // News status
   bool newsBlocked = InpNewsFilter && !g_news.IsTradingAllowed();
   DashPanel("IP_R3", x-2, IY, pw+4, lh+2, COL_ROW_A);
   DashLabel("IP_L3", px, IY+2,
             "News: " + (newsBlocked ? g_news.GetCurrentEventName() : "Clear"),
             newsBlocked ? clrOrangeRed : clrLimeGreen, fsS);
   row++;

   DashPanel("IP_SEP1", x-2, IY, pw+4, 2, COL_ACCENT);
   row++;

   // Last signal
   string lastSigStr = "Last:  None";
   if(g_lastSignalTime > 0)
   {
      string ldir = (g_lastDir > 0) ? "BUY" : "SELL";
      MqlDateTime ldt; TimeToStruct(g_lastSignalTime, ldt);
      lastSigStr = StringFormat("Last:  %s  %.1f/12  %02d:%02d",
                                ldir, g_lastScore, ldt.hour, ldt.min);
   }
   DashPanel("IP_R4", x-2, IY, pw+4, lh+2, COL_ROW_A);
   DashLabel("IP_L4", px, IY+2, lastSigStr, C'150,150,195', fsS);
   row++;

   // Signal counts
   DashPanel("IP_R5", x-2, IY, pw+4, lh+2, COL_ROW_A);
   DashLabel("IP_L5", px, IY+2,
             StringFormat("Signals:  BUY %d   SELL %d", g_buyCount, g_sellCount),
             C'120,120,160', fsS);
   row++;

   DashPanel("IP_SEP2", x-2, IY, pw+4, 2, COL_ACCENT);
   row++;

   // Footer
   DashPanel("IP_FT", x-2, IY, pw+4, lh+2, COL_ROW_A);
   DashLabel("IP_FOOT", px, IY+2,
             StringFormat("Min: %.1f  Str: %.1f  %02d:%02d:%02d",
                          InpMinScore, InpMinScoreStr, dt.hour, dt.min, dt.sec),
             C'60,60,90', fsS-1);
   row++;

   // Resize background
   int totalH = row * lh + 10;
   string bgName = OBJ_PFX + "DASH_IP_BG";
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, totalH);

   #undef IY
}

//+------------------------------------------------------------------+
//| SCORE HELPERS                                                    |
//+------------------------------------------------------------------+
double ScoreMTF(ENUM_HTF_BIAS bias, double alignment)
{
   double base = (bias == BIAS_STRONG_BULLISH || bias == BIAS_STRONG_BEARISH) ? 2.0
               : (bias == BIAS_BULLISH        || bias == BIAS_BEARISH)        ? 1.0 : 0.0;
   return base + alignment * 1.0;
}

double ScoreKZ()
{
   datetime utc = TimeCurrent() - (long)InpBrokerUTCOffset * 3600;
   MqlDateTime d; TimeToStruct(utc, d);
   int est = (d.hour - 5 + 24) % 24;
   if(est >= 2 && est < 5)   return 1.0;
   if(est >= 7 && est < 10)  return 1.0;
   if(est >= 20 || est < 1)  return 0.5;
   if(est >= 10 && est < 12) return 0.5;
   return 0.0;
}

color ScoreCol(double s)
{
   if(s >= 9.0) return clrLime;
   if(s >= 7.0) return clrYellow;
   if(s >= 5.0) return clrOrange;
   return clrRed;
}

//+------------------------------------------------------------------+
//| STRING HELPERS                                                   |
//+------------------------------------------------------------------+
string KZName()
{
   datetime utc = TimeCurrent() - (long)InpBrokerUTCOffset * 3600;
   MqlDateTime d; TimeToStruct(utc, d);
   int est = (d.hour - 5 + 24) % 24;
   if(est >= 20 || est < 1)  return "Asian KZ";
   if(est >= 2 && est < 5)   return "London Open KZ";
   if(est >= 7 && est < 10)  return "NY Open KZ";
   if(est >= 10 && est < 12) return "London Close KZ";
   return "Off-Session";
}

string SigStructStr(ENUM_STRUCTURE_TYPE st)
{
   switch(st)
   {
      case STRUCT_BOS_BULLISH:   return "BOS+";
      case STRUCT_BOS_BEARISH:   return "BOS-";
      case STRUCT_CHOCH_BULLISH: return "CHoCH+";
      case STRUCT_CHOCH_BEARISH: return "CHoCH-";
      default:                   return "---";
   }
}

//+------------------------------------------------------------------+
//| BLOCK CHARACTER BAR                                              |
//+------------------------------------------------------------------+
string MakeBar(double val, double maxVal, int width = 10)
{
   if(maxVal <= 0) return "";
   int n = (int)MathRound(MathMin(val / maxVal, 1.0) * width);
   string s = "";
   string full  = ShortToString(0x2588);
   string empty = ShortToString(0x2591);
   for(int i = 0; i < width; i++) s += (i < n) ? full : empty;
   return s;
}

//+------------------------------------------------------------------+
//| DASHBOARD PANEL HELPERS                                          |
//+------------------------------------------------------------------+
void DashPanel(string id, int x, int y, int w, int h, color bgCol)
{
   string name = OBJ_PFX + "DASH_" + id;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED,    false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,      true);
      ObjectSetInteger(0, name, OBJPROP_BACK,        false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,     w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,     h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,   bgCol);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     bgCol);
}

void DashLabel(string id, int x, int y,
               string text, color col, int fontSize,
               bool bold = false)
{
   string name = OBJ_PFX + "DASH_" + id;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,     ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     col);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fontSize);
   ObjectSetString (0, name, OBJPROP_FONT,      bold ? "Arial Bold" : "Arial");
}

//+------------------------------------------------------------------+
//| CHART OBJECT HELPERS                                             |
//+------------------------------------------------------------------+
void DrawHLine(string name, double price, color col, ENUM_LINE_STYLE sty, int w)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble (0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_STYLE, sty);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, name, OBJPROP_BACK,  true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

void DrawChartLabel(string name, datetime t, double price,
                    string text, color col, int sz)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_TIME,     t);
   ObjectSetDouble (0, name, OBJPROP_PRICE,    price);
   ObjectSetString (0, name, OBJPROP_TEXT,     text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,    col);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, sz);
   ObjectSetString (0, name, OBJPROP_FONT,     "Arial");
   ObjectSetInteger(0, name, OBJPROP_BACK,     false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

void DrawZone(string name, datetime t1, double price1,
              datetime t2, double price2, color col, uchar alpha)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, price1, t2, price2);
   ObjectSetInteger(0, name, OBJPROP_TIME,  0, t1);
   ObjectSetDouble (0, name, OBJPROP_PRICE, 0, price1);
   ObjectSetInteger(0, name, OBJPROP_TIME,  1, t2);
   ObjectSetDouble (0, name, OBJPROP_PRICE, 1, price2);
   ObjectSetInteger(0, name, OBJPROP_COLOR,   col);
   ObjectSetInteger(0, name, OBJPROP_FILL,    true);
   ObjectSetInteger(0, name, OBJPROP_BACK,    true);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, ColorToARGB(col, alpha));
   ObjectSetInteger(0, name, OBJPROP_STYLE,   STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,   1);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

void DeleteByTag(string tag)
{
   string full = OBJ_PFX + tag;
   for(int i = ObjectsTotal(0, 0) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i, 0);
      if(StringFind(n, full) == 0)
         ObjectDelete(0, n);
   }
}

void DeleteAllObjects()
{
   for(int i = ObjectsTotal(0, 0) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i, 0);
      if(StringFind(n, OBJ_PFX) == 0)
         ObjectDelete(0, n);
   }
}
