//+------------------------------------------------------------------+
//|                                          Portfolio_Governor.mq5  |
//|          🧠 CENTRAL BRAIN - Multi-Symbol Risk Controller         |
//|             Manages: DD, Exposure, PF, Correlation Groups        |
//+------------------------------------------------------------------+
#property copyright "Portfolio Governor"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "1.00"
#property description "🧠 Portfolio Governor: Central Risk Brain"
#property description "Run on ONE chart only. Controls all Symbol Engines."
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include "Include\PortfolioGlobals.mqh"

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

input group "═══════ PORTFOLIO LIMITS ═══════"
input double InpMaxPortfolioRisk = 2.0;        // Max Total Portfolio Risk (%)
input double InpMaxSymbolRisk = 0.6;           // Max Risk Per Symbol (%)
input double InpMaxGroupRisk = 1.0;            // Max Risk Per Correlation Group (%)

input group "═══════ DRAWDOWN GOVERNOR ═══════"
input double InpDD_Normal = 3.0;               // DD Level: Normal Trading (%)
input double InpDD_Reduced = 5.0;              // DD Level: Reduced Risk (%)
input double InpDD_Pause = 8.0;                // DD Level: Pause Trading (%)
input double InpDD_ReducedMult = 0.5;          // Risk Multiplier when DD > Normal

input group "═══════ ROLLING PF GOVERNOR ═══════"
input int    InpRollingTrades = 30;            // Rolling Window (trades)
input double InpPF_Normal = 1.8;               // PF Level: Normal Trading
input double InpPF_Reduced = 1.2;              // PF Level: Reduced Risk
input double InpPF_Pause = 1.0;                // PF Level: Pause Trading
input double InpPF_ReducedMult = 0.7;          // Risk Mult when PF < Normal

input group "═══════ MAGIC NUMBER RANGE ═══════"
input int    InpMagicBase = 100000;            // Magic Number Base
input int    InpMagicRange = 999;              // Magic Number Range (Base to Base+Range)

input group "═══════ UPDATE FREQUENCY ═══════"
input int    InpUpdateSeconds = 5;             // Update Interval (seconds)

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CPositionInfo position;
CAccountInfo  account;

double g_peakEquity = 0;
datetime g_lastUpdate = 0;

// Trade history for rolling PF
double g_tradeResults[];  // Store last N trade results
int g_tradeCount = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize GlobalVariables
   GlobalVariableSet(GV_GOVERNOR_ACTIVE, 1);
   GlobalVariableSet(GV_TRADING_ENABLED, 1);
   GlobalVariableSet(GV_RISK_MULTIPLIER, 1.0);
   GlobalVariableSet(GV_TOTAL_EXPOSURE, 0);
   GlobalVariableSet(GV_CURRENT_DD, 0);
   GlobalVariableSet(GV_ROLLING_PF, 2.0);
   GlobalVariableSet(GV_PEAK_EQUITY, account.Equity());
   GlobalVariableSet(GV_LAST_UPDATE, (double)TimeCurrent());
   
   // Initialize group risks
   GlobalVariableSet(GV_GROUP_USD_RISK, 0);
   GlobalVariableSet(GV_GROUP_JPY_RISK, 0);
   GlobalVariableSet(GV_GROUP_GBP_RISK, 0);
   GlobalVariableSet(GV_GROUP_METALS_RISK, 0);
   GlobalVariableSet(GV_GROUP_INDICES_RISK, 0);
   
   g_peakEquity = account.Equity();
   ArrayResize(g_tradeResults, InpRollingTrades);
   ArrayInitialize(g_tradeResults, 0);
   
   Print("═══════════════════════════════════════════════════════════");
   Print("  🧠 PORTFOLIO GOVERNOR v1.0 ACTIVATED");
   Print("═══════════════════════════════════════════════════════════");
   Print("  📊 Max Portfolio Risk: ", InpMaxPortfolioRisk, "%");
   Print("  📊 Max Symbol Risk: ", InpMaxSymbolRisk, "%");
   Print("  📊 Max Group Risk: ", InpMaxGroupRisk, "%");
   Print("  📉 DD Pause Level: ", InpDD_Pause, "%");
   Print("  📈 PF Pause Level: < ", InpPF_Pause);
   Print("═══════════════════════════════════════════════════════════");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Mark governor as inactive
   GlobalVariableSet(GV_GOVERNOR_ACTIVE, 0);
   Comment("");
   Print("🧠 Portfolio Governor DEACTIVATED");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Throttle updates
   if(TimeCurrent() - g_lastUpdate < InpUpdateSeconds) return;
   g_lastUpdate = TimeCurrent();
   
   // 1. Calculate portfolio metrics
   CalculatePortfolioMetrics();
   
   // 2. Update risk multiplier
   UpdateRiskMultiplier();
   
   // 3. Update trading enabled status
   UpdateTradingStatus();
   
   // 4. Update dashboard
   UpdateDashboard();
   
   // 5. Publish update timestamp
   GlobalVariableSet(GV_LAST_UPDATE, (double)TimeCurrent());
}

