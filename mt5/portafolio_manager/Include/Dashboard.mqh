//+------------------------------------------------------------------+
//|                                                    Dashboard.mqh |
//|                     PORTFOLIO GOVERNOR - INSTITUTIONAL UI        |
//|                                  Copyright 2026, Guido Ambiorix  |
//+------------------------------------------------------------------+
#ifndef DASHBOARD_MQH
#define DASHBOARD_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

#include <ChartObjects\ChartObjectsTxtControls.mqh>
#include <ChartObjects\ChartObjectsBmpControls.mqh>

//--- COLORS (Professional Dark Theme) ---
#define CLR_BG          C'15,15,20'       // Deep dark background
#define CLR_PANEL       C'25,28,35'       // Panel background
#define CLR_HEADER      C'35,40,50'       // Header gradient
#define CLR_ACCENT      C'0,150,255'      // Electric blue
#define CLR_TEXT_MAIN   C'240,240,245'    // Bright white
#define CLR_TEXT_DIM    C'140,145,155'    // Dimmed text
#define CLR_GREEN       C'39,174,96'      // Success green
#define CLR_RED         C'192,57,43'      // Alert red
#define CLR_ORANGE      C'230,126,34'     // Warning orange
#define CLR_GOLD        C'241,196,15'     // Premium gold
#define CLR_PURPLE      C'155,89,182'     // Risk purple
#define CLR_CYAN        C'26,188,156'     // Info cyan
#define CLR_BORDER      C'45,50,60'       // Subtle borders

//+------------------------------------------------------------------+
//| INSTITUTIONAL-GRADE DASHBOARD                                     |
//+------------------------------------------------------------------+
class CDashboard
{
private:
   // Layout Constants
   int m_x, m_y, m_w, m_h;

   // === BACKGROUND PANELS ===
   CChartObjectRectLabel m_bgMain;
   CChartObjectRectLabel m_bgHeader;
   CChartObjectRectLabel m_bgStatus;
   CChartObjectRectLabel m_bgPerformance;
   CChartObjectRectLabel m_bgRisk;
   CChartObjectRectLabel m_bgIntel;
   CChartObjectRectLabel m_bgTrades;
   CChartObjectRectLabel m_bgStats;

   // Progress Bars
   CChartObjectRectLabel m_barEquityBG;
   CChartObjectRectLabel m_barEquityFill;
   CChartObjectRectLabel m_barDDBG;
   CChartObjectRectLabel m_barDDFill;

   // === HEADER ===
   CChartObjectLabel m_lblTitle;
   CChartObjectLabel m_lblVersion;
   CChartObjectLabel m_lblTime;

   // === STATUS SECTION ===
   CChartObjectLabel m_lblStatusTitle;
   CChartObjectLabel m_lblKillStatus;
   CChartObjectLabel m_lblConnection;
   CChartObjectLabel m_lblLatency;
   CChartObjectLabel m_lblUptime;

   // === PERFORMANCE SECTION ===
   CChartObjectLabel m_lblPerfTitle;
   CChartObjectLabel m_lblTodayPnL;
   CChartObjectLabel m_lblWinRate;
   CChartObjectLabel m_lblProfitFactor;
   CChartObjectLabel m_lblTradesCount;

   // === RISK SECTION ===
   CChartObjectLabel m_lblRiskTitle;
   CChartObjectLabel m_lblEquity;
   CChartObjectLabel m_lblEquityBar;
   CChartObjectLabel m_lblDrawdown;
   CChartObjectLabel m_lblDDBar;
   CChartObjectLabel m_lblExposure;
   CChartObjectLabel m_lblMargin;

   // === INTEL SECTION ===
   CChartObjectLabel m_lblIntelTitle;
   CChartObjectLabel m_lblRegime;
   CChartObjectLabel m_lblConfidence;
   CChartObjectLabel m_lblUniverse;
   CChartObjectLabel m_lblRecovery;

   // === LIVE STATS ===
   CChartObjectLabel m_lblStatsTitle;
   CChartObjectLabel m_lblWins;
   CChartObjectLabel m_lblLosses;
   CChartObjectLabel m_lblAvgWin;
   CChartObjectLabel m_lblAvgLoss;

