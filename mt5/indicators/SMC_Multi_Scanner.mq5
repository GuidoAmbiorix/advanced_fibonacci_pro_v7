//+------------------------------------------------------------------+
//|                                            SMC_Multi_Scanner.mq5 |
//|                     SMC Confluence Multi-Symbol Scanner          |
//|         Scans up to 10 symbols, real-time confluence table       |
//|                   Fase 2 - Commercial SMC Suite                  |
//|                    Copyright 2026, Infernal Labs             |
//+------------------------------------------------------------------+
#property copyright   "Infernal Labs"
#property link        "https://www.mql5.com"
#property version     "1.00"
#property description "Multi-symbol SMC confluence scanner - up to 10 pairs"
#property description "Real-time score table: OB, FVG, Liquidity, BOS/CHoCH, MTF"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//+------------------------------------------------------------------+
//| INCLUDES                                                         |
//+------------------------------------------------------------------+
#include "../portafolio_manager/Include/SMC_OrderBlocks.mqh"
#include "../portafolio_manager/Include/SMC_FairValueGap.mqh"
#include "../portafolio_manager/Include/SMC_LiquiditySweep.mqh"
#include "../portafolio_manager/Include/SMC_StructureBreak.mqh"
#include "../portafolio_manager/Include/MTF_Confluence.mqh"

#define OBJ_PFX "SMCSC_"

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input group "=== SYMBOLS ==="
input string          InpSymbols      = "EURUSD,GBPUSD,XAUUSD,USDJPY,GBPJPY,EURJPY,AUDUSD,USDCAD,USDCHF,NZDUSD";
input ENUM_TIMEFRAMES InpTF           = PERIOD_H1;

input group "=== MULTI-TIMEFRAME ==="
input ENUM_TIMEFRAMES InpHTF          = PERIOD_H4;
input ENUM_TIMEFRAMES InpMTF_TF       = PERIOD_H1;
input ENUM_TIMEFRAMES InpLTF          = PERIOD_M15;
input int             InpEMAPeriod    = 50;
input int             InpRSIPeriod    = 14;

input group "=== KILLZONE ==="
input int             InpBrokerUTCOffset = 0;

input group "=== FILTER ==="
input double          InpMinScore     = 6.5;
input bool            InpSortByScore  = true;
input bool            InpAlertOnNew   = true;
input double          InpAlertScore   = 7.5;

input group "=== DISPLAY ==="
input int             InpDashX        = 10;
input int             InpDashY        = 30;
input int             InpFontSize     = 9;

//+------------------------------------------------------------------+
//| GLOBAL PARALLEL ARRAYS (no structs with class members)           |
//+------------------------------------------------------------------+
string             g_symbols[];
int                g_count = 0;

CSMCOrderBlocks    g_ob[];
CSMCFairValueGap   g_fvg[];
CSMCLiquiditySweep g_liq[];
CSMCStructureBreak g_str[];
CMTFConfluence     g_mtf[];

// Score cache
double g_score[], g_sMTF[], g_sOB[], g_sFVG[], g_sStr[], g_sLiq[], g_sKZ[];
int    g_dir[];

// Alert state
datetime g_lastAlertTime[];