//+------------------------------------------------------------------+
//| Trade event - capture closed trades for PF calculation            |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Check for newly closed trades
   static int lastHistoryCount = 0;
   int currentCount = HistoryDealsTotal();
   
   if(currentCount > lastHistoryCount)
   {
      // Process new closed trades
      HistorySelect(0, TimeCurrent());
      
      for(int i = lastHistoryCount; i < currentCount; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket > 0)
         {
            long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
            long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
            
            // Check if it's our trade and an exit
            if(magic >= InpMagicBase && magic <= InpMagicBase + InpMagicRange)
            {
               if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
               {
                  double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
                  AddTradeResult(profit);
               }
            }
         }
      }
      lastHistoryCount = currentCount;
   }
}

//+------------------------------------------------------------------+
//| Add trade result to rolling window                                |
//+------------------------------------------------------------------+
void AddTradeResult(double profit)
{
   // Shift array
   for(int i = InpRollingTrades - 1; i > 0; i--)
   {
      g_tradeResults[i] = g_tradeResults[i-1];
   }
   g_tradeResults[0] = profit;
   g_tradeCount++;
   
   // Recalculate rolling PF
   CalculateRollingPF();
}

//+------------------------------------------------------------------+
//| Calculate rolling profit factor                                   |
//+------------------------------------------------------------------+
void CalculateRollingPF()
{
   double grossProfit = 0;
   double grossLoss = 0;
   
   int count = MathMin(g_tradeCount, InpRollingTrades);
   
   for(int i = 0; i < count; i++)
   {
      if(g_tradeResults[i] > 0)
         grossProfit += g_tradeResults[i];
      else
         grossLoss += MathAbs(g_tradeResults[i]);
   }
   
   double pf = (grossLoss > 0) ? (grossProfit / grossLoss) : 2.0;
   GlobalVariableSet(GV_ROLLING_PF, pf);
}

//+------------------------------------------------------------------+
//| Calculate portfolio metrics                                       |
//+------------------------------------------------------------------+
void CalculatePortfolioMetrics()
{
   double equity = account.Equity();
   double totalExposure = 0;
   
   // Reset group risks
   double groupRisks[6] = {0, 0, 0, 0, 0, 0};
   
   // Scan all positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         long magic = position.Magic();
         
         // Check if it's our trade
         if(magic >= InpMagicBase && magic <= InpMagicBase + InpMagicRange)
         {
            string sym = position.Symbol();
            double openPrice = position.PriceOpen();
            double sl = position.StopLoss();
            double volume = position.Volume();
            
            // Calculate risk for this position
            double riskPoints = MathAbs(openPrice - sl);
            double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
            double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
            
            double riskMoney = 0;
            if(tickSize > 0)
               riskMoney = (riskPoints / tickSize) * tickValue * volume;
            
            double riskPercent = (equity > 0) ? (riskMoney / equity) * 100.0 : 0;
            
            totalExposure += riskPercent;
            
            // Add to correlation group
            ENUM_CORR_GROUP group = GetCorrelationGroup(sym);
            groupRisks[(int)group] += riskPercent;
         }
      }
   }
   
   // Update GlobalVariables
   GlobalVariableSet(GV_TOTAL_EXPOSURE, totalExposure);
   GlobalVariableSet(GV_GROUP_USD_RISK, groupRisks[0]);
   GlobalVariableSet(GV_GROUP_JPY_RISK, groupRisks[1]);
   GlobalVariableSet(GV_GROUP_GBP_RISK, groupRisks[2]);
   GlobalVariableSet(GV_GROUP_METALS_RISK, groupRisks[3]);
   GlobalVariableSet(GV_GROUP_INDICES_RISK, groupRisks[4]);
   
   // Calculate drawdown
   if(equity > g_peakEquity)
   {
      g_peakEquity = equity;
      GlobalVariableSet(GV_PEAK_EQUITY, g_peakEquity);
   }
   
   double dd = (g_peakEquity > 0) ? ((g_peakEquity - equity) / g_peakEquity) * 100.0 : 0;
   GlobalVariableSet(GV_CURRENT_DD, dd);
}

//+------------------------------------------------------------------+
//| Update risk multiplier based on DD and PF                         |
//+------------------------------------------------------------------+
void UpdateRiskMultiplier()
{
   double dd = GlobalVariableGet(GV_CURRENT_DD);
   double pf = GlobalVariableGet(GV_ROLLING_PF);
   
   double mult = 1.0;
   
   // DD-based reduction
   if(dd >= InpDD_Reduced)
      mult = MathMin(mult, InpDD_ReducedMult);
   else if(dd >= InpDD_Normal)
      mult = MathMin(mult, 0.75);
   
   // PF-based reduction
   if(pf < InpPF_Normal && pf >= InpPF_Reduced)
      mult = MathMin(mult, InpPF_ReducedMult);
   else if(pf < InpPF_Reduced && pf >= InpPF_Pause)
      mult = MathMin(mult, 0.4);
   
   GlobalVariableSet(GV_RISK_MULTIPLIER, mult);
}