   // === SYMBOL CONFLUENCE TABLE ===
   CChartObjectRectLabel m_bgSymbols;
   CChartObjectLabel m_lblSymbolsTitle;
   CChartObjectLabel m_lblSymbolHeaders;   // Table headers
   CChartObjectLabel m_lblSymbols[8];      // Up to 8 symbols

   // === TRADES LIST ===
   CChartObjectLabel m_lblTradesTitle;
   CChartObjectLabel m_lblTrades[12];

   // === FOOTER ===
   CChartObjectLabel m_lblFooter;

   // State tracking
   datetime m_initTime;
   int m_flashState;

public:
   CDashboard() : m_x(15), m_y(15), m_w(900), m_h(550)
   {
      m_initTime = TimeCurrent();
      m_flashState = 0;
   }

   ~CDashboard() { Destroy(); }

   //+------------------------------------------------------------------+
   //| INIT - Build the UI                                              |
   //+------------------------------------------------------------------+
   void Init()
   {
      Destroy();
      long cid = ChartID();

      // === MAIN BACKGROUND ===
      CreatePanel(m_bgMain, "BG_Main", m_x, m_y, m_w, m_h, CLR_BG, CLR_BORDER);

      // === HEADER SECTION ===
      CreatePanel(m_bgHeader, "BG_Header", m_x, m_y, m_w, 55, CLR_HEADER, CLR_ACCENT);
      CreateLabel(m_lblTitle, "L_Title", m_x+20, m_y+12, "🧠 PORTFOLIO GOVERNOR", 15, CLR_GOLD, true);
      CreateLabel(m_lblVersion, "L_Ver", m_x+350, m_y+18, "GOD MODE v2.1", 9, CLR_TEXT_DIM);
      CreateLabel(m_lblTime, "L_Time", m_x+750, m_y+18, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), 9, CLR_CYAN);

      int py = m_y + 65;
      int leftW = 580;
      int rightX = m_x + leftW + 10;
      int gap = 10;

      // === LEFT COLUMN ===

      // 1. STATUS PANEL (Top Left)
      CreatePanel(m_bgStatus, "BG_Status", m_x+10, py, 280, 130, CLR_PANEL, CLR_BORDER);
      CreateLabel(m_lblStatusTitle, "L_StatT", m_x+20, py+8, "🛡️ SYSTEM STATUS", 11, CLR_ACCENT, true);
      CreateLabel(m_lblKillStatus, "L_Kill", m_x+25, py+38, "● ACTIVE", 11, CLR_GREEN, true);
      CreateLabel(m_lblConnection, "L_Conn", m_x+25, py+65, "Uplink: Checking...", 9, CLR_TEXT_DIM);
      CreateLabel(m_lblLatency, "L_Lat", m_x+25, py+85, "Latency: --- ms", 9, CLR_TEXT_DIM);
      CreateLabel(m_lblUptime, "L_Up", m_x+25, py+105, "Uptime: 0m", 9, CLR_TEXT_DIM);

      // 2. PERFORMANCE PANEL (Top Right of Left Column)
      CreatePanel(m_bgPerformance, "BG_Perf", m_x+300, py, 280, 130, CLR_PANEL, CLR_BORDER);
      CreateLabel(m_lblPerfTitle, "L_PerfT", m_x+310, py+8, "📈 PERFORMANCE", 11, CLR_ACCENT, true);
      CreateLabel(m_lblTodayPnL, "L_PnL", m_x+315, py+38, "Today: $0.00", 11, CLR_TEXT_MAIN, true);
      CreateLabel(m_lblWinRate, "L_WR", m_x+315, py+65, "Win Rate: --%", 9, CLR_TEXT_DIM);
      CreateLabel(m_lblProfitFactor, "L_PF", m_x+315, py+85, "Profit Factor: --", 9, CLR_TEXT_DIM);
      CreateLabel(m_lblTradesCount, "L_Cnt", m_x+315, py+105, "Trades: 0 (0W/0L)", 9, CLR_TEXT_DIM);

      // 3. RISK PANEL (Middle Left - Expanded)
      py += 140;
      CreatePanel(m_bgRisk, "BG_Risk", m_x+10, py, 570, 160, CLR_PANEL, CLR_BORDER);
      CreateLabel(m_lblRiskTitle, "L_RiskT", m_x+20, py+8, "💰 RISK MANAGEMENT", 11, CLR_ACCENT, true);

