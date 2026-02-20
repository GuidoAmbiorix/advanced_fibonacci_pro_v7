//+------------------------------------------------------------------+
//|                                          Master_Confluence.mq5 |
//|          Master Confluence - Unified Trading Signal Indicator     |
//|                                  Copyright 2026, Guido Ambiorix   |
//+------------------------------------------------------------------+
#property copyright "Guido Ambiorix"
#property link      "https://github.com/GuidoAmbiorix"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 12
#property indicator_plots   0  // Data only

//--- Input parameters - Module toggles
input bool InpUseSMC = true;                    // Use SMC Analysis
input bool InpUseVolume = true;                 // Use Volume Analysis
input bool InpUseMTF = true;                    // Use MTF Analysis
input bool InpUseICT = true;                    // Use ICT Concepts
input bool InpUseDivergence = true;             // Use Divergence
input bool InpUseSession = false;               // Use Session Optimizer (Metals only)

//--- Input parameters - SMC settings
input int InpSMC_SwingLookback = 20;            // SMC Swing Lookback
input double InpSMC_MinImpulseATR = 2.0;        // SMC Min Impulse ATR
input double InpSMC_MinFVG_ATR = 0.5;           // SMC Min FVG ATR

//--- Input parameters - Volume settings
input int InpRVOL_Lookback = 20;                // RVOL Lookback Days
input int InpMF_Period = 5;                     // Money Flow Period

//--- Input parameters - MTF settings
input ENUM_TIMEFRAMES InpHTF = PERIOD_H4;       // HTF Period
input ENUM_TIMEFRAMES InpMTF = PERIOD_H1;       // MTF Period
input ENUM_TIMEFRAMES InpLTF = PERIOD_M15;      // LTF Period

//--- Input parameters - Other
input int InpRSIPeriod = 14;                    // RSI Period
input int InpBrokerUTCOffset = 2;               // Broker UTC Offset

//--- Indicator buffers
double BufferSMC[];              // Buffer 0: SMC Combined (0-4.5)
double BufferVolume[];           // Buffer 1: Volume Score (0-4.0)
double BufferMTF[];              // Buffer 2: MTF Score (0-2.0)
double BufferICT[];              // Buffer 3: ICT Score (0-6.0)
double BufferDivergence[];       // Buffer 4: Divergence (0-2.0)
double BufferSession[];          // Buffer 5: Session Score (0-3.0)
double BufferReserved1[];        // Buffer 6: Reserved
double BufferReserved2[];        // Buffer 7: Reserved
double BufferTotalBuy[];         // Buffer 8: Total Buy Score (0-30.0)
double BufferTotalSell[];        // Buffer 9: Total Sell Score (0-30.0)
double BufferScoreDelta[];       // Buffer 10: Score Delta
double BufferSignalQuality[];    // Buffer 11: Signal Quality (0-3)

//--- Custom indicator handles
int hSMC = INVALID_HANDLE;
int hVolume = INVALID_HANDLE;
int hMTF = INVALID_HANDLE;
int hICT = INVALID_HANDLE;
int hDivergence = INVALID_HANDLE;
int hSession = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Custom indicator initialization                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Indicator buffers mapping
   SetIndexBuffer(0, BufferSMC, INDICATOR_DATA);
   SetIndexBuffer(1, BufferVolume, INDICATOR_DATA);
   SetIndexBuffer(2, BufferMTF, INDICATOR_DATA);
   SetIndexBuffer(3, BufferICT, INDICATOR_DATA);
   SetIndexBuffer(4, BufferDivergence, INDICATOR_DATA);
   SetIndexBuffer(5, BufferSession, INDICATOR_DATA);
   SetIndexBuffer(6, BufferReserved1, INDICATOR_DATA);
   SetIndexBuffer(7, BufferReserved2, INDICATOR_DATA);
   SetIndexBuffer(8, BufferTotalBuy, INDICATOR_DATA);
   SetIndexBuffer(9, BufferTotalSell, INDICATOR_DATA);
   SetIndexBuffer(10, BufferScoreDelta, INDICATOR_DATA);
   SetIndexBuffer(11, BufferSignalQuality, INDICATOR_DATA);

   //--- Initialize arrays as series
   ArraySetAsSeries(BufferSMC, true);
   ArraySetAsSeries(BufferVolume, true);
   ArraySetAsSeries(BufferMTF, true);
   ArraySetAsSeries(BufferICT, true);
   ArraySetAsSeries(BufferDivergence, true);
   ArraySetAsSeries(BufferSession, true);
   ArraySetAsSeries(BufferReserved1, true);
   ArraySetAsSeries(BufferReserved2, true);
   ArraySetAsSeries(BufferTotalBuy, true);
   ArraySetAsSeries(BufferTotalSell, true);
   ArraySetAsSeries(BufferScoreDelta, true);
   ArraySetAsSeries(BufferSignalQuality, true);

   //--- Create indicator handles based on toggles
   if(InpUseSMC)
   {
      hSMC = iCustom(_Symbol, PERIOD_CURRENT, "Indicators\\SMC_Confluence",
                     InpSMC_SwingLookback, InpSMC_MinImpulseATR, InpSMC_MinFVG_ATR, 5, 10);
      if(hSMC == INVALID_HANDLE) Print("Warning: SMC_Confluence failed to load");
   }

   if(InpUseVolume)
   {
      hVolume = iCustom(_Symbol, PERIOD_CURRENT, "Indicators\\Volume_Confluence",
                        InpRVOL_Lookback, InpMF_Period);
      if(hVolume == INVALID_HANDLE) Print("Warning: Volume_Confluence failed to load");
   }

   if(InpUseMTF)
   {
      hMTF = iCustom(_Symbol, PERIOD_CURRENT, "Indicators\\MTF_Confluence",
                     InpHTF, InpMTF, InpLTF, 50, InpRSIPeriod);
      if(hMTF == INVALID_HANDLE) Print("Warning: MTF_Confluence failed to load");
   }

   if(InpUseICT)
   {
      hICT = iCustom(_Symbol, PERIOD_CURRENT, "Indicators\\ICT_Advanced");
      if(hICT == INVALID_HANDLE) Print("Warning: ICT_Advanced failed to load");
   }

   if(InpUseDivergence)
   {
      hDivergence = iCustom(_Symbol, PERIOD_CURRENT, "Indicators\\Divergence",
                            InpRSIPeriod, 10);
      if(hDivergence == INVALID_HANDLE) Print("Warning: Divergence failed to load");
   }

   if(InpUseSession)
   {
      hSession = iCustom(_Symbol, PERIOD_CURRENT, "Indicators\\Session_Optimizer",
                         InpBrokerUTCOffset);
      if(hSession == INVALID_HANDLE) Print("Warning: Session_Optimizer failed to load");
   }

   IndicatorSetString(INDICATOR_SHORTNAME, "Master Confluence");
   IndicatorSetInteger(INDICATOR_DIGITS, 2);

   Print("Master_Confluence indicator initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hSMC != INVALID_HANDLE) IndicatorRelease(hSMC);
   if(hVolume != INVALID_HANDLE) IndicatorRelease(hVolume);
   if(hMTF != INVALID_HANDLE) IndicatorRelease(hMTF);
   if(hICT != INVALID_HANDLE) IndicatorRelease(hICT);
   if(hDivergence != INVALID_HANDLE) IndicatorRelease(hDivergence);
   if(hSession != INVALID_HANDLE) IndicatorRelease(hSession);

   Print("Master_Confluence indicator deinitialized");
}