//+------------------------------------------------------------------+
//| Update trading enabled status                                     |
//+------------------------------------------------------------------+
void UpdateTradingStatus()
{
   double dd = GlobalVariableGet(GV_CURRENT_DD);
   double pf = GlobalVariableGet(GV_ROLLING_PF);
   
   bool enabled = true;
   
   // Pause on extreme DD
   if(dd >= InpDD_Pause)
      enabled = false;
   
   // Pause on very bad PF
   if(pf < InpPF_Pause && g_tradeCount >= 20) // Need enough trades
      enabled = false;
   
   GlobalVariableSet(GV_TRADING_ENABLED, enabled ? 1 : 0);
}

//+------------------------------------------------------------------+
//| Check if trade request is allowed                                 |
//+------------------------------------------------------------------+
bool CanOpenTrade(string symbol, double requestedRisk, double &approvedRisk)
{
   // Check if trading enabled
   if(GlobalVariableGet(GV_TRADING_ENABLED) != 1)
   {
      approvedRisk = 0;
      return false;
   }
   
   double totalExposure = GlobalVariableGet(GV_TOTAL_EXPOSURE);
   double riskMult = GlobalVariableGet(GV_RISK_MULTIPLIER);
   
   // Apply risk multiplier
   double scaledRisk = requestedRisk * riskMult;
   
   // Check portfolio limit
   if(totalExposure + scaledRisk > InpMaxPortfolioRisk)
   {
      scaledRisk = MathMax(0, InpMaxPortfolioRisk - totalExposure);
   }
   
   // Check symbol limit
   scaledRisk = MathMin(scaledRisk, InpMaxSymbolRisk);
   
   // Check group limit
   ENUM_CORR_GROUP group = GetCorrelationGroup(symbol);
   string gvKey = GetGroupGVKey(group);
   if(gvKey != "")
   {
      double groupRisk = GlobalVariableGet(gvKey);
      if(groupRisk + scaledRisk > InpMaxGroupRisk)
      {
         scaledRisk = MathMax(0, InpMaxGroupRisk - groupRisk);
      }
   }
   
   approvedRisk = scaledRisk;
   return (scaledRisk > 0.05); // Minimum viable risk
}

//+------------------------------------------------------------------+
//| Dashboard                                                         |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   double dd = GlobalVariableGet(GV_CURRENT_DD);
   double pf = GlobalVariableGet(GV_ROLLING_PF);
   double exposure = GlobalVariableGet(GV_TOTAL_EXPOSURE);
   double riskMult = GlobalVariableGet(GV_RISK_MULTIPLIER);
   bool enabled = GlobalVariableGet(GV_TRADING_ENABLED) == 1;
   
   string status = enabled ? "🟢 ACTIVE" : "🔴 PAUSED";
   string ddColor = (dd < InpDD_Normal) ? "🟢" : ((dd < InpDD_Pause) ? "🟡" : "🔴");
   string pfColor = (pf >= InpPF_Normal) ? "🟢" : ((pf >= InpPF_Pause) ? "🟡" : "🔴");
   
   string text = "═══════════════════════════════════════════\n";
   text += "  🧠 PORTFOLIO GOVERNOR v1.0\n";
   text += "═══════════════════════════════════════════\n";
   text += "Status: " + status + "\n";
   text += "───────────────────────────────────────────\n";
   text += "Equity: $" + DoubleToString(account.Equity(), 2) + "\n";
   text += ddColor + " DD: " + DoubleToString(dd, 2) + "% (Pause: " + DoubleToString(InpDD_Pause, 1) + "%)\n";
   text += pfColor + " PF: " + DoubleToString(pf, 2) + " (Last " + IntegerToString(MathMin(g_tradeCount, InpRollingTrades)) + " trades)\n";
   text += "───────────────────────────────────────────\n";
   text += "📊 Exposure: " + DoubleToString(exposure, 2) + "% / " + DoubleToString(InpMaxPortfolioRisk, 1) + "%\n";
   text += "⚖️ Risk Mult: " + DoubleToString(riskMult * 100, 0) + "%\n";
   text += "───────────────────────────────────────────\n";
   text += "GROUP EXPOSURE:\n";
   text += "  USD: " + DoubleToString(GlobalVariableGet(GV_GROUP_USD_RISK), 2) + "%\n";
   text += "  JPY: " + DoubleToString(GlobalVariableGet(GV_GROUP_JPY_RISK), 2) + "%\n";
   text += "  GBP: " + DoubleToString(GlobalVariableGet(GV_GROUP_GBP_RISK), 2) + "%\n";
   text += "  Metals: " + DoubleToString(GlobalVariableGet(GV_GROUP_METALS_RISK), 2) + "%\n";
   text += "  Indices: " + DoubleToString(GlobalVariableGet(GV_GROUP_INDICES_RISK), 2) + "%\n";
   text += "═══════════════════════════════════════════\n";
   
   Comment(text);
}
//+------------------------------------------------------------------+