      // Equity with progress bar
      CreateLabel(m_lblEquity, "L_Eq", m_x+25, py+38, "EQUITY: $0.00", 12, CLR_TEXT_MAIN, true);
      CreateLabel(m_lblEquityBar, "L_EqLbl", m_x+25, py+65, "Peak", 8, CLR_TEXT_DIM);
      CreatePanel(m_barEquityBG, "Bar_EqBG", m_x+25, py+75, 250, 8, C'40,40,45', C'40,40,45');
      CreatePanel(m_barEquityFill, "Bar_EqFill", m_x+25, py+75, 125, 8, CLR_GREEN, CLR_GREEN);

      // Drawdown with progress bar
      CreateLabel(m_lblDrawdown, "L_DD", m_x+305, py+38, "DRAWDOWN: 0.00%", 11, CLR_GREEN, true);
      CreateLabel(m_lblDDBar, "L_DDLbl", m_x+305, py+65, "Max Allowed", 8, CLR_TEXT_DIM);
      CreatePanel(m_barDDBG, "Bar_DDBG", m_x+305, py+75, 250, 8, C'40,40,45', C'40,40,45');
      CreatePanel(m_barDDFill, "Bar_DDFill", m_x+305, py+75, 1, 8, CLR_RED, CLR_RED);

      // Additional metrics
      CreateLabel(m_lblExposure, "L_Exp", m_x+25, py+100, "Exposure: 0.00%", 9, CLR_TEXT_DIM);
      CreateLabel(m_lblMargin, "L_Mar", m_x+25, py+120, "Margin Free: $0.00", 9, CLR_TEXT_DIM);

      // 4. INTEL PANEL (Bottom Left)
      py += 170;
      CreatePanel(m_bgIntel, "BG_Intel", m_x+10, py, 280, 110, CLR_PANEL, CLR_BORDER);
      CreateLabel(m_lblIntelTitle, "L_IntT", m_x+20, py+8, "🧠 MARKET INTEL", 11, CLR_ACCENT, true);
      CreateLabel(m_lblRegime, "L_Reg", m_x+25, py+38, "REGIME: SCANNING", 10, CLR_TEXT_MAIN, true);
      CreateLabel(m_lblConfidence, "L_Conf", m_x+25, py+65, "Confidence: --%", 9, CLR_TEXT_DIM);
      CreateLabel(m_lblUniverse, "L_Uni", m_x+25, py+85, "Universe: 0 Symbols", 9, CLR_TEXT_DIM);

      // 5. LIVE STATS PANEL (Bottom Right of Left Column)
      CreatePanel(m_bgStats, "BG_Stats", m_x+300, py, 280, 110, CLR_PANEL, CLR_BORDER);
      CreateLabel(m_lblStatsTitle, "L_StatT2", m_x+310, py+8, "📊 TODAY'S STATS", 11, CLR_ACCENT, true);
      CreateLabel(m_lblWins, "L_Wins", m_x+315, py+38, "✓ Wins: 0", 9, CLR_GREEN);
      CreateLabel(m_lblLosses, "L_Loss", m_x+420, py+38, "✗ Losses: 0", 9, CLR_RED);
      CreateLabel(m_lblAvgWin, "L_AvgW", m_x+315, py+60, "Avg Win: $0.00", 9, CLR_TEXT_DIM);
      CreateLabel(m_lblAvgLoss, "L_AvgL", m_x+420, py+60, "Avg Loss: $0.00", 9, CLR_TEXT_DIM);
      CreateLabel(m_lblRecovery, "L_Rec", m_x+315, py+85, "Recovery Multi: 1.0x", 9, CLR_PURPLE);

      // === RIGHT COLUMN ===
      py = m_y + 65;

      // 1. SYMBOL CONFLUENCE TABLE (Top Right)
      CreatePanel(m_bgSymbols, "BG_Syms", rightX, py, 295, 265, CLR_PANEL, CLR_BORDER);
      CreateLabel(m_lblSymbolsTitle, "L_SymT", rightX+15, py+8, "📊 SYMBOL CONFLUENCE", 11, CLR_ACCENT, true);

      // Table Headers
      CreateLabel(m_lblSymbolHeaders, "L_SymHead", rightX+15, py+35,
                  "Symbol      BUY   SELL   Status", 8, CLR_TEXT_DIM);

