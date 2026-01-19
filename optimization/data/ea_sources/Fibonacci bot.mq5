//+------------------------------------------------------------------+
//|                                                Fibonacci bot.mq5 |
//|                                  Copyright 2023, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#define  FIBO_OBJ "Fibo retracement"

#include <Trade/Trade.mqh>

input double lots = 0.1; 
input double RetracementLevel = 61.8;
input int SlPoints = 200;
input int TpPoints = 200;
input int ExpirationHours = 15;

int barsTotal;



//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   OnTick();
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   int bars = iBars(_Symbol,PERIOD_D1);
   if(barsTotal !=  bars && TimeCurrent() > StringToTime("00:05")){
   barsTotal = bars;
   
   ObjectDelete(0,FIBO_OBJ);
   
   double open = iOpen(_Symbol,PERIOD_D1,1);
   double close = iOpen(_Symbol,PERIOD_D1,1);
   
   double high = iHigh(_Symbol,PERIOD_D1,1);
   double low = iLow(_Symbol,PERIOD_D1,1);
   
   datetime timeStart = iTime(_Symbol,PERIOD_D1,1);
   datetime timeEnd = iTime(_Symbol,PERIOD_D1,0)-1;
   
   datetime expiration = iTime(_Symbol,PERIOD_D1,0) + ExpirationHours * PeriodSeconds(PERIOD_D1);
   
   if(close > open){
      ObjectCreate(0,FIBO_OBJ,OBJ_FIBO,0,timeStart,low,timeEnd,high);
      double entry = high - (high - low) * RetracementLevel / 100;
      
      entry = NormalizeDouble(entry,_Digits);      
      
      double sl = entry * SlPoints * _Point;
      sl = NormalizeDouble(sl,_Digits);
      
      double tp = entry * TpPoints * _Point;
      sl = NormalizeDouble(tp,_Digits);
      
      CTrade trade;
      if(trade.BuyLimit(lots,entry,_Symbol,sl,tp,ORDER_TIME_SPECIFIED,expiration)){
           Print(__FUNCTION__," > Buy order sent..."); 
      }
      
   }else{
       ObjectCreate(0,FIBO_OBJ,OBJ_FIBO,0,timeStart,high,timeEnd,low);
       double entry = high - (high - low) * RetracementLevel / 100;
      
      entry = NormalizeDouble(entry,_Digits);      
      
      double sl = entry * SlPoints * _Point;
      sl = NormalizeDouble(sl,_Digits);
      
      double tp = entry * TpPoints * _Point;
      sl = NormalizeDouble(tp,_Digits);
      
      CTrade trade;
      if(trade.BuyLimit(lots,entry,_Symbol,sl,tp,ORDER_TIME_SPECIFIED,expiration)){
        Print(__FUNCTION__," > Sell order sent..."); 
      }
      
   }


   ObjectSetInteger(0,FIBO_OBJ,OBJPROP_COLOR,clrBlack);
   
   for(int i = 0; ObjectGetInteger(0,FIBO_OBJ,OBJPROP_LEVELS); i++){
      ObjectSetInteger(0,FIBO_OBJ,OBJPROP_COLOR,i,clrBlack);
    }   
   
   
   
   
   }
  }

