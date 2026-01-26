//+------------------------------------------------------------------+
//|                                                 R_Drawdown.mqh   |
//|                                   Copyright 2026, ROUDO COMPANY  |
//|                                     https://roudo.com            |
//+------------------------------------------------------------------+
#property copyright "ROUDO"
#property link      "https://roudo.com"

//+------------------------------------------------------------------+
//| Clase de Control de Drawdown                                     |
//+------------------------------------------------------------------+
class CDrawdownManager
{
private:
   double daily_start_balance;
   double daily_peak_balance;
   datetime last_reset_date;
   bool drawdown_limit_hit;

   //--- Actualizar peak balance diario
   void UpdatePeakBalance()
   {
      double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(current_balance > daily_peak_balance) {
         daily_peak_balance = current_balance;
      }
   }

public:
   //--- Constructor
   CDrawdownManager() : drawdown_limit_hit(false)
   {
      daily_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      daily_peak_balance = daily_start_balance;
      last_reset_date = TimeCurrent();
   }

   //--- Calcular drawdown diario actual
   double GetCurrentDrawdown()
   {
      UpdatePeakBalance();

      double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);

      // Usar el menor entre balance y equity
      double current_value = MathMin(current_balance, current_equity);

      if(daily_peak_balance <= 0) return 0;

      double drawdown = ((daily_peak_balance - current_value) / daily_peak_balance) * 100.0;

      return MathMax(0, drawdown);
   }

   //--- Calcular drawdown desde inicio del día
   double GetDailyDrawdown()
   {
      if(daily_start_balance <= 0) return 0;

      double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double current_value = MathMin(current_balance, current_equity);

      double drawdown = ((daily_start_balance - current_value) / daily_start_balance) * 100.0;

      return drawdown;
   }

   //--- Verificar si se excedió el drawdown diario
   bool IsDrawdownExceeded()
   {
      double current_dd = GetCurrentDrawdown();

      if(current_dd >= MaxDailyDrawdown) {
         if(!drawdown_limit_hit) {
            Print("╔════════════════════════════════════════╗");
            Print("║  ⚠️ DRAWDOWN DIARIO EXCEDIDO           ║");
            Print("╠════════════════════════════════════════╣");
            Print("║  DD Actual: ", DoubleToString(current_dd, 2), "%");
            Print("║  DD Máximo: ", DoubleToString(MaxDailyDrawdown, 2), "%");
            Print("║  TRADING DETENIDO HASTA MAÑANA         ║");
            Print("╚════════════════════════════════════════╝");

            drawdown_limit_hit = true;

            if(StopOnDrawdownHit) {
               SendNotification("⚠️ ROUDO: Drawdown diario excedido (" +
                              DoubleToString(current_dd, 1) + "%). Trading detenido.");
            }
         }
         return true;
      }

      return false;
   }

   //--- Verificar drawdown por trade
   bool IsTradeDrawdownSafe()
   {
      double floating_loss = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(m_position.SelectByIndex(i)) {
            if(m_position.Symbol() == _Symbol && m_position.Magic() == MagicNumber_Hilo) {
               double profit = m_position.Profit();
               if(profit < 0) {
                  floating_loss += MathAbs(profit);
               }
            }
         }
      }

      double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(account_balance <= 0) return true;

      double trade_dd_percent = (floating_loss / account_balance) * 100.0;

      if(trade_dd_percent >= MaxDrawdownPerTrade) {
         Print("⚠️ Drawdown por trade alto: ", DoubleToString(trade_dd_percent, 2),
               "% (Máx: ", DoubleToString(MaxDrawdownPerTrade, 2), "%)");
         return false;
      }

      return true;
   }

   //--- Verificar si se puede continuar trading
   bool CanContinueTrading()
   {
      // Verificar drawdown diario
      if(IsDrawdownExceeded()) {
         return false;
      }

      return true;
   }

   //--- Reset diario
   void DailyReset()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      MqlDateTime last_dt;
      TimeToStruct(last_reset_date, last_dt);

      // Si cambió el día
      if(dt.day != last_dt.day || dt.mon != last_dt.mon || dt.year != last_dt.year) {
         Print("═══════════════════════════════════════");
         Print("  NUEVO DÍA - Reset de Drawdown");
         Print("  Balance inicial: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
         Print("═══════════════════════════════════════");

         daily_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
         daily_peak_balance = daily_start_balance;
         last_reset_date = TimeCurrent();
         drawdown_limit_hit = false;

         // Reset de otros managers
         g_breakeven.Reset();
         g_partial_tp.Reset();
      }
   }

   //--- Obtener información de drawdown
   string GetDrawdownInfo()
   {
      double current_dd = GetCurrentDrawdown();
      double daily_dd = GetDailyDrawdown();

      string info = "";
      info += "DD Actual: " + DoubleToString(current_dd, 2) + "% / " +
              DoubleToString(MaxDailyDrawdown, 1) + "%\n";

      // Barra de progreso
      int bar_length = 20;
      int filled = (int)((current_dd / MaxDailyDrawdown) * bar_length);
      filled = MathMin(filled, bar_length);

      string bar = "";
      for(int i = 0; i < filled; i++) bar += "█";
      for(int i = filled; i < bar_length; i++) bar += "░";

      info += bar;

      if(drawdown_limit_hit) {
         info += " ⚠️ LÍMITE ALCANZADO";
      }

      return info;
   }

   //--- Obtener balance inicial del día
   double GetDailyStartBalance() { return daily_start_balance; }

   //--- Verificar si límite fue alcanzado
   bool IsLimitHit() { return drawdown_limit_hit; }
};

//--- Instancia global
CDrawdownManager g_drawdown;
//+------------------------------------------------------------------+