//+------------------------------------------------------------------+
//| Split symbol string by comma                                     |
//+------------------------------------------------------------------+
int SplitSymbols(const string src, string &out[])
{
   ArrayResize(out, 0);
   string s = src;
   int n = 0;
   while(StringLen(s) > 0)
   {
      int p = StringFind(s, ",");
      string tok = (p >= 0) ? StringSubstr(s, 0, p) : s;
      // trim leading spaces
      while(StringLen(tok) > 0 && StringGetCharacter(tok, 0) == ' ')
         tok = StringSubstr(tok, 1);
      // trim trailing spaces
      while(StringLen(tok) > 0 && StringGetCharacter(tok, StringLen(tok)-1) == ' ')
         tok = StringSubstr(tok, 0, StringLen(tok)-1);
      if(StringLen(tok) > 0)
      {
         ArrayResize(out, n + 1);
         out[n++] = tok;
      }
      if(p < 0) break;
      s = StringSubstr(s, p + 1);
   }
   return n;
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   // Parse symbols
   g_count = SplitSymbols(InpSymbols, g_symbols);
   if(g_count <= 0)
   {
      Print("[SMCSC] ERROR: No valid symbols found in InpSymbols.");
      return INIT_FAILED;
   }
   if(g_count > 10) g_count = 10;

   // Resize all parallel arrays
   ArrayResize(g_ob,   g_count);
   ArrayResize(g_fvg,  g_count);
   ArrayResize(g_liq,  g_count);
   ArrayResize(g_str,  g_count);
   ArrayResize(g_mtf,  g_count);

   ArrayResize(g_score,       g_count);
   ArrayResize(g_sMTF,        g_count);
   ArrayResize(g_sOB,         g_count);
   ArrayResize(g_sFVG,        g_count);
   ArrayResize(g_sStr,        g_count);
   ArrayResize(g_sLiq,        g_count);
   ArrayResize(g_sKZ,         g_count);
   ArrayResize(g_dir,         g_count);
   ArrayResize(g_lastAlertTime, g_count);

   // Initialize modules for each symbol
   for(int i = 0; i < g_count; i++)
   {
      string sym = g_symbols[i];
      g_lastAlertTime[i] = 0;
      g_score[i] = 0;
      g_dir[i] = 0;

      if(!g_ob[i].Init(sym, InpTF, 50, 5, 2.0))
      {
         Print("[SMCSC] WARNING: OB init failed for ", sym);
      }
      if(!g_fvg[i].Init(sym, InpTF, 50, 10, 0.5))
      {
         Print("[SMCSC] WARNING: FVG init failed for ", sym);
      }
      if(!g_liq[i].Init(sym, InpTF, 20))
      {
         Print("[SMCSC] WARNING: LIQ init failed for ", sym);
      }
      if(!g_str[i].Init(sym, InpTF, 20))
      {
         Print("[SMCSC] WARNING: STR init failed for ", sym);
      }
      if(!g_mtf[i].Init(sym, InpHTF, InpMTF_TF, InpLTF, InpEMAPeriod, InpRSIPeriod))
      {
         Print("[SMCSC] WARNING: MTF init failed for ", sym);
      }
   }

   EventSetTimer(15);
   DeleteAllObjects();
   Print("[SMCSC] Initialized, scanning ", g_count, " symbols.");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   for(int i = 0; i < g_count; i++)
   {
      g_ob[i].Deinit();
      g_fvg[i].Deinit();
      g_liq[i].Deinit();
      g_str[i].Deinit();
      g_mtf[i].Deinit();
   }
   DeleteAllObjects();
}

