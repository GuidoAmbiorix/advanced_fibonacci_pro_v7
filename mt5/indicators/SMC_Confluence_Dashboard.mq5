//+------------------------------------------------------------------+
//|                                    SMC_Confluence_Dashboard.mq5 |
//|                    SMC Confluence Dashboard Pro - ELITE EDITION  |
//|  OB | FVG | Liquidity | BOS/CHoCH | MTF | KZ | News | Signals  |
//|  Asian Range | Premium/Discount | Swing Labels | Market Stats    |
//|                  NON-REPAINTING - confirmed bars only            |
//|                       Copyright 2026, Infernal Labs            |
//+------------------------------------------------------------------+
#property copyright   "Infernal Labs"
#property link        "https://www.mql5.com"
#property version     "2.00"
#property description "All-in-one SMC Elite: OB, FVG, Liquidity, BOS/CHoCH"
#property description "MTF Bias, Killzones, Asian Range, Premium/Discount"
#property description "NON-REPAINTING Signal Arrows | Score 0-12"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "SMC Buy Signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2

#property indicator_label2  "SMC Sell Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
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

#define OBJ_PFX "SMCD_"

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input group "=== ORDER BLOCKS ==="
input bool            InpShowOB          = true;
input int             InpOBLookback      = 50;
input int             InpOBMaxCount      = 5;
input double          InpOBMinImpulse    = 2.0;
input color           InpOBBullColor     = C'0,100,0';
input color           InpOBBearColor     = C'120,20,20';

input group "=== FAIR VALUE GAPS ==="
input bool            InpShowFVG         = true;
input int             InpFVGLookback     = 50;
input int             InpFVGMaxCount     = 10;
input double          InpFVGMinSize      = 0.5;
input color           InpFVGBullColor    = C'0,60,120';
input color           InpFVGBearColor    = C'120,40,0';
input bool            InpShowCELevel     = true;

input group "=== LIQUIDITY LEVELS ==="
input bool            InpShowLiquidity   = true;
input int             InpLiqLookback     = 20;
input color           InpPDHColor        = clrDarkOrange;
input color           InpPDLColor        = clrDodgerBlue;
input color           InpSwingColor      = C'80,80,80';
input bool            InpShowSwept       = false;

input group "=== STRUCTURE BOS/CHoCH ==="
input bool            InpShowStructure   = true;
input int             InpStructLookback  = 20;
input color           InpBOSBullColor    = clrMediumSeaGreen;
input color           InpBOSBearColor    = clrIndianRed;
input color           InpCHoCHBullColor  = clrLime;
input color           InpCHoCHBearColor  = clrRed;

input group "=== KILLZONES ==="
input bool            InpShowKillzones   = true;
input int             InpBrokerUTCOffset = 0;
input bool            InpKZAsian         = true;
input bool            InpKZLondon        = true;
input bool            InpKZNY            = true;
input bool            InpKZLondonClose   = false;
input color           InpKZAsianColor    = C'0,0,40';
input color           InpKZLondonColor   = C'0,30,0';
input color           InpKZNYColor       = C'40,0,0';

input group "=== MULTI-TIMEFRAME ==="
input ENUM_TIMEFRAMES InpHTF             = PERIOD_H4;
input ENUM_TIMEFRAMES InpMTF_TF          = PERIOD_H1;
input ENUM_TIMEFRAMES InpLTF             = PERIOD_M15;
input int             InpEMAPeriod       = 50;
input int             InpRSIPeriod       = 14;

input group "=== NEWS FILTER ==="
input bool            InpShowNews        = true;
input int             InpNewsBefore      = 30;
input int             InpNewsAfter       = 30;

input group "=== ALERTS ==="
input bool            InpAlertOnSignal   = true;
input double          InpAlertMinScore   = 7.0;
input bool            InpPushAlert       = false;
input bool            InpEmailAlert      = false;

input group "=== DASHBOARD ==="
input bool            InpShowDashboard   = true;
input int             InpDashX           = 20;
input int             InpDashY           = 30;
input int             InpDashFontSize    = 9;

input group "=== SIGNAL ARROWS ==="
input bool            InpShowArrows      = true;
input double          InpArrowMinScore   = 7.0;
input bool            InpArrowNewsFilter = true;
input double          InpRR_TP1          = 1.5;
input double          InpRR_TP2          = 3.0;
input bool            InpShowSLTP        = true;
input color           InpSLColor         = clrOrangeRed;
input color           InpTP1Color        = C'0,160,0';
input color           InpTP2Color        = clrLimeGreen;

input group "=== ASIAN RANGE ==="
input bool            InpShowAsianRange  = true;
input color           InpAsianRangeColor = C'80,80,180';
input bool            InpShowAsianMid    = true;

input group "=== PREMIUM/DISCOUNT ==="
input bool            InpShowPDZones     = true;
input color           InpPremiumColor    = C'80,0,0';
input color           InpDiscountColor   = C'0,80,0';
input color           InpEquilColor      = C'60,60,60';

input group "=== SWING LABELS ==="
input bool            InpShowSwingLabels = true;
input int             InpSwingLookback   = 30;
input color           InpSwingHColor     = C'180,180,100';
input color           InpSwingLColor     = C'100,180,180';

//+------------------------------------------------------------------+
//| MODULE INSTANCES                                                  |
//+------------------------------------------------------------------+
CSMCOrderBlocks    g_ob;
CSMCFairValueGap   g_fvg;
CSMCLiquiditySweep g_liq;
CSMCStructureBreak g_struct;
CMTFConfluence     g_mtf;
CNewsFilter        g_news;

//+------------------------------------------------------------------+
//| INDICATOR BUFFERS                                                 |
//+------------------------------------------------------------------+
double g_buyBuf[];
double g_sellBuf[];

//+------------------------------------------------------------------+
//| SIGNAL TRACKING GLOBALS                                          |
//+------------------------------------------------------------------+
datetime g_lastAlertTime  = 0;
double   g_lastScore      = 0;
int      g_lastDir        = 0;
datetime g_lastSignalTime = 0;
double   g_lastSL         = 0;
double   g_lastTP1        = 0;
double   g_lastTP2        = 0;
int      g_lastSigDir     = 0;
double   g_lastSigScore   = 0;
int      g_sigCountBuy    = 0;
int      g_sigCountSell   = 0;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set up indicator buffers
   SetIndexBuffer(0, g_buyBuf,  INDICATOR_DATA);
   SetIndexBuffer(1, g_sellBuf, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetDouble (0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble (1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, -10);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT,  10);

   ArraySetAsSeries(g_buyBuf,  true);
   ArraySetAsSeries(g_sellBuf, true);

   if(!g_ob.Init(_Symbol, _Period, InpOBLookback, InpOBMaxCount, InpOBMinImpulse))
      return INIT_FAILED;
   if(!g_fvg.Init(_Symbol, _Period, InpFVGLookback, InpFVGMaxCount, InpFVGMinSize))
      return INIT_FAILED;
   if(!g_liq.Init(_Symbol, _Period, InpLiqLookback))
      return INIT_FAILED;
   if(!g_struct.Init(_Symbol, _Period, InpStructLookback))
      return INIT_FAILED;
   if(!g_mtf.Init(_Symbol, InpHTF, InpMTF_TF, InpLTF, InpEMAPeriod, InpRSIPeriod))
      return INIT_FAILED;
   g_news.Init(_Symbol, InpNewsBefore, InpNewsAfter, true);

   EventSetTimer(5);
   DeleteAllObjects();
   Print("[SMCD] Elite Edition initialized on ", _Symbol, " ", EnumToString(_Period));
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
   g_struct.Deinit();
   g_mtf.Deinit();
   DeleteAllObjects();
}

