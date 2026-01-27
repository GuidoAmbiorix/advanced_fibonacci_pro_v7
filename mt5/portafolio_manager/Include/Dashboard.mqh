//+------------------------------------------------------------------+
//|                                                    Dashboard.mqh |
//|                                  Copyright 2026, Guido Ambiorix  |
//|                                     https://github.com/GuidoAmbiorix |
//+------------------------------------------------------------------+
#ifndef DASHBOARD_MQH
#define DASHBOARD_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

#include <ChartObjects\ChartObjectsTxtControls.mqh>
#include <ChartObjects\ChartObjectsBmpControls.mqh>

//--- COLORS ---
#define CLR_BG          C'20,20,25'
#define CLR_PANEL       C'35,35,40'
#define CLR_HEADER      C'45,45,50'
#define CLR_TEXT_MAIN   C'225,225,225'
#define CLR_TEXT_DIM    C'160,160,160'
#define CLR_ACCENT      C'0,120,215'
#define CLR_GREEN       C'46,204,113'
#define CLR_RED         C'231,76,60'
#define CLR_ORANGE      C'243,156,18'
#define CLR_GOLD        C'241,196,15'

//+------------------------------------------------------------------+
//| PREMIUM DASHBOARD CLASS                                           |
//+------------------------------------------------------------------+
class CDashboard
{
private:
   // Layout Constants
   int m_x, m_y, m_w, m_h;
   int m_col1_w, m_col2_w;
   
   // Backgrounds
   CChartObjectRectLabel m_bgMain;
   CChartObjectRectLabel m_bgHeader;
   CChartObjectRectLabel m_bgStatus;
   CChartObjectRectLabel m_bgIntel;
   CChartObjectRectLabel m_bgRisk;
   CChartObjectRectLabel m_bgTrades; // Side Panel
   
   // Headers
   CChartObjectLabel    m_lblTitle;
   CChartObjectLabel    m_lblSubTitle;
   CChartObjectLabel    m_lblTime;
   
   // Section Titles
   CChartObjectLabel    m_lblSecTitle;
   CChartObjectLabel    m_lblIntelTitle;
   CChartObjectLabel    m_lblRiskTitle;
   CChartObjectLabel    m_lblTradesTitle;
   
   // Status Metrics
   CChartObjectLabel    m_lblKillStatus;
   CChartObjectLabel    m_lblConn;
   CChartObjectLabel    m_lblPing;
   CChartObjectLabel    m_lblLiquidity;
   
   // Intel Metrics
   CChartObjectLabel    m_lblRegime;
   CChartObjectLabel    m_lblConf;
   CChartObjectLabel    m_lblActiveSyms;
   CChartObjectLabel    m_lblOptStatus;
   
   // Risk Metrics
   CChartObjectLabel    m_lblEquity;
   CChartObjectLabel    m_lblBalance;
   CChartObjectLabel    m_lblDD;
   CChartObjectLabel    m_lblVaR;
   CChartObjectLabel    m_lblRecov;
   
   // Trades List (Up to 12 rows)
   CChartObjectLabel    m_lblTrades[12];
   
   // Footer
   CChartObjectLabel    m_lblMsg;

public:
   // Expanded Width to 800 for Side Panel
   CDashboard() : m_x(20), m_y(20), m_w(800), m_h(450)
   {
      m_col1_w = 280; // Main content area split
   }
   
   ~CDashboard() { Destroy(); }