      int symY = py + 55;
      for(int i=0; i<8; i++)
      {
         CreateLabel(m_lblSymbols[i], "L_Sym"+IntegerToString(i), rightX+15, symY + (i*25),
                     "---         --    --     SCANNING", 9, CLR_TEXT_DIM);
      }

      // 2. ACTIVE TRADES PANEL (Bottom Right)
      py += 275;
      CreatePanel(m_bgTrades, "BG_Trades", rightX, py, 295, 265, CLR_PANEL, CLR_BORDER);
      CreateLabel(m_lblTradesTitle, "L_TrdT", rightX+15, py+8, "⚡ ACTIVE POSITIONS", 11, CLR_GOLD, true);

      int rowY = py + 40;
      for(int i=0; i<12; i++)
      {
         CreateLabel(m_lblTrades[i], "L_Trd"+IntegerToString(i), rightX+15, rowY + (i*22), "---", 8, CLR_TEXT_DIM);
      }

      // === FOOTER ===
      CreateLabel(m_lblFooter, "L_Foot", m_x+15, m_y+m_h-25, "🚀 Ready for battle", 8, CLR_TEXT_DIM);

      ChartRedraw();
   }

   //+------------------------------------------------------------------+
   //| UPDATE - Refresh all metrics                                     |
   //+------------------------------------------------------------------+
   void Update(string status, string regime, double equity, double dd,
               double var, string recoveryTxt, string connStatus, int ping)
   {
      // Update time
      m_lblTime.Description(TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));

      // Uptime
      int uptimeMin = (int)((TimeCurrent() - m_initTime) / 60);
      m_lblUptime.Description("Uptime: " + IntegerToString(uptimeMin) + "m");

      // === STATUS SECTION ===
      bool isKilled = (StringFind(status, "KILL") >= 0 || StringFind(status, "STOP") >= 0);

      if(isKilled)
      {
         m_lblKillStatus.Description("● KILLED");
         m_lblKillStatus.Color(CLR_RED);
         m_bgStatus.BackColor(C'60,30,30');

         // Flash effect
         m_flashState = (m_flashState + 1) % 10;
         if(m_flashState < 5)
            m_bgHeader.BackColor(C'80,20,20');
         else
            m_bgHeader.BackColor(CLR_HEADER);
      }
      else
      {
         m_lblKillStatus.Description("● " + status);
         m_lblKillStatus.Color(CLR_GREEN);
         m_bgStatus.BackColor(CLR_PANEL);
         m_bgHeader.BackColor(CLR_HEADER);
      }

      m_lblConnection.Description("Uplink: " + connStatus);
      m_lblConnection.Color(connStatus == "Stable" ? CLR_CYAN : CLR_ORANGE);

      m_lblLatency.Description("Latency: " + IntegerToString(ping) + " ms");
      color pingColor = (ping > 200) ? CLR_RED : (ping > 100) ? CLR_ORANGE : CLR_GREEN;
      m_lblLatency.Color(pingColor);

      // === RISK SECTION ===
      m_lblEquity.Description("EQUITY: $" + DoubleToString(equity, 2));

      double balance = AccountInfoDouble(ACCOUNT_BALANCE);

      // Equity progress bar (equity vs balance)
      double equityPct = (balance > 0) ? (equity / balance) * 100.0 : 100.0;
      int barWidth = (int)((equityPct / 100.0) * 250);
      if(barWidth < 0) barWidth = 0;
      if(barWidth > 250) barWidth = 250;

      m_barEquityFill.X_Size(barWidth);
      color eqColor = (equity >= balance) ? CLR_GREEN : CLR_ORANGE;
      if(equity < balance * 0.95) eqColor = CLR_RED;
      m_barEquityFill.BackColor(eqColor);

      m_lblEquityBar.Description("vs Balance: " + DoubleToString(equityPct, 1) + "%");

      // Drawdown
      m_lblDrawdown.Description("DRAWDOWN: " + DoubleToString(dd, 2) + "%");
      color ddColor = (dd > 8.0) ? CLR_RED : (dd > 5.0) ? CLR_ORANGE : CLR_GREEN;
      m_lblDrawdown.Color(ddColor);

      // DD progress bar (current vs max allowed 10%)
      double ddPct = (dd / 10.0) * 100.0;
      int ddBarWidth = (int)((ddPct / 100.0) * 250);
      if(ddBarWidth < 0) ddBarWidth = 0;
      if(ddBarWidth > 250) ddBarWidth = 250;
      m_barDDFill.X_Size(ddBarWidth);
      m_barDDFill.BackColor(ddColor);

      m_lblDDBar.Description("of 10% Max (" + DoubleToString(ddPct, 0) + "%)");

      // Additional metrics
      m_lblExposure.Description("Exposure: " + DoubleToString(var, 2) + "%");
      m_lblMargin.Description("Margin Free: $" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2));

      // === INTEL SECTION ===
      m_lblRegime.Description("REGIME: " + regime);
      color regimeColor = CLR_TEXT_MAIN;
      if(regime == "TREND") regimeColor = CLR_GREEN;
      else if(regime == "VOLATILE") regimeColor = CLR_ORANGE;
      else if(regime == "RANGE") regimeColor = CLR_CYAN;
      m_lblRegime.Color(regimeColor);

      m_lblRecovery.Description(recoveryTxt);

      ChartRedraw();
   }

   //+------------------------------------------------------------------+
   //| UPDATE PERFORMANCE STATS                                          |
   //+------------------------------------------------------------------+
   void UpdatePerformance(double todayPnL, double winRate, double profitFactor,
                          int totalTrades, int wins, int losses,
                          double avgWin, double avgLoss)
   {
      // Today's P&L
      color pnlColor = (todayPnL >= 0) ? CLR_GREEN : CLR_RED;
      string pnlSign = (todayPnL >= 0) ? "+" : "";
      m_lblTodayPnL.Description("Today: " + pnlSign + "$" + DoubleToString(todayPnL, 2));
      m_lblTodayPnL.Color(pnlColor);

      // Win Rate
      color wrColor = (winRate >= 60) ? CLR_GREEN : (winRate >= 50) ? CLR_CYAN : CLR_ORANGE;
      m_lblWinRate.Description("Win Rate: " + DoubleToString(winRate, 1) + "%");
      m_lblWinRate.Color(wrColor);

      // Profit Factor
      color pfColor = (profitFactor >= 2.0) ? CLR_GREEN : (profitFactor >= 1.5) ? CLR_CYAN : CLR_ORANGE;
      m_lblProfitFactor.Description("Profit Factor: " + DoubleToString(profitFactor, 2));
      m_lblProfitFactor.Color(pfColor);

      // Trade count
      m_lblTradesCount.Description("Trades: " + IntegerToString(totalTrades) +
                                   " (" + IntegerToString(wins) + "W/" + IntegerToString(losses) + "L)");

      // Live Stats
      m_lblWins.Description("✓ Wins: " + IntegerToString(wins));
      m_lblLosses.Description("✗ Losses: " + IntegerToString(losses));
      m_lblAvgWin.Description("Avg Win: $" + DoubleToString(avgWin, 2));
      m_lblAvgLoss.Description("Avg Loss: $" + DoubleToString(MathAbs(avgLoss), 2));

      ChartRedraw();
   }

   //+------------------------------------------------------------------+
   //| UPDATE INTEL (Confidence, Universe Size)                         |
   //+------------------------------------------------------------------+
   void UpdateIntel(double confidence, int universeSize, string optimizer)
   {
      m_lblConfidence.Description("Confidence: " + DoubleToString(confidence * 100, 0) + "%");

      color confColor = (confidence >= 0.7) ? CLR_GREEN : (confidence >= 0.5) ? CLR_CYAN : CLR_ORANGE;
      m_lblConfidence.Color(confColor);

      m_lblUniverse.Description("Universe: " + IntegerToString(universeSize) + " Symbols");

      ChartRedraw();
   }

   //+------------------------------------------------------------------+
   //| UPDATE SYMBOL CONFLUENCE TABLE                                    |
   //+------------------------------------------------------------------+
   struct SymbolConfluenceRow
   {
      string symbol;
      double buyScore;
      double sellScore;
      string status;
   };

   void UpdateSymbolTable(SymbolConfluenceRow &rows[])
   {
      int count = ArraySize(rows);
      for(int i=0; i<8; i++)
      {
         if(i < count)
         {
            string sym = rows[i].symbol;
            // Truncate symbol to 6 chars max for alignment
            if(StringLen(sym) > 6) sym = StringSubstr(sym, 0, 6);

            // Format scores with color coding
            string buyStr = DoubleToString(rows[i].buyScore, 1);
            string sellStr = DoubleToString(rows[i].sellScore, 1);

            // Pad for alignment
            while(StringLen(sym) < 11) sym += " ";
            while(StringLen(buyStr) < 5) buyStr = " " + buyStr;
            while(StringLen(sellStr) < 5) sellStr = " " + sellStr;

            string status = rows[i].status;
            if(StringLen(status) > 12) status = StringSubstr(status, 0, 12);

            string line = sym + buyStr + sellStr + "  " + status;
            m_lblSymbols[i].Description(line);

            // Color based on highest score
            double maxScore = MathMax(rows[i].buyScore, rows[i].sellScore);
            color rowColor = CLR_TEXT_DIM;

            if(maxScore >= 9.0)
               rowColor = CLR_GOLD;        // ELITE
            else if(maxScore >= 7.0)
               rowColor = CLR_GREEN;       // STRONG
            else if(maxScore >= 6.0)
               rowColor = CLR_CYAN;        // GOOD
            else if(maxScore >= 4.0)
               rowColor = CLR_ORANGE;      // MONITORING

            m_lblSymbols[i].Color(rowColor);
         }
         else
         {
            m_lblSymbols[i].Description("---         --    --     ---");
            m_lblSymbols[i].Color(CLR_TEXT_DIM);
         }
      }

      ChartRedraw();
   }

   //+------------------------------------------------------------------+
   //| UPDATE TRADES LIST                                                |
   //+------------------------------------------------------------------+
   void UpdateTradesList(string &tradeRows[])
   {
      int count = ArraySize(tradeRows);
      for(int i=0; i<12; i++)
      {
         string txt = "---";
         color clr = CLR_TEXT_DIM;

         if(i < count && tradeRows[i] != "")
         {
            txt = tradeRows[i];

            // Color coding
            if(StringFind(txt, "$ -") >= 0 || StringFind(txt, "-$") >= 0)
               clr = CLR_RED;
            else if(StringFind(txt, "$ +") >= 0 || StringFind(txt, "+$") >= 0)
               clr = CLR_GREEN;
            else if(StringFind(txt, "$") >= 0)
               clr = CLR_CYAN;
         }

         m_lblTrades[i].Description(txt);
         m_lblTrades[i].Color(clr);
      }
      ChartRedraw();
   }

   //+------------------------------------------------------------------+
   //| UPDATE FOOTER MESSAGE                                             |
   //+------------------------------------------------------------------+
   void UpdateFooter(string msg)
   {
      m_lblFooter.Description("🚀 " + msg);
      ChartRedraw();
   }

   void Destroy()
   {
      ObjectsDeleteAll(ChartID(), "L_");
      ObjectsDeleteAll(ChartID(), "BG_");
      ObjectsDeleteAll(ChartID(), "Bar_");
   }