//+------------------------------------------------------------------+
//| OnCalculate - NON-REPAINTING                                     |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
{
   if(rates_total < 10) return 0;

   // Module updates
   g_ob.Update();
   g_fvg.Update();
   g_liq.Update();
   g_struct.Update();
   g_mtf.Update();
   g_news.Update();

   // Chart drawings
   DrawKillzones();
   DrawLiquidity();
   DrawOrderBlocks();
   DrawFairValueGaps();
   DrawStructure();
   DrawAsianRange();
   DrawPDZones();
   DrawSwingLabels();
   DrawDashboard();

   // NON-REPAINTING signal arrows
   if(InpShowArrows)
   {
      int limit = (prev_calculated <= 0) ? rates_total - 2 : rates_total - prev_calculated;
      limit = MathMin(limit, rates_total - 2);

      for(int i = limit; i >= 1; i--)
      {
         // Do not touch already-processed bars
         if(prev_calculated > 0 && i < prev_calculated - 2) break;

         g_buyBuf[i]  = EMPTY_VALUE;
         g_sellBuf[i] = EMPTY_VALUE;

         // Calculate score & direction for bar i
         int   sigDir   = 0;
         double sigScore = 0;
         CalcBarScore(i, time, open, high, low, close, rates_total, sigDir, sigScore);

         if(sigDir == 0 || sigScore < InpArrowMinScore) continue;

         // News filter check (use current news state — conservative)
         if(InpArrowNewsFilter && !g_news.IsTradingAllowed()) continue;

         // Avoid firing 2 signals on the same bar or consecutive bars
         if(g_lastSignalTime > 0)
         {
            int barsAgo = iBarShift(_Symbol, _Period, g_lastSignalTime, false);
            if(barsAgo >= 0 && barsAgo <= 3) continue;
         }

         // Place arrow
         double entryPrice = (sigDir > 0) ? high[i] : low[i];

         // Compute SL / TP — retrieve ATR via proper handle (bar i, shifted from current)
         double atrVal = _Point * 100; // safe fallback (10 pips)
         {
            int hATRtmp = iATR(_Symbol, _Period, 14);
            if(hATRtmp != INVALID_HANDLE)
            {
               double atrCur[1];
               // CopyBuffer with start_pos = i reads the bar i bars ago
               if(CopyBuffer(hATRtmp, 0, i, 1, atrCur) == 1)
                  atrVal = atrCur[0];
               IndicatorRelease(hATRtmp);
            }
         }

         if(sigDir > 0)
         {
            g_buyBuf[i]  = low[i]  - atrVal * 0.5;
            g_sellBuf[i] = EMPTY_VALUE;
         }
         else
         {
            g_sellBuf[i] = high[i] + atrVal * 0.5;
            g_buyBuf[i]  = EMPTY_VALUE;
         }

         double sl = 0, tp1 = 0, tp2 = 0;
         OrderBlock nearOB;
         if(g_ob.GetNearestOB(sigDir, nearOB))
         {
            sl = (sigDir > 0) ? nearOB.bottom - atrVal * 0.2
                              : nearOB.top    + atrVal * 0.2;
         }
         else
         {
            sl = (sigDir > 0) ? entryPrice - atrVal * 1.5
                              : entryPrice + atrVal * 1.5;
         }

         double risk = MathAbs(entryPrice - sl);
         tp1 = (sigDir > 0) ? entryPrice + risk * InpRR_TP1
                            : entryPrice - risk * InpRR_TP1;
         tp2 = (sigDir > 0) ? entryPrice + risk * InpRR_TP2
                            : entryPrice - risk * InpRR_TP2;

         // Only draw objects for the most recent signal (not historical)
         if(i <= 3)
         {
            g_lastSignalTime = time[i];
            g_lastSL         = sl;
            g_lastTP1        = tp1;
            g_lastTP2        = tp2;
            g_lastSigDir     = sigDir;
            g_lastSigScore   = sigScore;
            if(sigDir > 0) g_sigCountBuy++;
            else           g_sigCountSell++;

            if(InpShowSLTP)
            {
               DrawSLTPLines(time[i], sl, tp1, tp2, entryPrice, sigDir, sigScore);
            }
         }
      }
   }

   if(prev_calculated < rates_total)
      CheckAlerts();

   return rates_total;
}

//+------------------------------------------------------------------+
//| OnTimer                                                          |
//+------------------------------------------------------------------+
void OnTimer()
{
   g_news.Update();
   DrawDashboard();
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Calculate score and direction for a specific bar                 |
//| Uses module data available at call time (current state)          |
//+------------------------------------------------------------------+
void CalcBarScore(int barIdx, const datetime &time[], const double &open[],
                  const double &high[], const double &low[], const double &close[],
                  const int rates_total,
                  int &outDir, double &outScore)
{
   outDir   = 0;
   outScore = 0.0;

   ENUM_HTF_BIAS bias    = g_mtf.GetBias();
   double        align   = g_mtf.GetAlignmentScore();

   int dir = (bias == BIAS_BULLISH || bias == BIAS_STRONG_BULLISH)  ?  1
           : (bias == BIAS_BEARISH || bias == BIAS_STRONG_BEARISH)  ? -1 : 0;

   if(dir == 0) return;

   double sMTF  = ScoreMTF(bias, align);
   double sOB   = g_ob.GetConfluenceScore(dir);
   double sFVG  = g_fvg.GetConfluenceScore(dir);
   double sStr  = g_struct.GetConfluenceScore(dir);
   double sLiq  = g_liq.GetConfluenceScore(dir);
   double sKZ   = ScoreKZ();
   double total = MathMin(sMTF + sOB + sFVG + sStr + sLiq + sKZ, 12.0);

   outDir   = dir;
   outScore = total;
}

//+------------------------------------------------------------------+
//| Draw SL/TP lines and signal label                                |
//+------------------------------------------------------------------+
void DrawSLTPLines(datetime sigTime, double sl, double tp1, double tp2,
                   double entry, int dir, double score)
{
   DeleteByTag("SIG_");

   string dirStr = (dir > 0) ? "BUY" : "SELL";
   // Instrument-aware pip size (same logic as DrawDashboard)
   double pip;
   {
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      if(digits == 5 || digits == 3)
         pip = _Point * 10;
      else
         pip = _Point;
      if(pip <= 0) pip = _Point;
   }

   double slPips  = MathAbs(entry - sl)  / pip;
   double tp1Pips = MathAbs(entry - tp1) / pip;
   double tp2Pips = MathAbs(entry - tp2) / pip;

   // SL line
   string slName = OBJ_PFX + "SIG_SL";
   if(ObjectFind(0, slName) < 0) ObjectCreate(0, slName, OBJ_HLINE, 0, 0, sl);
   ObjectSetDouble (0, slName, OBJPROP_PRICE,       sl);
   ObjectSetInteger(0, slName, OBJPROP_COLOR,       InpSLColor);
   ObjectSetInteger(0, slName, OBJPROP_STYLE,       STYLE_DOT);
   ObjectSetInteger(0, slName, OBJPROP_WIDTH,       1);
   ObjectSetInteger(0, slName, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, slName, OBJPROP_HIDDEN,      true);

   // TP1 line
   string tp1Name = OBJ_PFX + "SIG_TP1";
   if(ObjectFind(0, tp1Name) < 0) ObjectCreate(0, tp1Name, OBJ_HLINE, 0, 0, tp1);
   ObjectSetDouble (0, tp1Name, OBJPROP_PRICE,      tp1);
   ObjectSetInteger(0, tp1Name, OBJPROP_COLOR,      InpTP1Color);
   ObjectSetInteger(0, tp1Name, OBJPROP_STYLE,      STYLE_DASH);
   ObjectSetInteger(0, tp1Name, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, tp1Name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, tp1Name, OBJPROP_HIDDEN,     true);

   // TP2 line
   string tp2Name = OBJ_PFX + "SIG_TP2";
   if(ObjectFind(0, tp2Name) < 0) ObjectCreate(0, tp2Name, OBJ_HLINE, 0, 0, tp2);
   ObjectSetDouble (0, tp2Name, OBJPROP_PRICE,      tp2);
   ObjectSetInteger(0, tp2Name, OBJPROP_COLOR,      InpTP2Color);
   ObjectSetInteger(0, tp2Name, OBJPROP_STYLE,      STYLE_DASH);
   ObjectSetInteger(0, tp2Name, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, tp2Name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, tp2Name, OBJPROP_HIDDEN,     true);

   // Signal label
   string lblName = OBJ_PFX + "SIG_LBL";
   string lblTxt  = StringFormat("%s %.1f  SL:%s  TP1:%s  TP2:%s",
                                 dirStr, score,
                                 DoubleToString(sl,  _Digits),
                                 DoubleToString(tp1, _Digits),
                                 DoubleToString(tp2, _Digits));
   double lblPrice = (dir > 0) ? sl - _Point * 20 : sl + _Point * 20;
   if(ObjectFind(0, lblName) < 0)
      ObjectCreate(0, lblName, OBJ_TEXT, 0, sigTime, lblPrice);
   ObjectSetString (0, lblName, OBJPROP_TEXT,       lblTxt);
   ObjectSetDouble (0, lblName, OBJPROP_PRICE,      lblPrice);
   ObjectSetInteger(0, lblName, OBJPROP_TIME,       sigTime);
   ObjectSetInteger(0, lblName, OBJPROP_COLOR,      (dir > 0) ? clrLime : clrRed);
   ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE,   8);
   ObjectSetString (0, lblName, OBJPROP_FONT,       "Arial");
   ObjectSetInteger(0, lblName, OBJPROP_ANCHOR,     ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, lblName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, lblName, OBJPROP_HIDDEN,     true);

   // SL label
   string slLblName = OBJ_PFX + "SIG_SL_LBL";
   string slLbl     = StringFormat("SL  %.1f pips", slPips);
   if(ObjectFind(0, slLblName) < 0)
      ObjectCreate(0, slLblName, OBJ_TEXT, 0, sigTime, sl);
   ObjectSetString (0, slLblName, OBJPROP_TEXT,       slLbl);
   ObjectSetDouble (0, slLblName, OBJPROP_PRICE,      sl);
   ObjectSetInteger(0, slLblName, OBJPROP_TIME,       sigTime);
   ObjectSetInteger(0, slLblName, OBJPROP_COLOR,      InpSLColor);
   ObjectSetInteger(0, slLblName, OBJPROP_FONTSIZE,   7);
   ObjectSetString (0, slLblName, OBJPROP_FONT,       "Arial");
   ObjectSetInteger(0, slLblName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, slLblName, OBJPROP_HIDDEN,     true);

   // TP1 label
   string tp1LblName = OBJ_PFX + "SIG_TP1_LBL";
   string tp1Lbl     = StringFormat("TP1  +%.1f pips", tp1Pips);
   if(ObjectFind(0, tp1LblName) < 0)
      ObjectCreate(0, tp1LblName, OBJ_TEXT, 0, sigTime, tp1);
   ObjectSetString (0, tp1LblName, OBJPROP_TEXT,       tp1Lbl);
   ObjectSetDouble (0, tp1LblName, OBJPROP_PRICE,      tp1);
   ObjectSetInteger(0, tp1LblName, OBJPROP_TIME,       sigTime);
   ObjectSetInteger(0, tp1LblName, OBJPROP_COLOR,      InpTP1Color);
   ObjectSetInteger(0, tp1LblName, OBJPROP_FONTSIZE,   7);
   ObjectSetString (0, tp1LblName, OBJPROP_FONT,       "Arial");
   ObjectSetInteger(0, tp1LblName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, tp1LblName, OBJPROP_HIDDEN,     true);

   // TP2 label
   string tp2LblName = OBJ_PFX + "SIG_TP2_LBL";
   string tp2Lbl     = StringFormat("TP2  +%.1f pips", tp2Pips);
   if(ObjectFind(0, tp2LblName) < 0)
      ObjectCreate(0, tp2LblName, OBJ_TEXT, 0, sigTime, tp2);
   ObjectSetString (0, tp2LblName, OBJPROP_TEXT,       tp2Lbl);
   ObjectSetDouble (0, tp2LblName, OBJPROP_PRICE,      tp2);
   ObjectSetInteger(0, tp2LblName, OBJPROP_TIME,       sigTime);
   ObjectSetInteger(0, tp2LblName, OBJPROP_COLOR,      InpTP2Color);
   ObjectSetInteger(0, tp2LblName, OBJPROP_FONTSIZE,   7);
   ObjectSetString (0, tp2LblName, OBJPROP_FONT,       "Arial");
   ObjectSetInteger(0, tp2LblName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, tp2LblName, OBJPROP_HIDDEN,     true);
}

