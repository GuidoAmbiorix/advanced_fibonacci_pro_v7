import rpyc
import pandas as pd
import numpy as np
import time
import traceback
from typing import Dict, Optional, List
from datetime import datetime
import datetime as dt_module

class PythonBacktester:
    def __init__(self, host='localhost', port=18812):
        self.host = host
        self.port = port
        self.conn = None
        self.mt5 = None
        self.connected = False
        
    def connect(self) -> bool:
        if self.connected: 
            return True
            
        try:
            # Try connecting multiple times
            for i in range(3):
                try:
                    self.conn = rpyc.classic.connect(self.host, self.port)
                    self.mt5 = self.conn.modules.MetaTrader5
                    
                    if not self.mt5.initialize():
                        print(f"❌ MT5 Initialize Failed: {self.mt5.last_error()}")
                        return False

                    self.connected = True
                    print("✅ Connected to MT5 via RPyC")
                    return True
                except Exception as e:
                    print(f"⚠️ Connection attempt {i+1} failed: {e}")
                    time.sleep(2)
            return False
        except Exception as e:
            print(f"❌ Fatal Connection Error: {e}")
            return False

    def get_historical_data(self, symbol: str, timeframe: str, date_from: datetime, date_to: datetime) -> Optional[pd.DataFrame]:
        if not self.connected and not self.connect():
            return None
            
        try:
            # Map timeframe
            tf_map = {
                'M1': self.mt5.TIMEFRAME_M1, 'M5': self.mt5.TIMEFRAME_M5, 'M15': self.mt5.TIMEFRAME_M15,
                'H1': self.mt5.TIMEFRAME_H1, 'H4': self.mt5.TIMEFRAME_H4, 'D1': self.mt5.TIMEFRAME_D1
            }
            tf_key = timeframe.replace('PERIOD_', '')
            mt5_tf = tf_map.get(tf_key, self.mt5.TIMEFRAME_M15)
            
            # Symbol Selection
            if not self.mt5.symbol_select(symbol, True):
                alt_symbol = symbol + "m"
                if self.mt5.symbol_select(alt_symbol, True):
                    symbol = alt_symbol
                else:
                    return None
            
            ts_from = int(date_from.timestamp())
            ts_to = int(date_to.timestamp())
            
            print(f"📉 Requesting data for {symbol} ({tf_key})...")
            rates = self.mt5.copy_rates_range(symbol, mt5_tf, ts_from, ts_to)
            
            # Fallback for "Invalid params"
            if (rates is None or len(rates) == 0) and self.mt5.last_error()[0] == -2:
                print("   ⚠️ MT5 Error -2. Trying shorter range (30 days)...")
                ts_to_fallback = ts_from + (30 * 24 * 3600)
                rates = self.mt5.copy_rates_range(symbol, mt5_tf, ts_from, ts_to_fallback)

            if rates is None or len(rates) == 0:
                return None
                
            # Convert
            try:
                df = pd.DataFrame(list(rates))
            except:
                df = pd.DataFrame(rates)
                
            df['time'] = pd.to_datetime(df['time'], unit='s')
            return df
            
        except Exception as e:
            traceback.print_exc()
            return None

    def run_backtest(self, simulator, symbol, timeframe, date_from, date_to, deposit, params):
        # Param extraction
        risk = params.get('InpRisk_Per_Trade', 1.0)
        reward = params.get('InpRisk_Reward_Ratio', 2.0)
        atr_p = int(params.get('InpATR_Period', 14))
        adx_t = params.get('InpADX_Threshold', 25)
        min_c = params.get('InpMin_Confluence_Score', 5)
        cool = int(params.get('InpCooldownMinutes', 30))
        max_dd = params.get('InpMax_Drawdown_Percent', 100.0)
        
        df = self.get_historical_data(symbol, timeframe, date_from, date_to)
        if df is None:
            return {'profit_factor': 0, 'win_rate': 0, 'net_profit': 0, 'trades': 0, 'max_drawdown': 0.0}
            
        return self._run_simple_backtest(df, deposit, risk, reward, atr_p, adx_t, min_c, cool, max_dd)

    def _calculate_atr(self, df, period):
        high = df['high']
        low = df['low']
        close = df['close']
        tr1 = high - low
        tr2 = abs(high - close.shift())
        tr3 = abs(low - close.shift())
        tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
        return tr.rolling(period).mean()

    def _calculate_rsi(self, df, period):
        delta = df['close'].diff()
        gain = (delta.where(delta > 0, 0)).rolling(window=period).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(window=period).mean()
        rs = gain / loss
        return 100 - (100 / (1 + rs))

    def _run_simple_backtest(self, df, deposit, risk, reward, atr_period, adx_threshold, min_confluence, cooldown, max_dd_pct):
        # Calculate indicators
        df['atr'] = self._calculate_atr(df, atr_period)
        df['rsi'] = self._calculate_rsi(df, 14)
        df['ema_fast'] = df['close'].ewm(span=12).mean()
        df['ema_slow'] = df['close'].ewm(span=26).mean()
        
        balance = deposit
        equity_peak = deposit
        trades = []
        open_trade = None
        last_trade_time = None
        
        # Simplified simulation loop
        for i in range(50, len(df)-1):
            if balance <= 0: break
            
            # Max DD
            dd = (equity_peak - balance) / equity_peak * 100
            if dd >= max_dd_pct and max_dd_pct < 100:
                break
            if balance > equity_peak: equity_peak = balance
            
            row = df.iloc[i]
            
            # Cooldown
            if last_trade_time and (row['time'] - last_trade_time).total_seconds()/60 < cooldown:
                continue
                
            # Signal
            signal = 0
            if row['ema_fast'] > row['ema_slow'] and row['rsi'] < 70: signal = 1
            if row['ema_fast'] < row['ema_slow'] and row['rsi'] > 30: signal = -1
            
            # Close Trade
            if open_trade:
                pnl = 0
                price = row['open'] # Close at open of next bar (simplified) or hit TP/SL within bar
                # Use SL/TP checked against Low/High
                sl = open_trade['sl']
                tp = open_trade['tp']
                
                # Check Hit
                hit_tp = False
                hit_sl = False
                
                if open_trade['type'] == 1: # Buy
                   if row['low'] <= sl: hit_sl = True; price = sl
                   elif row['high'] >= tp: hit_tp = True; price = tp
                else: # Sell
                   if row['high'] >= sl: hit_sl = True; price = sl
                   elif row['low'] <= tp: hit_tp = True; price = tp
                   
                if hit_tp or hit_sl:
                    if open_trade['type'] == 1: pnl = (price - open_trade['entry']) * open_trade['vol']
                    else: pnl = (open_trade['entry'] - price) * open_trade['vol']
                    
                    balance += pnl
                    trades.append({'pnl': pnl})
                    open_trade = None
                    last_trade_time = row['time']
                    continue
            
            # Open Trade
            if signal != 0 and open_trade is None:
                atr = row['atr']
                if pd.isna(atr): continue
                
                sl_dist = atr * 1.5
                tp_dist = sl_dist * reward
                price = row['close']
                
                sl = price - sl_dist if signal == 1 else price + sl_dist
                tp = price + tp_dist if signal == 1 else price - tp_dist
                
                risk_amt = balance * (risk / 100.0)
                # Vol approx (Forex standard lot = 100000)
                # profit = vol * (price_diff) ? No, depends on contract size.
                # Assuming XAUUSD roughly point = $1
                vol = risk_amt / sl_dist if sl_dist > 0 else 0.01
                
                open_trade = {'type': signal, 'entry': price, 'sl': sl, 'tp': tp, 'vol': vol, 'time': row['time']}
                
        # Metrics
        total_trades = len(trades)
        wins = len([t for t in trades if t['pnl'] > 0])
        gross_profit = sum([t['pnl'] for t in trades if t['pnl'] > 0])
        gross_loss = abs(sum([t['pnl'] for t in trades if t['pnl'] < 0]))
        
        pf = gross_profit / gross_loss if gross_loss > 0 else (100 if gross_profit > 0 else 0)
        wr = wins / total_trades if total_trades > 0 else 0
        dd_max = max(0, (deposit - balance)/deposit * 100) # Simple DD
        
        return {
            'net_profit': balance - deposit,
            'profit_factor': pf,
            'win_rate': wr * 100,
            'trades': total_trades,
            'max_drawdown': dd_max
        }
