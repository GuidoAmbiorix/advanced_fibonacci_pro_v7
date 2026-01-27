//+------------------------------------------------------------------+
//|                                              SmartExecution.mqh  |
//|                                  Copyright 2026, Guido Ambiorix  |
//|                                     https://github.com/GuidoAmbiorix |
//+------------------------------------------------------------------+
#ifndef SMART_EXECUTION_MQH
#define SMART_EXECUTION_MQH

#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property strict

#include <Trade\Trade.mqh>
#include "LiquidityGuard.mqh"
#include "PortfolioGlobals.mqh"

//+------------------------------------------------------------------+
//| SMART EXECUTION MODULE                                            |
//| Responsibility: "Excute like an Institution"                     |
//| Features: TWAP, Iceberg, Slippage Control, Pre-Checks            |
//+------------------------------------------------------------------+
class CSmartExecution
{
private:
   CTrade         m_trade;
   CLiquidityGuard *m_guard;
   int            m_slippage;
   
public:
   CSmartExecution() : m_slippage(10), m_guard(NULL) {}
   
   void Init(CLiquidityGuard *guard, int baseSlippage)
   {
      m_guard = guard;
      m_slippage = baseSlippage;
      m_trade.SetDeviationInPoints(m_slippage);
      m_trade.SetTypeFilling(ORDER_FILLING_FOK); 
   }

   //+------------------------------------------------------------------+
   //| Execute Smart Order                                               |
   //+------------------------------------------------------------------+
   bool ExecuteOrder(string symbol, ENUM_ORDER_TYPE type, double volume, double price, double sl, double tp, string comment)
   {
      // 0. PRE-FLIGHT CHECKS
      if(!PreTradeValidation(symbol, volume, type))
      {
         Print("❌ SmartExec: Pre-Check Failed for ", symbol);
         return false;
      }
      
      // 1. Liquidity Check
      if(m_guard != NULL)
      {
         if(!m_guard.IsSafe(symbol))
         {
            Print("💧 SmartExec: ABORTING Trade on ", symbol, ". Liquidity Unsafe.");
            return false;
         }
      }
      
      // 2. Large Order Handling (Iceberg)
      if(volume > 5.0)
      {
         return ExecuteIceberg(symbol, type, volume, price, sl, tp, comment);
      }
      
      // 3. Normal Execution
      AdjustSlippage(symbol);
      
      if(!m_trade.PositionOpen(symbol, type, volume, price, sl, tp, comment))
      {
         Print("💥 Trade Failed: ", m_trade.ResultRetcodeDescription());
         return false;
      }
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Pre-Trade Validation                                              |
   //+------------------------------------------------------------------+
   bool PreTradeValidation(string symbol, double volume, ENUM_ORDER_TYPE type)
   {
      // 1. Check Trading allowed
      if((ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED) return false;
      
      // 2. Check Volume Limits
      double minVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      if(volume < minVol || volume > maxVol)
      {
         Print("⚠️ Invalid Volume: ", volume, " (Min: ", minVol, " Max: ", maxVol, ")");
         return false;
      }
      
      // 3. Margin Check
      double marginRequired;
      if(!OrderCalcMargin(type, symbol, volume, SymbolInfoDouble(symbol, SYMBOL_ASK), marginRequired))
      {
         // Could not calc margin
         return false;
      }
      
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(marginRequired > freeMargin * 0.9) // Leave 10% buffer
      {
         Print("⚠️ Insufficient Margin! Req: ", marginRequired, " Free: ", freeMargin);
         return false;
      }
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Iceberg Execution                                                 |
   //+------------------------------------------------------------------+
   bool ExecuteIceberg(string symbol, ENUM_ORDER_TYPE type, double totalVolume, double price, double sl, double tp, string comment)
   {
      Print("🧊 SmartExec: ICEBERG ", totalVolume, " lots");
      
      double clipSize = 1.0; 
      int clips = (int)MathCeil(totalVolume / clipSize);
      double remaining = totalVolume;
      
      bool success = true;
      
      for(int i = 0; i < clips; i++)
      {
         double currentRaw = MathMin(remaining, clipSize);
         double currentVol = NormalizeDouble(currentRaw, 2); 
         
         if(currentVol <= 0) break;
         
         if(i > 0)
         {
             int delay = 100 + MathRand() % 900;
             Sleep(delay);
         }
         
         double execPrice = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
         
         if(!m_trade.PositionOpen(symbol, type, currentVol, execPrice, sl, tp, comment + "_Ice_" + IntegerToString(i+1)))
         {
            success = false;
         }
         
         remaining -= currentVol;
      }
      
      return success;
   }
   
   //+------------------------------------------------------------------+
   //| Adjust Slippage based on Volatility                               |
   //+------------------------------------------------------------------+
   void AdjustSlippage(string symbol)
   {
      if(GlobalVariableGet(GV_MARKET_REGIME) == REGIME_VOLATILE)
         m_trade.SetDeviationInPoints(m_slippage * 2);
      else
         m_trade.SetDeviationInPoints(m_slippage);
   }
};

#endif