//+------------------------------------------------------------------+
//| DRAW: Asian Range Box (today + yesterday)                        |
//+------------------------------------------------------------------+
void DrawAsianRange()
{
   if(!InpShowAsianRange) return;
   DeleteByTag("AR_");

   MqlRates r[];
   int bars = CopyRates(_Symbol, PERIOD_H1, 0, 3 * 24, r);
   if(bars <= 0) return;

   // Find today's and yesterday's Asian sessions
   struct AsianSession
   {
      datetime t1, t2;
      double   hi, lo;
      bool     valid;
   };

   AsianSession sessions[2];
   for(int s = 0; s < 2; s++)
   {
      sessions[s].t1    = 0;
      sessions[s].t2    = 0;
      sessions[s].hi    = -1;
      sessions[s].lo    = 1e10;
      sessions[s].valid = false;
   }

   // Determine day boundary for "today" and "yesterday"
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   datetime todayMidnight = StringToTime(IntegerToString(now.year) + "." +
                                         IntegerToString(now.mon) + "." +
                                         IntegerToString(now.day));
   datetime yestMidnight  = todayMidnight - 86400;

   for(int b = 0; b < bars; b++)
   {
      datetime barUtc = r[b].time - (long)InpBrokerUTCOffset * 3600;
      MqlDateTime bd;
      TimeToStruct(barUtc, bd);
      int est = (bd.hour - 5 + 24) % 24;

      bool isAsian = (est >= 20 || est < 1);
      if(!isAsian) continue;

      // Which session: today or yesterday?
      // Asian session for "today" starts ~20:00 EST previous calendar day
      datetime barDay = StringToTime(IntegerToString(bd.year) + "." +
                                     IntegerToString(bd.mon)  + "." +
                                     IntegerToString(bd.day));

      int slot = -1;
      if(barDay >= yestMidnight) slot = 0;   // yesterday/today boundary session
      if(barDay >= todayMidnight) slot = 1;  // session after today midnight — but Asian before midnight

      // Simpler: assign slot based on whether the bar is within the last 24h or 24-48h
      long diff = (long)(TimeCurrent() - r[b].time);
      if(diff <= 24 * 3600)       slot = 0; // today's session
      else if(diff <= 48 * 3600)  slot = 1; // yesterday's session
      else continue;

      if(slot < 0 || slot > 1) continue;

      if(sessions[slot].t1 == 0 || r[b].time < sessions[slot].t1)
         sessions[slot].t1 = r[b].time;
      if(r[b].time + 3600 > sessions[slot].t2)
         sessions[slot].t2 = r[b].time + 3600;

      if(r[b].high > sessions[slot].hi) sessions[slot].hi = r[b].high;
      if(r[b].low  < sessions[slot].lo) sessions[slot].lo = r[b].low;
      sessions[slot].valid = true;
   }

   string slotName[2] = {"T", "Y"};
   for(int s = 0; s < 2; s++)
   {
      if(!sessions[s].valid) continue;
      if(sessions[s].hi <= 0 || sessions[s].lo >= 1e9) continue;

      double mid = (sessions[s].hi + sessions[s].lo) / 2.0;
      string pfx = OBJ_PFX + "AR_" + slotName[s];

      // Box rectangle
      string boxName = pfx + "_BOX";
      if(ObjectFind(0, boxName) < 0)
         ObjectCreate(0, boxName, OBJ_RECTANGLE, 0,
                      sessions[s].t1, sessions[s].hi,
                      sessions[s].t2, sessions[s].lo);
      ObjectSetInteger(0, boxName, OBJPROP_TIME,       0, sessions[s].t1);
      ObjectSetDouble (0, boxName, OBJPROP_PRICE,      0, sessions[s].hi);
      ObjectSetInteger(0, boxName, OBJPROP_TIME,       1, sessions[s].t2);
      ObjectSetDouble (0, boxName, OBJPROP_PRICE,      1, sessions[s].lo);
      ObjectSetInteger(0, boxName, OBJPROP_COLOR,      InpAsianRangeColor);
      ObjectSetInteger(0, boxName, OBJPROP_FILL,       true);
      ObjectSetInteger(0, boxName, OBJPROP_BACK,       true);
      ObjectSetInteger(0, boxName, OBJPROP_BGCOLOR,    ColorToARGB(InpAsianRangeColor, 30));
      ObjectSetInteger(0, boxName, OBJPROP_STYLE,      STYLE_SOLID);
      ObjectSetInteger(0, boxName, OBJPROP_WIDTH,      1);
      ObjectSetInteger(0, boxName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, boxName, OBJPROP_HIDDEN,     true);

      // High line
      DrawHLine(pfx + "_HI", sessions[s].hi, InpAsianRangeColor, STYLE_SOLID, 1);

      // Low line
      DrawHLine(pfx + "_LO", sessions[s].lo, InpAsianRangeColor, STYLE_SOLID, 1);

      // Midpoint line
      if(InpShowAsianMid)
      {
         DrawHLine(pfx + "_MID", mid, InpAsianRangeColor, STYLE_DASH, 1);
         DrawChartLabel(pfx + "_MIDL",
                        sessions[s].t2,
                        mid,
                        "Asian Mid " + slotName[s],
                        InpAsianRangeColor, InpDashFontSize - 2);
      }

      // Labels
      DrawChartLabel(pfx + "_HIL", sessions[s].t2, sessions[s].hi,
                     "Asian Hi " + slotName[s],
                     InpAsianRangeColor, InpDashFontSize - 2);
      DrawChartLabel(pfx + "_LOL", sessions[s].t2, sessions[s].lo,
                     "Asian Lo " + slotName[s],
                     InpAsianRangeColor, InpDashFontSize - 2);
   }
}

