import pandas as pd
from typing import Dict, List, Optional
from loguru import logger
from datetime import datetime
from ta.trend import MACD, EMAIndicator
from ta.momentum import RSIIndicator
import numpy as np

class SilverEngine:
    """
    ⚪ SILVER ENGINE (Momentum Scalp)
    
    Strategy: "Speed Demon" MACD Trend Following.
    Best For: Strong Momentum pairs (EURUSD, USDJPY, Gold) on M15.
    
    Optimized Scalping Settings:
    - MACD: 5, 13, 8 (Fast)
    - RSI: 9 Period (Sensitive)
    - Trend: 200 EMA
    """
    
    def __init__(self, config: Dict):
        self.config = config
        self.symbol = config.get('symbol', 'Unknown')
        self.timeframe = config.get('timeframe', 'M15')
        
        # Optimized Settings
        self.macd_fast = config.get('macd_fast', 5)
        self.macd_slow = config.get('macd_slow', 13)
        self.macd_signal = config.get('macd_signal', 8)
        self.rsi_period = config.get('rsi_period', 9)
        self.ema_trend_period = config.get('ema_trend', 200)
        
        # Risk Settings
        self.rr_ratio = config.get('rr_ratio', 2.0)
        self.fixed_sl_pips = config.get('fixed_sl_pips', 10.0) # Scalp tightness
        
    def analyze(self, df: pd.DataFrame, df_higher_tf: Optional[pd.DataFrame] = None, df_daily: Optional[pd.DataFrame] = None) -> Dict:
        """
        Analyze M15 data for Momentum setups.
        """
        if df is None or len(df) < 200:
            return {'signals': [], 'structure': None}
            
        # 1. Indicators
        
        # MACD
        # MACD
        macd_indicator = MACD(
            close=df['close'], 
            window_slow=self.macd_slow, 
            window_fast=self.macd_fast, 
            window_sign=self.macd_signal
        )
        # ta library returns Series
        df['MACD_line'] = macd_indicator.macd()
        df['MACD_signal'] = macd_indicator.macd_signal()
        df['MACD_hist'] = macd_indicator.macd_diff()
        
        # RSI
        rsi_indicator = RSIIndicator(close=df['close'], window=self.rsi_period)
        df['rsi'] = rsi_indicator.rsi()

        # EMA
        ema_indicator = EMAIndicator(close=df['close'], window=self.ema_trend_period)
        df['ema200'] = ema_indicator.ema_indicator()
        
        # 2. Logic Check
        signals = []
        current = df.iloc[-1]
        prev = df.iloc[-2]
        
        current_price = current.close
        trend_ema = current['ema200']
        
        # Determine Trend
        is_uptrend = current_price > trend_ema
        is_downtrend = current_price < trend_ema
        
        # entry logic
        # BUY: Uptrend + MACD Crossover (Bullish) + RSI < 55 (Dip)
        # SELL: Downtrend + MACD Crossunder (Bearish) + RSI > 45 (Rally)
        
        # Check Crossover lines
        # MACD Line > Signal Line (Bullish)
        macd_val = current['MACD_line']
        signal_val = current['MACD_signal']
        prev_macd = prev['MACD_line']
        prev_signal = prev['MACD_signal']
        
        macd_crossover = (prev_macd <= prev_signal) and (macd_val > signal_val)
        macd_crossunder = (prev_macd >= prev_signal) and (macd_val < signal_val)
        
        signal_type = None
        
        if is_uptrend and macd_crossover:
            # Check RSI Dip Filter
            if current['rsi'] < 55: 
                signal_type = 'BUY'
                
        elif is_downtrend and macd_crossunder:
            # Check RSI Rally Filter
            if current['rsi'] > 45: 
                signal_type = 'SELL'
                
        if signal_type:
            # Calculate Risk
            pip_size = 0.01 if 'JPY' in self.symbol else 0.0001
            sl_dist = self.fixed_sl_pips * pip_size
            
            sl_price = current_price - sl_dist if signal_type == 'BUY' else current_price + sl_dist
            tp_dist = sl_dist * self.rr_ratio
            tp1_price = current_price + tp_dist if signal_type == 'BUY' else current_price - tp_dist
            
            signal = {
                'symbol': self.symbol,
                'signal_type': signal_type,
                'entry_price': current_price,
                'price': current_price,
                'time': datetime.now().isoformat(),
                'stop_loss': sl_price,
                'take_profit_1': tp1_price,
                'take_profit_2': tp1_price, 
                'take_profit_3': tp1_price,
                'strategy': 'SilverMomentum',
                'confluence_score': 10,
                'metadata': {'macd': macd_val, 'rsi': current['rsi']}
            }
            signals.append(signal)
            logger.info(f"⚪ Silver Signal Found: {signal_type} @ {current_price} | MACD Cross | RSI {current['rsi']:.1f}")

        # Structure Shim for UI
        structure_shim = type('obj', (object,), {'trend': 'UP' if is_uptrend else 'DOWN', 'current_phase': 'IMPULSE'})
        
        return {
            'signals': signals,
            'structure': structure_shim, 
            'debug_info': {'macd': macd_val, 'rsi': current['rsi']}
        }

    def update_news(self, events: List):
        pass
