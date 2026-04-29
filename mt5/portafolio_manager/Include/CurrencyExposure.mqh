//+------------------------------------------------------------------+
//|                                            CurrencyExposure.mqh  |
//|  Tracks net currency exposure across all open positions.         |
//|  Prevents over-concentration in a single currency (e.g., all    |
//|  trades correlated through USD or JPY).                          |
//|                                                                  |
//|  Implementation: lightweight — scans positions directly each     |
//|  bar. No GlobalVariables needed (avoids cross-EA interference).  |
//+------------------------------------------------------------------+
#ifndef CURRENCY_EXPOSURE_MQH
#define CURRENCY_EXPOSURE_MQH

#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| Supported currencies for exposure tracking                        |
//+------------------------------------------------------------------+
enum ENUM_CURRENCY
{
   CUR_USD = 0,
   CUR_EUR = 1,
   CUR_GBP = 2,
   CUR_JPY = 3,
   CUR_CAD = 4,
   CUR_CHF = 5,
   CUR_AUD = 6,
   CUR_NZD = 7,
   CUR_XAU = 8,
   CUR_COUNT = 9
};

//+------------------------------------------------------------------+
//| Currency Exposure Tracker                                         |
//+------------------------------------------------------------------+
class CCurrencyExposure
{
private:
   double   m_exposure[CUR_COUNT]; // net lots per currency (+buy, -sell)
   double   m_absExposure[CUR_COUNT]; // absolute lots (for max check)
   int      m_magicNumber;
   bool     m_initialized;

public:
   CCurrencyExposure()
   {
      m_initialized = false;
      m_magicNumber = 0;
      ArrayInitialize(m_exposure, 0);
      ArrayInitialize(m_absExposure, 0);
   }

   void Init(int magicNumber)
   {
      m_magicNumber = magicNumber;
      m_initialized = true;
      RebuildFromPositions();
   }

   //+------------------------------------------------------------------+
   //| Rebuild full exposure from all open positions                     |
   //| Call once per bar                                                 |
   //+------------------------------------------------------------------+
   void RebuildFromPositions()
   {
      ArrayInitialize(m_exposure, 0);
      ArrayInitialize(m_absExposure, 0);

      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(m_magicNumber != 0 && PositionGetInteger(POSITION_MAGIC) != m_magicNumber) continue;

         string sym     = PositionGetString(POSITION_SYMBOL);
         double lots    = PositionGetDouble(POSITION_VOLUME);
         int    posType = (int)PositionGetInteger(POSITION_TYPE); // 0=buy, 1=sell

         int baseCur  = _GetCurrencyIndex(_GetBase(sym));
         int quoteCur = _GetCurrencyIndex(_GetQuote(sym));

         double signedLots = (posType == POSITION_TYPE_BUY) ? lots : -lots;

         if(baseCur  >= 0) { m_exposure[baseCur]  += signedLots; m_absExposure[baseCur]  += lots; }
         if(quoteCur >= 0) { m_exposure[quoteCur] -= signedLots; m_absExposure[quoteCur] += lots; }
      }
   }

   //+------------------------------------------------------------------+
   //| Check if adding a new trade is safe (won't breach max exposure)  |
   //| symbol  : the proposed trade's symbol                            |
   //| dir     : ORDER_TYPE_BUY=0, ORDER_TYPE_SELL=1                   |
   //| lots    : proposed lot size                                      |
   //| maxLots : max absolute lots allowed per currency                 |
   //+------------------------------------------------------------------+
   bool IsSafe(string symbol, int orderType, double lots, double maxLots)
   {
      if(!m_initialized || maxLots <= 0) return true;

      int baseCur  = _GetCurrencyIndex(_GetBase(symbol));
      int quoteCur = _GetCurrencyIndex(_GetQuote(symbol));

      // For a BUY: base currency goes long, quote goes short
      // For a SELL: base currency goes short, quote goes long
      double baseAdd  = (orderType == ORDER_TYPE_BUY) ?  lots : -lots;
      double quoteAdd = (orderType == ORDER_TYPE_BUY) ? -lots :  lots;

      // Check absolute exposure after adding
      if(baseCur >= 0)
      {
         double newAbsBase = m_absExposure[baseCur] + lots;
         if(newAbsBase > maxLots) return false;
      }
      if(quoteCur >= 0)
      {
         double newAbsQuote = m_absExposure[quoteCur] + lots;
         if(newAbsQuote > maxLots) return false;
      }

      return true;
   }

   // Get current absolute exposure for a currency by string (e.g. "USD")
   double GetAbsExposure(string currency)
   {
      int idx = _GetCurrencyIndex(currency);
      if(idx < 0) return 0;
      return m_absExposure[idx];
   }

   // Net signed exposure (+ = net long, - = net short)
   double GetNetExposure(string currency)
   {
      int idx = _GetCurrencyIndex(currency);
      if(idx < 0) return 0;
      return m_exposure[idx];
   }

   // Dashboard summary: top 3 most exposed currencies
   string GetStatus(double maxLots)
   {
      string result = "CurExp: ";
      string curNames[CUR_COUNT] = {"USD","EUR","GBP","JPY","CAD","CHF","AUD","NZD","XAU"};
      for(int i = 0; i < CUR_COUNT; i++)
      {
         if(m_absExposure[i] < 0.01) continue;
         double pct = (maxLots > 0) ? m_absExposure[i] / maxLots * 100 : 0;
         result += curNames[i] + "=" + DoubleToString(m_absExposure[i], 2) +
                   "(" + DoubleToString(pct, 0) + "%) ";
      }
      return result;
   }

private:
   string _GetBase(string symbol)
   {
      if(StringLen(symbol) < 6) return "";
      // Handle XAUUSD specially
      if(symbol == "XAUUSD") return "XAU";
      return StringSubstr(symbol, 0, 3);
   }

   string _GetQuote(string symbol)
   {
      if(StringLen(symbol) < 6) return "";
      if(symbol == "XAUUSD") return "USD";
      return StringSubstr(symbol, 3, 3);
   }

   int _GetCurrencyIndex(string cur)
   {
      if(cur == "USD") return CUR_USD;
      if(cur == "EUR") return CUR_EUR;
      if(cur == "GBP") return CUR_GBP;
      if(cur == "JPY") return CUR_JPY;
      if(cur == "CAD") return CUR_CAD;
      if(cur == "CHF") return CUR_CHF;
      if(cur == "AUD") return CUR_AUD;
      if(cur == "NZD") return CUR_NZD;
      if(cur == "XAU") return CUR_XAU;
      return -1;
   }
};

#endif