//+------------------------------------------------------------------+
//| DRAW: Premium / Discount / Equilibrium Zones                    |
//+------------------------------------------------------------------+
void DrawPDZones()
{
   if(!InpShowPDZones) return;
   DeleteByTag("PDZ_");

   double pdh = g_liq.GetPDH();
   double pdl = g_liq.GetPDL();

   if(pdh <= 0 || pdl <= 0 || pdh <= pdl) return;

   double range          = pdh - pdl;
   double premiumLow     = pdh - range * 0.25;   // top 25%
   double discountHigh   = pdl + range * 0.25;   // bottom 25%
   double equilHigh      = (pdh + pdl) / 2.0 + range * 0.05;
   double equilLow       = (pdh + pdl) / 2.0 - range * 0.05;

   datetime t1 = TimeCurrent() - PeriodSeconds(PERIOD_D1);
   datetime t2 = TimeCurrent() + PeriodSeconds(_Period) * 50;

   // Premium zone (top)
   string premName = OBJ_PFX + "PDZ_PREM";
   if(ObjectFind(0, premName) < 0)
      ObjectCreate(0, premName, OBJ_RECTANGLE, 0, t1, pdh, t2, premiumLow);
   ObjectSetInteger(0, premName, OBJPROP_TIME,       0, t1);
   ObjectSetDouble (0, premName, OBJPROP_PRICE,      0, pdh);
   ObjectSetInteger(0, premName, OBJPROP_TIME,       1, t2);
   ObjectSetDouble (0, premName, OBJPROP_PRICE,      1, premiumLow);
   ObjectSetInteger(0, premName, OBJPROP_COLOR,      InpPremiumColor);
   ObjectSetInteger(0, premName, OBJPROP_FILL,       true);
   ObjectSetInteger(0, premName, OBJPROP_BACK,       true);
   ObjectSetInteger(0, premName, OBJPROP_BGCOLOR,    ColorToARGB(InpPremiumColor, 40));
   ObjectSetInteger(0, premName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, premName, OBJPROP_HIDDEN,     true);

   DrawChartLabel(OBJ_PFX + "PDZ_PREML", t2, (pdh + premiumLow) / 2.0,
                  "PREMIUM", InpPremiumColor, InpDashFontSize - 1);

   // Discount zone (bottom)
   string discName = OBJ_PFX + "PDZ_DISC";
   if(ObjectFind(0, discName) < 0)
      ObjectCreate(0, discName, OBJ_RECTANGLE, 0, t1, discountHigh, t2, pdl);
   ObjectSetInteger(0, discName, OBJPROP_TIME,       0, t1);
   ObjectSetDouble (0, discName, OBJPROP_PRICE,      0, discountHigh);
   ObjectSetInteger(0, discName, OBJPROP_TIME,       1, t2);
   ObjectSetDouble (0, discName, OBJPROP_PRICE,      1, pdl);
   ObjectSetInteger(0, discName, OBJPROP_COLOR,      InpDiscountColor);
   ObjectSetInteger(0, discName, OBJPROP_FILL,       true);
   ObjectSetInteger(0, discName, OBJPROP_BACK,       true);
   ObjectSetInteger(0, discName, OBJPROP_BGCOLOR,    ColorToARGB(InpDiscountColor, 40));
   ObjectSetInteger(0, discName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, discName, OBJPROP_HIDDEN,     true);

   DrawChartLabel(OBJ_PFX + "PDZ_DISCL", t2, (discountHigh + pdl) / 2.0,
                  "DISCOUNT", InpDiscountColor, InpDashFontSize - 1);

   // Equilibrium zone (middle)
   string equilName = OBJ_PFX + "PDZ_EQUIL";
   double equilMid  = (pdh + pdl) / 2.0;
   if(ObjectFind(0, equilName) < 0)
      ObjectCreate(0, equilName, OBJ_RECTANGLE, 0, t1, equilHigh, t2, equilLow);
   ObjectSetInteger(0, equilName, OBJPROP_TIME,       0, t1);
   ObjectSetDouble (0, equilName, OBJPROP_PRICE,      0, equilHigh);
   ObjectSetInteger(0, equilName, OBJPROP_TIME,       1, t2);
   ObjectSetDouble (0, equilName, OBJPROP_PRICE,      1, equilLow);
   ObjectSetInteger(0, equilName, OBJPROP_COLOR,      InpEquilColor);
   ObjectSetInteger(0, equilName, OBJPROP_FILL,       true);
   ObjectSetInteger(0, equilName, OBJPROP_BACK,       true);
   ObjectSetInteger(0, equilName, OBJPROP_BGCOLOR,    ColorToARGB(InpEquilColor, 35));
   ObjectSetInteger(0, equilName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, equilName, OBJPROP_HIDDEN,     true);

   DrawChartLabel(OBJ_PFX + "PDZ_EQUILL", t2, equilMid,
                  "EQUILIBRIUM (50%)", InpEquilColor, InpDashFontSize - 1);

   // Equil midline
   DrawHLine(OBJ_PFX + "PDZ_MID", equilMid, InpEquilColor, STYLE_DASH, 1);
}

//+------------------------------------------------------------------+
//| DRAW: Swing High/Low Labels                                      |
//+------------------------------------------------------------------+
void DrawSwingLabels()
{
   if(!InpShowSwingLabels) return;
   DeleteByTag("SWG_");

   int lookback = MathMin(InpSwingLookback, iBars(_Symbol, _Period) - 5);
   if(lookback < 5) return;

   // Track last 2 swing highs and lows to classify HH/LH/HL/LL
   double swingHi[10];
   double swingLo[10];
   int    swingHiBar[10];
   int    swingLoBar[10];
   int    hiCount = 0, loCount = 0;

   for(int i = 2; i < lookback && (hiCount < 5 || loCount < 5); i++)
   {
      double h = iHigh(_Symbol, _Period, i);
      double l = iLow (_Symbol, _Period, i);

      // Swing high: higher than 2 bars each side
      if(h > iHigh(_Symbol, _Period, i-1) &&
         h > iHigh(_Symbol, _Period, i+1) &&
         h > iHigh(_Symbol, _Period, i-2) &&
         h > iHigh(_Symbol, _Period, i+2) &&
         hiCount < 5)
      {
         swingHi[hiCount]    = h;
         swingHiBar[hiCount] = i;
         hiCount++;
      }

      // Swing low
      if(l < iLow(_Symbol, _Period, i-1) &&
         l < iLow(_Symbol, _Period, i+1) &&
         l < iLow(_Symbol, _Period, i-2) &&
         l < iLow(_Symbol, _Period, i+2) &&
         loCount < 5)
      {
         swingLo[loCount]    = l;
         swingLoBar[loCount] = i;
         loCount++;
      }
   }

   // Draw swing high labels (index 0 = most recent)
   for(int i = 0; i < hiCount; i++)
   {
      string lbl = "SH";
      if(i < hiCount - 1)
      {
         lbl = (swingHi[i] > swingHi[i+1]) ? "HH" : "LH";
      }

      datetime t = iTime(_Symbol, _Period, swingHiBar[i]);
      double   p = swingHi[i] + iATR(_Symbol, _Period, 14) * 0.3;

      string name = OBJ_PFX + "SWG_H_" + IntegerToString(i);
      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
      ObjectSetString (0, name, OBJPROP_TEXT,       lbl);
      ObjectSetDouble (0, name, OBJPROP_PRICE,      p);
      ObjectSetInteger(0, name, OBJPROP_TIME,       t);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      InpSwingHColor);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   InpDashFontSize - 2);
      ObjectSetString (0, name, OBJPROP_FONT,       "Arial Bold");
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,     ANCHOR_CENTER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   }

   // Draw swing low labels
   for(int i = 0; i < loCount; i++)
   {
      string lbl = "SL_";
      if(i < loCount - 1)
      {
         lbl = (swingLo[i] < swingLo[i+1]) ? "LL" : "HL";
      }

      datetime t = iTime(_Symbol, _Period, swingLoBar[i]);
      double   p = swingLo[i] - iATR(_Symbol, _Period, 14) * 0.3;

      string name = OBJ_PFX + "SWG_L_" + IntegerToString(i);
      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
      ObjectSetString (0, name, OBJPROP_TEXT,       lbl);
      ObjectSetDouble (0, name, OBJPROP_PRICE,      p);
      ObjectSetInteger(0, name, OBJPROP_TIME,       t);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      InpSwingLColor);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   InpDashFontSize - 2);
      ObjectSetString (0, name, OBJPROP_FONT,       "Arial Bold");
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,     ANCHOR_CENTER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   }
}

//+------------------------------------------------------------------+
//| DRAW: Order Blocks                                               |
//+------------------------------------------------------------------+
void DrawOrderBlocks()
{
   if(!InpShowOB) return;
   DeleteByTag("OB_");

   OrderBlock obs[];

   // Bullish
   int n = g_ob.GetStrongestOBs(1, obs, InpOBMaxCount);
   for(int i = 0; i < n; i++)
   {
      datetime t2 = TimeCurrent() + PeriodSeconds(_Period) * 15;
      DrawZone(OBJ_PFX + "OB_B_" + IntegerToString(i),
               obs[i].time, obs[i].top, t2, obs[i].bottom,
               InpOBBullColor, 204);
      DrawChartLabel(OBJ_PFX + "OB_BL_" + IntegerToString(i),
                     t2, obs[i].midline,
                     "OB [" + IntegerToString((int)obs[i].strengthScore) + "]",
                     InpOBBullColor, InpDashFontSize - 1);
   }

   // Bearish
   n = g_ob.GetStrongestOBs(-1, obs, InpOBMaxCount);
   for(int i = 0; i < n; i++)
   {
      datetime t2 = TimeCurrent() + PeriodSeconds(_Period) * 15;
      DrawZone(OBJ_PFX + "OB_S_" + IntegerToString(i),
               obs[i].time, obs[i].top, t2, obs[i].bottom,
               InpOBBearColor, 204);
      DrawChartLabel(OBJ_PFX + "OB_SL_" + IntegerToString(i),
                     t2, obs[i].midline,
                     "OB [" + IntegerToString((int)obs[i].strengthScore) + "]",
                     InpOBBearColor, InpDashFontSize - 1);
   }
}