   //+------------------------------------------------------------------+
   //| INIT                                                              |
   //+------------------------------------------------------------------+
   void Init()
   {
      Destroy();
      long cid = ChartID();
      
      // 1. Main Background
      CreatePanel(m_bgMain, "BG_Main", m_x, m_y, m_w, m_h, CLR_BG, C'60,60,60');
      
      // 2. Header
      CreatePanel(m_bgHeader, "BG_Head", m_x, m_y, m_w, 50, CLR_HEADER, CLR_HEADER);
      CreateLabel(m_lblTitle, "L_Ti", m_x+15, m_y+10, "🧠 PORTFOLIO GOVERNOR", 14, CLR_GOLD, true);
      CreateLabel(m_lblSubTitle, "L_Sub", m_x+300, m_y+15, "GOD MODE v2.1", 9, CLR_TEXT_DIM);
      CreateLabel(m_lblTime, "L_Time", m_x+700, m_y+15, "00:00", 9, CLR_TEXT_MAIN);
      
      // --- LEFT COLUMN (Status & Risk) ---
      int py = m_y + 60;
      int leftW = 550; 
      int rightX = m_x + leftW + 10;
      int rightW = 220;
      
      // 3. Status Section (Top Left)
      CreatePanel(m_bgStatus, "BG_Stat", m_x+10, py, 260, 140, CLR_PANEL, CLR_PANEL);
      CreateLabel(m_lblSecTitle, "L_SecT", m_x+20, py+10, "🛡️ SAFETY CORE", 10, CLR_ACCENT, true);
      
      CreateLabel(m_lblKillStatus, "L_Kill", m_x+20, py+40, "STATUS:  INITIALIZING...", 10, CLR_TEXT_MAIN, true);
      CreateLabel(m_lblConn, "L_Conn", m_x+20, py+70, "UPLINK:  Checking...", 9, CLR_TEXT_DIM);
      CreateLabel(m_lblPing, "L_Ping", m_x+20, py+90, "LATENCY: 0 ms", 9, CLR_TEXT_DIM);
      CreateLabel(m_lblLiquidity, "L_Liq", m_x+20, py+110, "LIQUIDITY: OK", 9, CLR_GREEN);
      
      // 4. Intelligence Section (Top Mid)
      CreatePanel(m_bgIntel, "BG_Intel", m_x+280, py, 280, 140, CLR_PANEL, CLR_PANEL);
      CreateLabel(m_lblIntelTitle, "L_IntT", m_x+290, py+10, "🧠 MARKET INTEL", 10, CLR_ACCENT, true);
      
      CreateLabel(m_lblRegime, "L_Reg", m_x+290, py+40, "REGIME:  SCANNING", 10, CLR_TEXT_MAIN, true);
      CreateLabel(m_lblConf, "L_Conf", m_x+290, py+70, "CONFIDENCE: 0%", 9, CLR_TEXT_DIM);
      CreateLabel(m_lblActiveSyms, "L_Syms", m_x+290, py+90, "UNIVERSE: 0 Pairs", 9, CLR_TEXT_DIM);
      CreateLabel(m_lblOptStatus, "L_Opt", m_x+290, py+110, "OPTIMIZER: IDLE", 9, CLR_TEXT_DIM);
      
      // 5. Risk & Performance (Bottom Left/Mid)
      py += 150;
      CreatePanel(m_bgRisk, "BG_Risk", m_x+10, py, 550, 180, CLR_PANEL, CLR_PANEL);
      CreateLabel(m_lblRiskTitle, "L_RskT", m_x+20, py+10, "📊 RISK & PERFORMANCE", 10, CLR_ACCENT, true);
      
      CreateLabel(m_lblEquity, "L_Eq", m_x+40, py+50, "EQUITY: $0.00", 12, CLR_TEXT_MAIN, true);
      CreateLabel(m_lblBalance, "L_Bal", m_x+40, py+80, "BALANCE: $0.00", 10, CLR_TEXT_DIM);
      
      CreateLabel(m_lblDD, "L_DD", m_x+250, py+50, "DRAWDOWN: 0.00%", 11, CLR_GREEN, true);
      CreateLabel(m_lblVaR, "L_VaR", m_x+250, py+80, "VaR (95%): $0.00", 10, CLR_ORANGE);
      CreateLabel(m_lblRecov, "L_Rec", m_x+400, py+50, "RECV Multi: 1.0x", 11, CLR_ACCENT, true);
      
      // --- RIGHT COLUMN (Trades) ---
      py = m_y + 60; // Reset Y
      CreatePanel(m_bgTrades, "BG_Trd", rightX, py, rightW, 330, CLR_PANEL, CLR_PANEL);
      CreateLabel(m_lblTradesTitle, "L_TrdT", rightX+10, py+10, "⚡ ACTIVE TRADES", 10, CLR_GOLD, true);
      
      int rowStep = 25;
      for(int i=0; i<12; i++)
      {
         CreateLabel(m_lblTrades[i], "L_TrdRow"+IntegerToString(i), rightX+10, py+40 + (i*rowStep), "--", 9, CLR_TEXT_DIM);
      }
      
      // Footer
      py = m_y + 400;
      CreateLabel(m_lblMsg, "L_Msg", m_x+10, py+30, "Ready.", 8, CLR_TEXT_DIM);
      
      ChartRedraw();
   }
   