private:
   //+------------------------------------------------------------------+
   //| Helper: Create Panel                                             |
   //+------------------------------------------------------------------+
   void CreatePanel(CChartObjectRectLabel &obj, string name, int x, int y, int w, int h, color bg, color border)
   {
      if(ObjectFind(ChartID(), name) >= 0) ObjectDelete(ChartID(), name);
      obj.Create(ChartID(), name, 0, x, y, w, h);
      obj.BackColor(bg);
      obj.Color(border);
      obj.BorderType(BORDER_FLAT);
      obj.Corner(CORNER_LEFT_UPPER);
      obj.Selectable(false);
      obj.Z_Order(0);
   }

   //+------------------------------------------------------------------+
   //| Helper: Create Label                                             |
   //+------------------------------------------------------------------+
   void CreateLabel(CChartObjectLabel &obj, string name, int x, int y, string text, int size, color clr, bool bold=false)
   {
      if(ObjectFind(ChartID(), name) >= 0) ObjectDelete(ChartID(), name);
      obj.Create(ChartID(), name, 0, x, y);
      obj.Description(text);
      obj.FontSize(size);
      obj.Color(clr);
      if(bold) obj.Font("Consolas Bold");
      else obj.Font("Consolas");
      obj.Corner(CORNER_LEFT_UPPER);
      obj.Selectable(false);
      obj.Z_Order(10);
   }
};

#endif