//+------------------------------------------------------------------+
//| DRAW: Fair Value Gaps (nearest per side)                         |
//+------------------------------------------------------------------+
void DrawFairValueGaps()
{
   if(!InpShowFVG) return;
   DeleteByTag("FVG_");

   FairValueGap fvg;
   datetime t2 = TimeCurrent() + PeriodSeconds(_Period) * 15;

   if(g_fvg.GetNearestFVG(1, fvg) && fvg.status != FVG_FILLED)
   {
      DrawZone(OBJ_PFX + "FVG_B",  fvg.time, fvg.top, t2, fvg.bottom, InpFVGBullColor, 180);
      if(InpShowCELevel)
         DrawHLine(OBJ_PFX + "FVG_CE_B", fvg.midline, InpFVGBullColor, STYLE_DASH, 1);
      DrawChartLabel(OBJ_PFX + "FVG_BL", t2, fvg.midline,
                     "FVG " + IntegerToString((int)fvg.fillPercent) + "% fill",
                     InpFVGBullColor, InpDashFontSize - 1);
   }

   if(g_fvg.GetNearestFVG(-1, fvg) && fvg.status != FVG_FILLED)
   {
      DrawZone(OBJ_PFX + "FVG_S",  fvg.time, fvg.top, t2, fvg.bottom, InpFVGBearColor, 180);
      if(InpShowCELevel)
         DrawHLine(OBJ_PFX + "FVG_CE_S", fvg.midline, InpFVGBearColor, STYLE_DASH, 1);
      DrawChartLabel(OBJ_PFX + "FVG_SL", t2, fvg.midline,
                     "FVG " + IntegerToString((int)fvg.fillPercent) + "% fill",
                     InpFVGBearColor, InpDashFontSize - 1);
   }
}

//+------------------------------------------------------------------+
//| DRAW: Liquidity Levels (PDH/PDL/PWH/PWL + nearest swing)        |
//+------------------------------------------------------------------+
void DrawLiquidity()
{
   if(!InpShowLiquidity) return;
   DeleteByTag("LIQ_");

   struct LvlDef { double price; string label; color col; int width; };
   LvlDef fixed[];
   ArrayResize(fixed, 4);
   fixed[0].price = g_liq.GetPDH(); fixed[0].label = "PDH"; fixed[0].col = InpPDHColor; fixed[0].width = 2;
   fixed[1].price = g_liq.GetPDL(); fixed[1].label = "PDL"; fixed[1].col = InpPDLColor; fixed[1].width = 2;
   fixed[2].price = g_liq.GetPWH(); fixed[2].label = "PWH"; fixed[2].col = InpPDHColor; fixed[2].width = 1;
   fixed[3].price = g_liq.GetPWL(); fixed[3].label = "PWL"; fixed[3].col = InpPDLColor; fixed[3].width = 1;

   for(int i = 0; i < 4; i++)
   {
      if(fixed[i].price <= 0) continue;
      string name = OBJ_PFX + "LIQ_" + fixed[i].label;
      DrawHLine(name, fixed[i].price, fixed[i].col, STYLE_DASH, fixed[i].width);
      DrawChartLabel(name + "_L",
                     TimeCurrent() + PeriodSeconds(_Period) * 3,
                     fixed[i].price, fixed[i].label, fixed[i].col, InpDashFontSize - 2);
   }

   double nearPrice; ENUM_LIQUIDITY_TYPE nearType;
   if(g_liq.GetNearestLevel(1, nearPrice, nearType))
   {
      string tag = LiqTypeToString(nearType);
      DrawHLine(OBJ_PFX + "LIQ_SW_H", nearPrice, InpSwingColor, STYLE_DOT, 1);
      DrawChartLabel(OBJ_PFX + "LIQ_SW_HL",
                     TimeCurrent() + PeriodSeconds(_Period) * 3,
                     nearPrice, tag, InpSwingColor, InpDashFontSize - 2);
   }
   if(g_liq.GetNearestLevel(-1, nearPrice, nearType))
   {
      string tag = LiqTypeToString(nearType);
      DrawHLine(OBJ_PFX + "LIQ_SW_L", nearPrice, InpSwingColor, STYLE_DOT, 1);
      DrawChartLabel(OBJ_PFX + "LIQ_SW_LL",
                     TimeCurrent() + PeriodSeconds(_Period) * 3,
                     nearPrice, tag, InpSwingColor, InpDashFontSize - 2);
   }
}

//+------------------------------------------------------------------+
//| DRAW: BOS / CHoCH                                               |
//+------------------------------------------------------------------+
void DrawStructure()
{
   if(!InpShowStructure) return;
   DeleteByTag("STR_");

   ENUM_STRUCTURE_TYPE st    = g_struct.GetLastBreakType();
   double              price = g_struct.GetLastBreakPrice();
   datetime            btime = g_struct.GetLastBreakTime();
   if(st == STRUCT_NONE || btime == 0) return;

   bool isBull  = (st == STRUCT_BOS_BULLISH  || st == STRUCT_CHOCH_BULLISH);
   bool isCHoCH = (st == STRUCT_CHOCH_BULLISH || st == STRUCT_CHOCH_BEARISH);

   color  col = isCHoCH ? (isBull ? InpCHoCHBullColor : InpCHoCHBearColor)
                        : (isBull ? InpBOSBullColor    : InpBOSBearColor);
   string lbl = isCHoCH ? (isBull ? "CHoCH+" : "CHoCH-")
                        : (isBull ? "BOS+"   : "BOS-");

   DrawHLine(OBJ_PFX + "STR_LINE", price, col, STYLE_DASH, isCHoCH ? 2 : 1);
   DrawChartLabel(OBJ_PFX + "STR_LBL", btime, price, lbl, col, InpDashFontSize);
}

//+------------------------------------------------------------------+
//| DRAW: Killzone Shading                                           |
//+------------------------------------------------------------------+
void DrawKillzones()
{
   if(!InpShowKillzones) return;
   DeleteByTag("KZ_");

   MqlRates r[];
   int bars = CopyRates(_Symbol, PERIOD_H1, 0, 7 * 24, r);
   if(bars <= 0) return;

   struct KZSession { datetime t1; datetime t2; color col; };
   KZSession sessions[];
   int nSess = 0;

   for(int b = 0; b < bars - 1; b++)
   {
      datetime utc = r[b].time - (long)InpBrokerUTCOffset * 3600;
      MqlDateTime udt; TimeToStruct(utc, udt);
      int est = (udt.hour - 5 + 24) % 24;

      color kzCol = clrNONE;
      if(InpKZAsian      && (est >= 20 || est < 1))     kzCol = InpKZAsianColor;
      else if(InpKZLondon && est >= 2 && est < 5)        kzCol = InpKZLondonColor;
      else if(InpKZNY     && est >= 7 && est < 10)       kzCol = InpKZNYColor;
      else if(InpKZLondonClose && est >= 10 && est < 12) kzCol = C'30,15,0';
      if(kzCol == clrNONE) continue;

      if(nSess > 0 && sessions[nSess-1].col == kzCol &&
         r[b].time <= sessions[nSess-1].t2 + 60)
      {
         sessions[nSess-1].t2 = r[b].time + 3600;
      }
      else
      {
         ArrayResize(sessions, nSess + 1);
         sessions[nSess].t1  = r[b].time;
         sessions[nSess].t2  = r[b].time + 3600;
         sessions[nSess].col = kzCol;
         nSess++;
      }
   }

   double priceMax = ChartGetDouble(0, CHART_PRICE_MAX);
   double priceMin = ChartGetDouble(0, CHART_PRICE_MIN);

   for(int i = 0; i < nSess; i++)
   {
      string name = OBJ_PFX + "KZ_" + IntegerToString(i);
      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_RECTANGLE, 0,
                      sessions[i].t1, priceMax,
                      sessions[i].t2, priceMin);
      ObjectSetInteger(0, name, OBJPROP_TIME,       0, sessions[i].t1);
      ObjectSetDouble (0, name, OBJPROP_PRICE,      0, priceMax);
      ObjectSetInteger(0, name, OBJPROP_TIME,       1, sessions[i].t2);
      ObjectSetDouble (0, name, OBJPROP_PRICE,      1, priceMin);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      sessions[i].col);
      ObjectSetInteger(0, name, OBJPROP_FILL,       true);
      ObjectSetInteger(0, name, OBJPROP_BACK,       true);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      0);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   }
}