   //+------------------------------------------------------------------+
   //| UPDATE MAIN METRICS                                               |
   //+------------------------------------------------------------------+
   void Update(string status, string regime, double equity, double dd, 
               double var, string recoveryTxt, string connStatus, int ping)
   {
      m_lblTime.Description(TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
      
      // Security
      m_lblKillStatus.Description("STATUS:  " + status);
      if(StringFind(status, "KILL") >= 0) { m_lblKillStatus.Color(CLR_RED); m_bgStatus.BackColor(C'50,20,20'); }
      else { m_lblKillStatus.Color(CLR_GREEN); m_bgStatus.BackColor(CLR_PANEL); }
      
      m_lblConn.Description("UPLINK:  " + connStatus);
      m_lblPing.Description("LATENCY: " + IntegerToString(ping) + " ms");
      m_lblPing.Color(ping > 200 ? CLR_ORANGE : CLR_TEXT_DIM);
      
      // Intel
      m_lblRegime.Description("REGIME:  " + regime);
      if(regime == "TREND") m_lblRegime.Color(CLR_GREEN);
      else if(regime == "VOLATILE") m_lblRegime.Color(CLR_ORANGE);
      else m_lblRegime.Color(CLR_TEXT_MAIN);
      
      // Risk
      m_lblEquity.Description("EQUITY: $" + DoubleToString(equity, 2));
      m_lblBalance.Description("BALANCE: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
      m_lblDD.Description("DRAWDOWN: " + DoubleToString(dd, 2) + "%");
      m_lblDD.Color(dd > 5.0 ? CLR_RED : CLR_GREEN);
      m_lblVaR.Description("VaR (95%): " + DoubleToString(var, 2));
      m_lblRecov.Description(recoveryTxt);
      
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
         string txt = "";
         color clr = CLR_TEXT_DIM;
         
         if(i < count) 
         {
            txt = tradeRows[i];
            if(StringFind(txt, "$ -") >= 0) clr = CLR_RED;       // Loss
            else if(StringFind(txt, "$") >= 0) clr = CLR_GREEN;  // Profit
         }
         
         m_lblTrades[i].Description(txt);
         m_lblTrades[i].Color(clr);
      }
      ChartRedraw();
   }
   
   void Destroy()
   {
      ObjectsDeleteAll(ChartID(), "L_");
      ObjectsDeleteAll(ChartID(), "BG_");
   }

private:
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
   
   void CreateLabel(CChartObjectLabel &obj, string name, int x, int y, string text, int size, color clr, bool bold=false)
   {
      if(ObjectFind(ChartID(), name) >= 0) ObjectDelete(ChartID(), name);
      obj.Create(ChartID(), name, 0, x, y);
      obj.Description(text);
      obj.FontSize(size);
      obj.Color(clr);
      if(bold) obj.Font("Verdana Bold");
      else obj.Font("Verdana");
      obj.Corner(CORNER_LEFT_UPPER);
      obj.Selectable(false);
      obj.Z_Order(10);
   }
};

#endif
