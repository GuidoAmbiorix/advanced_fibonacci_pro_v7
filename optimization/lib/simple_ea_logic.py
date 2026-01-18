"""
Simple EA Logic Implementation for Backtesting
Implements basic trend-following logic similar to typical MT5 EAs
"""
import pandas as pd
import numpy as np
from typing import Dict, List, Tuple, Optional


class SimpleEALogic:
    """
    Simple EA logic for backtesting
    Implements basic trend following with RSI, ADX, and ATR
    """
    
    def __init__(self, parameters: Dict):
        """Initialize with EA parameters"""
        self.params = parameters
        self.positions = []  # Track open positions
        self.closed_trades = []
        
        # Extract commonly used parameters
        self.rsi_period = parameters.get('InpRSI_Period', 14)
        self.adx_period = parameters.get('InpADX_Period', 14)
        self.adx_threshold = parameters.get('InpADX_Threshold', 25)
        self.atr_period = parameters.get('InpATR_Period', 14)
        self.risk_reward = parameters.get('InpRisk_Reward_Ratio', 2.0)
    
    def calculate_rsi(self, data: pd.DataFrame, period: int = 14) -> pd.Series:
        """Calculate RSI indicator"""
        delta = data['close'].diff()
        gain = (delta.where(delta > 0, 0)).rolling(window=period).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(window=period).mean()
        
        rs = gain / loss
        rsi = 100 - (100 / (1 + rs))
        return rsi
    
    def calculate_atr(self, data: pd.DataFrame, period: int = 14) -> pd.Series:
        """Calculate ATR indicator"""
        high_low = data['high'] - data['low']
        high_close = np.abs(data['high'] - data['close'].shift())
        low_close = np.abs(data['low'] - data['close'].shift())
        
        ranges = pd.concat([high_low, high_close, low_close], axis=1)
        true_range = np.max(ranges, axis=1)
        atr = true_range.rolling(period).mean()
        return atr
    
    def calculate_ema(self, data: pd.Series, period: int) -> pd.Series:
        """Calculate EMA"""
        return data.ewm(span=period, adjust=False).mean()
    
    def generate_signal(self, data: pd.DataFrame, index: int) -> Optional[str]:
        """
        Generate trading signal based on indicators
        
        Returns:
            'BUY', 'SELL', or None
        """
        if index < max(self.rsi_period, self.adx_period, self.atr_period, 50):
            return None
        
        # Calculate indicators
        rsi = self.calculate_rsi(data.iloc[:index+1], self.rsi_period).iloc[-1]
        atr = self.calculate_atr(data.iloc[:index+1], self.atr_period).iloc[-1]
        
        # Simple trend following logic
        close = data.iloc[index]['close']
        ema_50 = self.calculate_ema(data.iloc[:index+1]['close'], 50).iloc[-1]
        ema_200 = self.calculate_ema(data.iloc[:index+1]['close'], 200).iloc[-1] if index >= 200 else ema_50
        
        # Buy signal: price above EMAs, RSI not overbought
        if close > ema_50 > ema_200 and 40 < rsi < 70:
            return 'BUY'
        
        # Sell signal: price below EMAs, RSI not oversold  
        if close < ema_50 < ema_200 and 30 < rsi < 60:
            return 'SELL'
        
        return None
    
    def calculate_position_size(self, price: float, sl_distance: float, balance: float) -> float:
        """Calculate position size based on risk"""
        risk_percent = self.params.get('InpRisk_Per_Trade', 1.0) / 100
        risk_amount = balance * risk_percent
        
        if sl_distance <= 0:
            return 0.01
        
        # Simplified lot calculation
        # In real MT5: lot = risk_amount / (sl_distance_pips * pip_value)
        lot_size = min(risk_amount / (sl_distance * 100), 
                      self.params.get('InpMaxLot_Per_Trade', 1.0))
        
        return max(0.01, round(lot_size, 2))
    
    def open_position(self, signal: str, bar: pd.Series, balance: float) -> Dict:
        """Open a new position"""
        atr = self.calculate_atr(pd.DataFrame([bar]), self.atr_period)
        if len(atr) == 0 or pd.isna(atr.iloc[0]):
            atr_value = bar['high'] - bar['low']
        else:
            atr_value = atr.iloc[0]
        
        entry_price = bar['close']
        
        if signal == 'BUY':
            sl = entry_price - (atr_value * 2)
            tp = entry_price + (atr_value * 2 * self.risk_reward)
        else:  # SELL
            sl = entry_price + (atr_value * 2)
            tp = entry_price - (atr_value * 2 * self.risk_reward)
        
        sl_distance = abs(entry_price - sl)
        lot_size = self.calculate_position_size(entry_price, sl_distance, balance)
        
        position = {
            'type': signal,
            'entry_price': entry_price,
            'sl': sl,
            'tp': tp,
            'lot_size': lot_size,
            'entry_time': bar['time']
        }
        
        return position
    
    def check_exit(self, position: Dict, bar: pd.Series) -> Optional[Tuple[float, str]]:
        """Check if position should be closed"""
        high = bar['high']
        low = bar['low']
        
        if position['type'] == 'BUY':
            # Check SL
            if low <= position['sl']:
                profit = (position['sl'] - position['entry_price']) * position['lot_size'] * 100
                return profit, 'SL'
            # Check TP
            if high >= position['tp']:
                profit = (position['tp'] - position['entry_price']) * position['lot_size'] * 100
                return profit, 'TP'
        else:  # SELL
            # Check SL
            if high >= position['sl']:
                profit = (position['entry_price'] - position['sl']) * position['lot_size'] * 100
                return profit, 'SL'
            # Check TP
            if low <= position['tp']:
                profit = (position['entry_price'] - position['tp']) * position['lot_size'] * 100
                return profit, 'TP'
        
        return None
    
    def backtest(self, data: pd.DataFrame, initial_balance: float = 10000) -> List[Dict]:
        """
        Run backtest on historical data
        
        Returns:
            List of closed trades
        """
        balance = initial_balance
        
        for i in range(len(data)):
            bar = data.iloc[i]
            
            # Check existing positions
            if self.positions:
                for position in self.positions[:]:  # Copy list to modify during iteration
                    exit_result = self.check_exit(position, bar)
                    
                    if exit_result:
                        profit, exit_type = exit_result
                        balance += profit
                        
                        trade = {
                            **position,
                            'exit_price': position['tp'] if exit_type == 'TP' else position['sl'],
                            'exit_time': bar['time'],
                            'profit': profit,
                            'exit_type': exit_type
                        }
                        
                        self.closed_trades.append(trade)
                        self.positions.remove(position)
            
            # Check for new signals (if no positions open)
            if not self.positions:
                signal = self.generate_signal(data, i)
                
                if signal:
                    position = self.open_position(signal, bar, balance)
                    self.positions.append(position)
        
        return self.closed_trades