//+------------------------------------------------------------------+
//| Block-character bar                                              |
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

string MakeSep(int width = 36)
{
   string s = "  ";
   string ch = ShortToString(0x2550);
   for(int i = 0; i < width; i++) s += ch;
   return s;
}

//+------------------------------------------------------------------+
//| DashPanel: pixel-anchored background rectangle                   |
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

//+------------------------------------------------------------------+
//| DashLabel: left-upper anchored text label                        |
//+------------------------------------------------------------------+
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
//| DRAW: Full Dashboard                                             |
//+------------------------------------------------------------------+
void DrawDashboard()
{
   if(!InpShowDashboard) return;

   // ── Gather data ───────────────────────────────────────────────
   ENUM_HTF_BIAS bias     = g_mtf.GetBias();
   double        alignment = g_mtf.GetAlignmentScore();
   int           dir       = (bias == BIAS_BULLISH || bias == BIAS_STRONG_BULLISH)  ?  1
                           : (bias == BIAS_BEARISH || bias == BIAS_STRONG_BEARISH)  ? -1 : 0;

   double sMTF  = ScoreMTF(bias, alignment);
   double sOB   = g_ob.GetConfluenceScore(dir);
   double sFVG  = g_fvg.GetConfluenceScore(dir);
   double sStr  = g_struct.GetConfluenceScore(dir);
   double sLiq  = g_liq.GetConfluenceScore(dir);
   double sKZ   = ScoreKZ();
   double total = MathMin(sMTF + sOB + sFVG + sStr + sLiq + sKZ, 12.0);

   g_lastScore = total;
   g_lastDir   = dir;

   // News
   bool   newsBlocked = InpShowNews && !g_news.IsTradingAllowed();
   string newsLine    = newsBlocked ? "BLOCKED: " + g_news.GetCurrentEventName() : "Clear";
   int    minsNext    = g_news.GetMinutesToNextNews();
   if(!newsBlocked && minsNext >= 0 && minsNext < 180)
      newsLine = "Clear  next " + IntegerToString(minsNext / 60) + "h " +
                 IntegerToString(minsNext % 60) + "m";

   // HTF / MTF
   TimeframeAnalysis htf  = g_mtf.GetHTFAnalysis();
   TimeframeAnalysis mtfA = g_mtf.GetMTFAnalysis();

   // OB
   OrderBlock nearOB;
   string obLine = "None";
   color  obCol  = C'90,90,90';
   if(g_ob.GetNearestOB(dir, nearOB))
   {
      obLine = StringFormat("str=%d  %dT  age=%dB",
               (int)nearOB.strengthScore, nearOB.touchCount, nearOB.ageInBars);
      obCol  = (nearOB.type == OB_BULLISH) ? clrMediumSeaGreen : clrIndianRed;
   }

   // FVG
   FairValueGap nearFVG;
   string fvgLine = "None";
   color  fvgCol  = C'90,90,90';
   if(g_fvg.GetNearestFVG(dir, nearFVG) && nearFVG.status != FVG_FILLED)
   {
      fvgLine = StringFormat("%s  %d%% fill%s",
               (nearFVG.status == FVG_OPEN) ? "Open" : "Partial",
               (int)nearFVG.fillPercent,
               nearFVG.isOptimal ? " [OPT]" : "");
      fvgCol = (nearFVG.type == FVG_BULLISH) ? clrSteelBlue : clrOrangeRed;
   }

   // Liquidity
   string liqLine = "No sweep";
   color  liqCol  = C'90,90,90';
   if(g_liq.IsSweepAligned(dir))
   {
      liqLine = (dir > 0) ? "Low swept" : "High swept";
      liqCol  = (dir > 0) ? clrMediumSeaGreen : clrIndianRed;
   }

   // Structure
   ENUM_STRUCTURE_TYPE lastBreak = g_struct.GetLastBreakType();
   string strLine = StructStr(lastBreak);
   color  strCol  = (lastBreak == STRUCT_CHOCH_BULLISH || lastBreak == STRUCT_BOS_BULLISH)
                  ? clrMediumSeaGreen
                  : (lastBreak == STRUCT_CHOCH_BEARISH || lastBreak == STRUCT_BOS_BEARISH)
                    ? clrIndianRed : C'90,90,90';

   // ATR / Spread / Daily
   int    hATR14 = iATR(_Symbol, _Period, 14);
   double atrVal = 0;
   if(hATR14 != INVALID_HANDLE)
   {
      double ab[1];
      if(CopyBuffer(hATR14, 0, 1, 1, ab) == 1) atrVal = ab[0];
      IndicatorRelease(hATR14);
   }
   // Pip calculation: detect instrument type to set correct pip size.
   // 5-digit forex (EURUSD): _Point=0.00001, pip=0.0001 (_Point*10)
   // 3-digit JPY pairs (USDJPY): _Point=0.001, pip=0.01 (_Point*10)
   // XAUUSD / metals (4-digit): _Point=0.01, pip=0.01 (same as _Point, not *10)
   // Indices / CFDs: _Point varies; use _Point as pip unit.
   double pip;
   {
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      if(digits == 5 || digits == 3)
         pip = _Point * 10;           // Standard 5-digit forex / 3-digit JPY
      else
         pip = _Point;                // Metals (4-digit), indices, etc.
      if(pip <= 0) pip = _Point;      // Fallback: never allow zero
   }
   double atrPips    = (pip > 0) ? atrVal / pip : 0;
   double spreadPips = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) / 10.0;
   double bid        = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double dHigh      = iHigh(_Symbol, PERIOD_D1, 0);
   double dLow       = iLow (_Symbol, PERIOD_D1, 0);
   double dRange     = (pip > 0) ? (dHigh - dLow) / pip : 0;
   double pdh        = g_liq.GetPDH();
   double pdl        = g_liq.GetPDL();
   double toPDH      = (pdh > 0 && pip > 0) ? (pdh - bid) / pip : 0;
   double toPDL      = (pdl > 0 && pip > 0) ? (bid - pdl) / pip : 0;

   // P/D zone
   string pdZoneStr = "---";
   color  pdZoneCol = C'120,120,130';
   if(pdh > 0 && pdl > 0 && pdh > pdl)
   {
      double rng     = pdh - pdl;
      double premLow = pdh - rng * 0.25;
      double discHi  = pdl + rng * 0.25;
      if(bid >= premLow)  { pdZoneStr = "PREMIUM";     pdZoneCol = C'200,80,80'; }
      else if(bid <= discHi) { pdZoneStr = "DISCOUNT";    pdZoneCol = C'80,200,80'; }
      else                { pdZoneStr = "EQUILIBRIUM"; pdZoneCol = C'120,120,180'; }
   }

   // Signal
   string sigTxt = "WAIT";
   color  sigCol = C'100,100,100';
   color  sigBg  = C'22,22,38';
   if(newsBlocked)                { sigTxt = "NEWS BLACKOUT"; sigCol = clrWhite;       sigBg = C'110,35,0'; }
   else if(dir == 0)              { sigTxt = "NEUTRAL";        sigCol = clrSilver;     sigBg = C'35,35,52'; }
   else if(total >= 9.0 && dir>0) { sigTxt = "STRONG BUY";    sigCol = clrLime;       sigBg = C'0,80,0'; }
   else if(total >= 9.0 && dir<0) { sigTxt = "STRONG SELL";   sigCol = C'255,90,90';  sigBg = C'105,0,0'; }
   else if(total >= 6.5 && dir>0) { sigTxt = "BUY";           sigCol = clrLime;       sigBg = C'0,60,0'; }
   else if(total >= 6.5 && dir<0) { sigTxt = "SELL";          sigCol = clrOrangeRed;  sigBg = C'80,0,0'; }
   else if(total >= 4.5 && dir>0) { sigTxt = "Weak Buy";      sigCol = C'100,210,110'; sigBg = C'12,45,18'; }
   else if(total >= 4.5 && dir<0) { sigTxt = "Weak Sell";     sigCol = C'210,110,100'; sigBg = C'45,12,12'; }

   // ── Layout ────────────────────────────────────────────────────
   int x   = InpDashX;
   int y   = InpDashY;
   int fs  = InpDashFontSize;
   int fsS = MathMax(fs - 1, 7);
   int fsL = fs + 5;
   int lh  = fs + 6;
   int pw  = 310;
   int px  = x + 10;

   color COL_BG      = C'13,13,22';
   color COL_HDR     = C'0,55,88';
   color COL_ACCENT  = C'0,120,180';
   color COL_TBLHDR  = C'28,28,48';
   color COL_ROW_A   = C'18,18,30';
   color COL_ROW_B   = C'23,23,37';

   string dot = ShortToString(0x25CF);   // filled circle ●

   MqlDateTime dtNow; TimeToStruct(TimeCurrent(), dtNow);

   int curY = y;   // pixel Y cursor

   // ── MAIN BG (first = behind everything) ───────────────────────
   DashPanel("BG", x-2, curY-4, pw+4, 900, COL_BG);

   // ── HEADER ────────────────────────────────────────────────────
   DashPanel("HDR", x-2, curY-2, pw+4, 28, COL_HDR);
   DashLabel("H0", px, curY+5, "SMC CONFLUENCE PRO  ELITE", clrWhite, fs, true);
   curY += 28;

   // Sub-header
   DashPanel("SUBBG", x-2, curY, pw+4, lh+2, C'8,8,18');
   DashLabel("H1", px, curY+2,
             _Symbol + "  |  " + EnumToString(_Period) +
             StringFormat("  |  %02d:%02d", dtNow.hour, dtNow.min),
             C'130,190,215', fsS);
   DashLabel("H2", x+pw-68, curY+2,
             "Align " + IntegerToString((int)alignment) + "%",
             C'0,185,215', fsS);
   curY += lh + 4;

   // Accent line
   DashPanel("SEP0", x-2, curY, pw+4, 2, COL_ACCENT);
   curY += 4;

   // ── SCORE ROW ─────────────────────────────────────────────────
   DashPanel("SCBG", x-2, curY, pw+4, lh+2, COL_ROW_A);
   DashLabel("SC0", px, curY+2,
             StringFormat("SCORE   %.1f / 12.0   (%d%%)",
                          total, (int)(total/12.0*100.0)),
             ScoreCol(total), fs, true);
   curY += lh + 4;

   // Real segmented score bar (12 actual rectangles — not block chars)
   {
      int barW   = pw - 20;
      int segs   = 12;
      int gap    = 2;
      int segW   = (barW - (segs-1)*gap) / segs;
      int filled = (int)MathRound(MathMin(total/12.0, 1.0) * segs);
      color scoreC = ScoreCol(total);
      color emptyC = C'35,35,52';
      for(int i = 0; i < segs; i++)
      {
         int sx = px + i*(segW+gap);
         DashPanel("SB" + IntegerToString(i), sx, curY, segW, 10,
                   (i < filled) ? scoreC : emptyC);
      }
      curY += 14;
   }

   // Accent line
   DashPanel("SEP1", x-2, curY, pw+4, 2, COL_ACCENT);
   curY += 2;

   // ── BIG SIGNAL SECTION ────────────────────────────────────────
   DashPanel("SIGBG", x-2, curY, pw+4, 54, sigBg);
   DashLabel("SIG",   px+8, curY+6,  sigTxt, sigCol, fsL, true);
   DashLabel("SIGSC", px+8, curY+36,
             StringFormat("Score: %.1f   Bias: %s", total, BiasStr(bias)),
             sigCol, fsS);
   curY += 56;

   DashPanel("SEP2", x-2, curY, pw+4, 2, COL_ACCENT);
   curY += 4;

   // ── MODULE GRID: 3 columns x 2 rows of colored cells ─────────
   DashPanel("MODHDR", x-2, curY, pw+4, lh, COL_TBLHDR);
   DashLabel("MODH", px, curY+2, "CONFLUENCE MODULES", C'155,155,200', fsS, true);
   curY += lh + 3;

   string modName[6]  = { "MTF Bias", "Ord Block", "Fair Val",
                           "Structure", "Liquidity", "Killzone" };
   double modScore[6] = { sMTF, sOB,  sFVG, sStr, sLiq, sKZ };
   // modMax must match the actual cap from each module's GetConfluenceScore():
   // MTF: ScoreMTF -> base(2.0) + alignment/100(1.0) = 3.0
   // OB:  GetConfluenceScore caps at 1.5
   // FVG: GetConfluenceScore caps at 1.0
   // Struct: GetConfluenceScore caps at 1.5
   // Liq:  GetConfluenceScore caps at 1.5
   // KZ:   ScoreKZ max = 1.0
   double modMax[6]   = { 3.0,  1.5,  1.0,  1.5,  1.5,  1.0 };

   int cellW   = 93;
   int cellH   = 52;
   int cellGap = 4;
   int gridX   = x + 2;

   // Create cell backgrounds FIRST (layering order)
   for(int m = 0; m < 6; m++)
   {
      int col2 = m % 3;
      int row2 = m / 3;
      int cx   = gridX + col2 * (cellW + cellGap);
      int cy   = curY  + row2 * (cellH + cellGap);
      double ratio = (modMax[m] > 0) ? modScore[m] / modMax[m] : 0;
      color cellBg = ratio >= 0.8 ? C'0,42,5'  :
                     ratio >= 0.5 ? C'42,38,0' : C'28,28,45';
      color edgeC  = ratio >= 0.8 ? clrLime    :
                     ratio >= 0.5 ? clrYellow   : C'62,62,88';
      DashPanel("MC_"  + IntegerToString(m), cx,   cy,   cellW, cellH, cellBg);
      DashPanel("MCE_" + IntegerToString(m), cx,   cy,   3,     cellH, edgeC);
   }
   // Create labels on top of cells
   for(int m = 0; m < 6; m++)
   {
      int col2 = m % 3;
      int row2 = m / 3;
      int cx   = gridX + col2 * (cellW + cellGap);
      int cy   = curY  + row2 * (cellH + cellGap);
      double ratio = (modMax[m] > 0) ? modScore[m] / modMax[m] : 0;
      color edgeC  = ratio >= 0.8 ? clrLime : ratio >= 0.5 ? clrYellow : C'62,62,88';
      DashLabel("MN_" + IntegerToString(m), cx+7, cy+5,
                modName[m], C'165,165,195', fsS-1, true);
      DashLabel("MV_" + IntegerToString(m), cx+7, cy+cellH-lh,
                dot + " " + StringFormat("%.1f/%.1f", modScore[m], modMax[m]),
                edgeC, fsS);
   }
   curY += 2*cellH + cellGap + 6;

   DashPanel("SEP3", x-2, curY, pw+4, 2, COL_ACCENT);
   curY += 4;

   // ── SESSION & NEWS ────────────────────────────────────────────
   DashPanel("SESSBG", x-2, curY, pw+4, lh*2+4, COL_ROW_A);
   DashLabel("KZ",   px, curY+2,
             "SESSION  " + KZName(), C'0,200,230', fsS);
   curY += lh + 2;
   DashLabel("NEWS", px, curY,
             "NEWS     " + newsLine,
             newsBlocked ? clrOrangeRed : clrLimeGreen, fsS);
   curY += lh + 4;

   DashPanel("SEP4", x-2, curY, pw+4, 2, COL_ACCENT);
   curY += 4;

   // ── DETAIL ROWS (compact) ─────────────────────────────────────
   DashPanel("D0BG", x-2, curY, pw+4, lh+2, COL_ROW_A);
   DashLabel("D0", px, curY+2,
             StringFormat("HTF RSI:%.1f  %s  |  MTF RSI:%.1f",
                          htf.rsiValue,
                          htf.priceAboveEMA ? "EMA+" : "EMA-",
                          mtfA.rsiValue),
             C'148,148,195', fsS);
   curY += lh + 2;

   DashPanel("D1BG", x-2, curY, pw+4, lh+2, COL_ROW_B);
   DashLabel("D1", px, curY+2,
             StringFormat("ATR:%.1fp  Sprd:%.1fp  Day:%.0fp",
                          atrPips, spreadPips, dRange),
             C'138,198,138', fsS);
   curY += lh + 2;

   DashPanel("D2BG", x-2, curY, pw+4, lh+2, COL_ROW_A);
   DashLabel("D2", px, curY+2, "OB   " + obLine, obCol, fsS);
   curY += lh + 2;

   DashPanel("D3BG", x-2, curY, pw+4, lh+2, COL_ROW_B);
   DashLabel("D3", px, curY+2, "FVG  " + fvgLine, fvgCol, fsS);
   curY += lh + 2;

   DashPanel("D4BG", x-2, curY, pw+4, lh+2, COL_ROW_A);
   DashLabel("D4", px, curY+2,
             StringFormat("LIQ: %s   |   STR: %s", liqLine, strLine),
             liqCol, fsS);
   curY += lh + 2;

   DashPanel("D5BG", x-2, curY, pw+4, lh+2, COL_ROW_B);
   DashLabel("D5", px, curY+2,
             StringFormat("PDH:%s  PDL:%s   Zone:%s",
                          DoubleToString(pdh, _Digits),
                          DoubleToString(pdl, _Digits),
                          pdZoneStr),
             pdZoneCol, fsS);
   curY += lh + 2;

   DashPanel("D6BG", x-2, curY, pw+4, lh+2, COL_ROW_A);
   DashLabel("D6", px, curY+2,
             StringFormat("To PDH: %+.1fp   To PDL: -%+.1fp",
                          toPDH, toPDL),
             C'175,175,128', fsS);
   curY += lh + 4;

   DashPanel("SEP5", x-2, curY, pw+4, 2, COL_ACCENT);
   curY += 4;

   // ── LAST SIGNAL SETUP ─────────────────────────────────────────
   if(g_lastSigDir != 0)
   {
      bool   sigBull  = (g_lastSigDir > 0);
      color  setupBg  = sigBull ? C'0,48,5'   : C'52,0,0';
      color  setupCol = sigBull ? clrLime      : C'255,90,90';

      DashPanel("SETHDR", x-2, curY, pw+4, lh, COL_TBLHDR);
      DashLabel("SETH", px, curY+2, "LAST SIGNAL SETUP", C'195,195,238', fsS, true);
      curY += lh;

      DashPanel("SET0BG", x-2, curY, pw+4, lh+2, setupBg);
      DashLabel("SET0", px, curY+2,
                StringFormat("%s   Score:%.1f   Buy:%d  Sell:%d",
                             sigBull ? "BUY" : "SELL", g_lastSigScore,
                             g_sigCountBuy, g_sigCountSell),
                setupCol, fsS, true);
      curY += lh + 2;

      if(g_lastSL > 0)
      {
         double rp = MathAbs(bid - g_lastSL)  / pip;
         double t1 = (g_lastTP1 > 0) ? MathAbs(g_lastTP1 - bid) / pip : 0;
         double t2 = (g_lastTP2 > 0) ? MathAbs(g_lastTP2 - bid) / pip : 0;
         DashPanel("SET1BG", x-2, curY, pw+4, lh+2, COL_ROW_A);
         DashLabel("SET1", px, curY+2,
                   StringFormat("SL:%s(%.0fp)  TP1:%s(+%.0fp)  TP2:+%.0fp",
                                DoubleToString(g_lastSL, _Digits), rp,
                                DoubleToString(g_lastTP1, _Digits), t1, t2),
                   C'175,175,175', fsS);
         curY += lh + 2;
      }
      DashPanel("SEP6", x-2, curY, pw+4, 2, COL_ACCENT);
      curY += 4;
   }

   // ── FOOTER ────────────────────────────────────────────────────
   DashLabel("FOOT", px, curY+2,
             StringFormat("Updated  %02d:%02d:%02d", dtNow.hour, dtNow.min, dtNow.sec),
             C'52,52,75', fsS-1);
   curY += lh + 6;

   // Resize main background to exact content height
   string bgName = OBJ_PFX + "DASH_BG";
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, curY - y + 8);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| ALERTS                                                           |
//+------------------------------------------------------------------+
void CheckAlerts()
{
   if(!InpAlertOnSignal) return;
   if(g_lastScore < InpAlertMinScore) return;
   if(g_lastDir == 0) return;
   if(InpShowNews && !g_news.IsTradingAllowed()) return;
   if(TimeCurrent() - g_lastAlertTime < PeriodSeconds(_Period)) return;

   string dir = (g_lastDir > 0) ? "BUY" : "SELL";
   string msg = StringFormat("[SMCD] %s %s  Score=%.1f/12  %s",
                             _Symbol, dir, g_lastScore, KZName());
   Alert(msg);
   if(InpPushAlert)  SendNotification(msg);
   if(InpEmailAlert) SendMail("[SMCD] " + _Symbol, msg);
   g_lastAlertTime = TimeCurrent();
   Print(msg);
}