//+------------------------------------------------------------------+
//| Custom indicator iteration                                       |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   int currentBar = 0;
   double buf[1];

   //--- Initialize component scores
   double smcScore = 0, volScore = 0, mtfScore = 0, ictScore = 0, divScore = 0, sessScore = 0;

   //--- Get SMC score (combined SMC score from buffer 4)
   if(InpUseSMC && hSMC != INVALID_HANDLE)
   {
      if(CopyBuffer(hSMC, 4, 1, 1, buf) > 0)
         smcScore = buf[0];
   }
   BufferSMC[currentBar] = smcScore;

   //--- Get Volume score (use buy score for bullish, sell for bearish direction)
   if(InpUseVolume && hVolume != INVALID_HANDLE)
   {
      if(CopyBuffer(hVolume, 2, 0, 1, buf) > 0)  // Buffer 2 = Buy Score
         volScore = buf[0];
   }
   BufferVolume[currentBar] = volScore;

   //--- Get MTF score (use buy score)
   if(InpUseMTF && hMTF != INVALID_HANDLE)
   {
      if(CopyBuffer(hMTF, 4, 0, 1, buf) > 0)  // Buffer 4 = Buy Score
         mtfScore = buf[0];
   }
   BufferMTF[currentBar] = mtfScore;

   //--- Get ICT score (combined score)
   if(InpUseICT && hICT != INVALID_HANDLE)
   {
      if(CopyBuffer(hICT, 3, 0, 1, buf) > 0)  // Buffer 3 = Combined Score
         ictScore = buf[0];
   }
   BufferICT[currentBar] = ictScore;

   //--- Get Divergence score (combined score)
   if(InpUseDivergence && hDivergence != INVALID_HANDLE)
   {
      if(CopyBuffer(hDivergence, 2, 0, 1, buf) > 0)  // Buffer 2 = Combined Score
         divScore = buf[0];
   }
   BufferDivergence[currentBar] = divScore;

   //--- Get Session score (metals score)
   if(InpUseSession && hSession != INVALID_HANDLE)
   {
      if(CopyBuffer(hSession, 2, 0, 1, buf) > 0)  // Buffer 2 = Metals Score
         sessScore = buf[0];
   }
   BufferSession[currentBar] = sessScore;

   //--- Calculate total scores
   // For simplicity, we'll use absolute values for bullish bias
   double totalBuy = MathAbs(smcScore) + volScore + mtfScore + MathAbs(ictScore) +
                     MathAbs(divScore) + sessScore;

   // For sell, we'd need to recalculate with negative biases
   // Simplified: just use inverse of buy score for this example
   double totalSell = totalBuy * 0.5;  // Placeholder

   BufferTotalBuy[currentBar] = totalBuy;
   BufferTotalSell[currentBar] = totalSell;
   BufferScoreDelta[currentBar] = totalBuy - totalSell;

   //--- Calculate signal quality (0-3)
   double quality = 0;
   if(totalBuy >= 15.0) quality = 3;  // Elite
   else if(totalBuy >= 12.0) quality = 2;  // Strong
   else if(totalBuy >= 8.0) quality = 1;  // Good

   BufferSignalQuality[currentBar] = quality;

   return rates_total;
}
//+------------------------------------------------------------------+