//+------------------------------------------------------------------+
//| Update all modules and scores for all symbols                    |
//+------------------------------------------------------------------+
void UpdateAll()
{
   for(int i = 0; i < g_count; i++)
   {
      g_ob[i].Update();
      g_fvg[i].Update();
      g_liq[i].Update();
      g_str[i].Update();
      g_mtf[i].Update();

      ENUM_HTF_BIAS bias = g_mtf[i].GetBias();
      double align       = g_mtf[i].GetAlignmentScore();
      int dir = (bias == BIAS_BULLISH || bias == BIAS_STRONG_BULLISH) ?  1
              : (bias == BIAS_BEARISH || bias == BIAS_STRONG_BEARISH) ? -1 : 0;

      g_dir[i]  = dir;
      g_sMTF[i] = ScoreMTF(bias, align);
      g_sOB[i]  = g_ob[i].GetConfluenceScore(dir);
      g_sFVG[i] = g_fvg[i].GetConfluenceScore(dir);
      g_sStr[i] = g_str[i].GetConfluenceScore(dir);
      g_sLiq[i] = g_liq[i].GetConfluenceScore(dir);
      g_sKZ[i]  = ScoreKZ();
      g_score[i] = MathMin(g_sMTF[i] + g_sOB[i] + g_sFVG[i] + g_sStr[i] + g_sLiq[i] + g_sKZ[i], 12.0);

      // Alert check
      if(InpAlertOnNew && g_score[i] >= InpAlertScore && g_dir[i] != 0)
      {
         if(TimeCurrent() - g_lastAlertTime[i] >= PeriodSeconds(InpTF))
         {
            string dirStr = (g_dir[i] > 0) ? "BUY" : "SELL";
            string msg = StringFormat("[SMCSC] %s  %s  Score=%.1f/12  %s",
                                      g_symbols[i], dirStr, g_score[i], KZName());
            Alert(msg);
            Print(msg);
            g_lastAlertTime[i] = TimeCurrent();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
{
   UpdateAll();
   DrawScanner();
   return rates_total;
}

//+------------------------------------------------------------------+
//| OnTimer                                                          |
//+------------------------------------------------------------------+
void OnTimer()
{
   UpdateAll();
   DrawScanner();
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| DrawScanner - main table rendering                               |
//+------------------------------------------------------------------+
void DrawScanner()
{
   // Color palette
   color COL_MAIN_BG  = C'13,13,22';
   color COL_HEADER   = C'0,55,88';
   color COL_ACCENT   = C'0,120,180';
   color COL_ROW_A    = C'18,18,30';
   color COL_ROW_B    = C'24,24,38';
   color COL_TBL_HDR  = C'32,32,52';
   color COL_SIG_BUY  = C'0,65,0';
   color COL_SIG_SELL = C'85,0,0';

   int x  = InpDashX;
   int y  = InpDashY;
   int fs = InpFontSize;
   int fsS = MathMax(fs - 1, 7);
   int lh  = fs + 7;
   int pw  = 458;   // total table width
   int px  = x + 10;

   // Column pixel offsets from px
   int col0 = 0;   // symbol    w=85
   int col1 = 90;  // score+bar w=90
   int col2 = 185; // direction w=60
   int col3 = 250; // OB bar    w=38
   int col4 = 293; // FVG bar   w=38
   int col5 = 336; // LIQ bar   w=38
   int col6 = 379; // STR text  w=75

   // Build sort index
   int sortIdx[];
   ArrayResize(sortIdx, g_count);
   for(int i = 0; i < g_count; i++) sortIdx[i] = i;

   if(InpSortByScore)
   {
      // Bubble sort descending by score
      for(int a = 0; a < g_count - 1; a++)
         for(int b = 0; b < g_count - a - 1; b++)
            if(g_score[sortIdx[b]] < g_score[sortIdx[b+1]])
            {
               int tmp = sortIdx[b];
               sortIdx[b] = sortIdx[b+1];
               sortIdx[b+1] = tmp;
            }
   }

   int row = 0;
   #define SY (y + row * lh)

   // Main background
   DashPanel("BG", x-2, y-4, pw+4, lh*(g_count+5)+14, COL_MAIN_BG);

   // Header panel
   DashPanel("HDR", x-2, SY-2, pw+4, lh+4, COL_HEADER);
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   string hdr = "SMC CONFLUENCE SCANNER   " + KZName() +
                "   " + StringFormat("%02d:%02d:%02d", dt.hour, dt.min, dt.sec);
   DashLabel("H0", px, SY+3, hdr, clrWhite, fs, true);
   row++;

   // Accent line
   DashPanel("SEP0", x-2, SY, pw+4, 2, COL_ACCENT);
   row++;

   // Column header row
   DashPanel("TBLHDR", x-2, SY, pw+4, lh+2, COL_TBL_HDR);
   DashLabel("TH0", px + col0, SY+2, "SYMBOL",    C'140,140,185', fsS);
   DashLabel("TH1", px + col1, SY+2, "SCORE",     C'140,140,185', fsS);
   DashLabel("TH2", px + col2, SY+2, "BIAS",      C'140,140,185', fsS);
   DashLabel("TH3", px + col3, SY+2, "OB",        C'140,140,185', fsS);
   DashLabel("TH4", px + col4, SY+2, "FVG",       C'140,140,185', fsS);
   DashLabel("TH5", px + col5, SY+2, "LIQ",       C'140,140,185', fsS);
   DashLabel("TH6", px + col6, SY+2, "STRUCTURE", C'140,140,185', fsS);
   row++;

   // Data rows
   for(int r = 0; r < g_count; r++)
   {
      int i = sortIdx[r];
      bool isSignal = (g_score[i] >= InpMinScore);

      color rowBg = isSignal
                  ? (g_dir[i] > 0 ? COL_SIG_BUY : (g_dir[i] < 0 ? COL_SIG_SELL : C'30,30,50'))
                  : ((r % 2 == 0) ? COL_ROW_A : COL_ROW_B);

      string rid = "R" + IntegerToString(r);
      DashPanel(rid + "BG", x-2, SY, pw+4, lh+2, rowBg);

      // Symbol
      color symCol = isSignal ? clrWhite : C'200,200,220';
      DashLabel(rid + "SYM", px + col0, SY+2, g_symbols[i], symCol, fsS, isSignal);

      // Score + mini bar
      string scoreStr = StringFormat("%.1f", g_score[i]) + " " + MakeBar(g_score[i], 12.0, 8);
      DashLabel(rid + "SCR", px + col1, SY+2, scoreStr, ScoreCol(g_score[i]), fsS);

      // Direction
      string dirTxt;
      color  dirCol, dirBg;
      if(g_dir[i] > 0)       { dirTxt = " BUY ";  dirCol = clrLime;      dirBg = C'0,65,0';   }
      else if(g_dir[i] < 0)  { dirTxt = " SELL "; dirCol = clrOrangeRed; dirBg = C'85,0,0';   }
      else                   { dirTxt = "  --- ";  dirCol = clrSilver;    dirBg = C'40,40,60'; }
      DashPanel(rid + "DIRBG", px + col2 - 2, SY+1, 55, lh, dirBg);
      DashLabel(rid + "DIR",   px + col2,     SY+2, dirTxt, dirCol, fsS, true);

      // OB mini bar (4 chars)
      DashLabel(rid + "OB",  px + col3, SY+2, MakeBar(g_sOB[i],  1.5, 4), ScoreCol(g_sOB[i] * 8.0),  fsS);
      // FVG mini bar (4 chars)
      DashLabel(rid + "FVG", px + col4, SY+2, MakeBar(g_sFVG[i], 1.0, 4), ScoreCol(g_sFVG[i] * 12.0), fsS);
      // LIQ mini bar (4 chars)
      DashLabel(rid + "LIQ", px + col5, SY+2, MakeBar(g_sLiq[i], 1.5, 4), ScoreCol(g_sLiq[i] * 8.0),  fsS);

      // Structure text
      ENUM_STRUCTURE_TYPE st = g_str[i].GetLastBreakType();
      string stStr = ScanStructStr(st);
      color  stCol = (st == STRUCT_BOS_BULLISH  || st == STRUCT_CHOCH_BULLISH) ? clrMediumSeaGreen
                   : (st == STRUCT_BOS_BEARISH  || st == STRUCT_CHOCH_BEARISH) ? clrIndianRed
                   : C'90,90,90';
      DashLabel(rid + "STR", px + col6, SY+2, stStr, stCol, fsS);

      row++;
   }

   // Footer separator
   DashPanel("SEP1", x-2, SY, pw+4, 2, COL_ACCENT);
   row++;

   // Footer
   DashPanel("FTBG", x-2, SY, pw+4, lh+2, COL_ROW_A);
   DashLabel("FOOT", px, SY+2,
             StringFormat("Updated %02d:%02d:%02d | 15s refresh | %d symbols | Min score: %.1f",
                          dt.hour, dt.min, dt.sec, g_count, InpMinScore),
             C'60,60,90', fsS-1);
   row++;

   // Resize main BG
   int totalH = row * lh + 14;
   string bgName = OBJ_PFX + "DASH_BG";
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, totalH);

   #undef SY
   ChartRedraw();
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
   if(est >= 2 && est < 5)   return 1.0;  // London Open
   if(est >= 7 && est < 10)  return 1.0;  // NY Open
   if(est >= 20 || est < 1)  return 0.5;  // Asian
   if(est >= 10 && est < 12) return 0.5;  // London Close
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

string ScanStructStr(ENUM_STRUCTURE_TYPE st)
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