//+------------------------------------------------------------------+
//| SCORE HELPERS                                                    |
//+------------------------------------------------------------------+
double ScoreMTF(ENUM_HTF_BIAS bias, double alignment)
{
   double base = (bias == BIAS_STRONG_BULLISH || bias == BIAS_STRONG_BEARISH) ? 2.0
               : (bias == BIAS_BULLISH        || bias == BIAS_BEARISH)        ? 1.0 : 0.0;
   return base + alignment / 100.0;  // alignment is 0-100, normalise to 0-1
}

double ScoreKZ()
{
   datetime utc = TimeCurrent() - (long)InpBrokerUTCOffset * 3600;
   MqlDateTime d; TimeToStruct(utc, d);
   int est = (d.hour - 5 + 24) % 24;
   if(InpKZLondon && est >= 2 && est < 5)  return 1.0;
   if(InpKZNY     && est >= 7 && est < 10) return 1.0;
   if(InpKZAsian  && (est >= 20 || est < 1)) return 0.5;
   if(InpKZLondonClose && est >= 10 && est < 12) return 0.5;
   return 0.0;
}

//+------------------------------------------------------------------+
//| STRING HELPERS                                                   |
//+------------------------------------------------------------------+
string KZName()
{
   datetime utc = TimeCurrent() - (long)InpBrokerUTCOffset * 3600;
   MqlDateTime d; TimeToStruct(utc, d);
   int est = (d.hour - 5 + 24) % 24;
   if(InpKZAsian  && (est >= 20 || est < 1)) return "Asian KZ";
   if(InpKZLondon && est >= 2 && est < 5)    return "London Open KZ (PRIME)";
   if(InpKZNY     && est >= 7 && est < 10)   return "NY Open KZ (PRIME)";
   if(InpKZLondonClose && est >= 10 && est < 12) return "London Close KZ";
   return "Off-Session";
}

string BiasStr(ENUM_HTF_BIAS b)
{
   switch(b)
   {
      case BIAS_STRONG_BULLISH: return "STRONG BULL";
      case BIAS_BULLISH:        return "Bullish";
      case BIAS_STRONG_BEARISH: return "STRONG BEAR";
      case BIAS_BEARISH:        return "Bearish";
      default:                  return "Neutral";
   }
}

string StructStr(ENUM_STRUCTURE_TYPE st)
{
   switch(st)
   {
      case STRUCT_BOS_BULLISH:   return "BOS Bull";
      case STRUCT_BOS_BEARISH:   return "BOS Bear";
      case STRUCT_CHOCH_BULLISH: return "CHoCH Bull (reversal)";
      case STRUCT_CHOCH_BEARISH: return "CHoCH Bear (reversal)";
      default:                   return "None";
   }
}

string LiqTypeToString(ENUM_LIQUIDITY_TYPE t)
{
   switch(t)
   {
      case LIQ_PDH:         return "PDH";
      case LIQ_PDL:         return "PDL";
      case LIQ_PWH:         return "PWH";
      case LIQ_PWL:         return "PWL";
      case LIQ_EQUAL_HIGHS: return "EQH";
      case LIQ_EQUAL_LOWS:  return "EQL";
      case LIQ_SWING_HIGH:  return "SH";
      case LIQ_SWING_LOW:   return "SL";
      default:              return "LIQ";
   }
}

color ScoreCol(double s)
{
   if(s >= 9.0) return clrLime;
   if(s >= 7.0) return clrYellow;
   if(s >= 5.0) return clrOrange;
   return clrRed;
}

color BiasCol(ENUM_HTF_BIAS b)
{
   switch(b)
   {
      case BIAS_STRONG_BULLISH: return clrLime;
      case BIAS_BULLISH:        return clrMediumSeaGreen;
      case BIAS_STRONG_BEARISH: return clrRed;
      case BIAS_BEARISH:        return clrIndianRed;
      default:                  return clrSilver;
   }
}

//+------------------------------------------------------------------+
//| CHART OBJECT HELPERS                                             |
//+------------------------------------------------------------------+
void DrawZone(string name, datetime t1, double price1,
              datetime t2, double price2, color col, uchar alpha)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, price1, t2, price2);
   ObjectSetInteger(0, name, OBJPROP_TIME,  0, t1);
   ObjectSetDouble (0, name, OBJPROP_PRICE, 0, price1);
   ObjectSetInteger(0, name, OBJPROP_TIME,  1, t2);
   ObjectSetDouble (0, name, OBJPROP_PRICE, 1, price2);
   ObjectSetInteger(0, name, OBJPROP_COLOR,  col);
   ObjectSetInteger(0, name, OBJPROP_FILL,   true);
   ObjectSetInteger(0, name, OBJPROP_BACK,   true);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, ColorToARGB(col, alpha));
   ObjectSetInteger(0, name, OBJPROP_STYLE,  STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,  1);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

void DrawHLine(string name, double price, color col, ENUM_LINE_STYLE style, int width)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble (0, name, OBJPROP_PRICE,      price);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      col);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      width);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

void DrawChartLabel(string name, datetime t, double price,
                    string text, color col, int fontSize)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_TIME,       t);
   ObjectSetDouble (0, name, OBJPROP_PRICE,      price);
   ObjectSetString (0, name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      col);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   fontSize);
   ObjectSetString (0, name, OBJPROP_FONT,       "Arial");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

//+------------------------------------------------------------------+
//| Delete all indicator objects                                     |
//+------------------------------------------------------------------+
void DeleteAllObjects()
{
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, OBJ_PFX) == 0)
         ObjectDelete(0, name);
   }
}

//+------------------------------------------------------------------+
//| Delete objects with a specific sub-tag                           |
//+------------------------------------------------------------------+
void DeleteByTag(string tag)
{
   string fullTag = OBJ_PFX + tag;
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, fullTag) == 0)
         ObjectDelete(0, name);
   }
}
