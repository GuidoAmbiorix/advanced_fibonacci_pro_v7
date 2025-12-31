import pandas as pd
from ta.volatility import BollingerBands
from ta.trend import ADXIndicator
from ta.momentum import RSIIndicator
from typing import Dict, List, Optional
from loguru import logger
from datetime import datetime

class BronzeEngine:
    """
    🟤 BRONZE ENGINE (Mean Reversion)
    
    Strategy: Bollinger Band Fade + ADX Filter.
    Best For: Low Volatility / Ranging / Choppy Markets.
    
    Optimized Settings:
    - Bollinger: 20, 2.0
    - Filter: ADX < 25 (Must be Non-Trending)
    """
    
    def __init__(self, config: Dict):
        self.config = config
        self.symbol = config.get('symbol', 'Unknown')
        self.timeframe = config.get('timeframe', 'M15')
        
        # Settings
        self.bb_length = config.get('bb_length', 20)
        self.bb_std = config.get('bb_std', 2.0)
        self.adx_period = config.get('adx_period', 14)
        self.adx_threshold = config.get('adx_threshold', 25.0)
        
        # Risk
        self.rr_ratio = config.get('rr_ratio', 1.5) # Lower RR for scalping ranges
        self.fixed_sl_pips = config.get('fixed_sl_pips', 15.0) 
        
    def analyze(self, df: pd.DataFrame, df_higher_tf: Optional[pd.DataFrame] = None, df_daily: Optional[pd.DataFrame] = None) -> Dict:
        """
        Analyze data for Mean Reversion setups.
        """
        if df is None or len(df) < 50:
             return {'signals': [], 'structure': None}
             
        # 1. Indicators
        
        # Bollinger Bands
        bb_indicator = BollingerBands(close=df['close'], window=self.bb_length, window_dev=self.bb_std)
        df['bbl'] = bb_indicator.bollinger_lband()
        df['bbu'] = bb_indicator.bollinger_hband()
        df['bbm'] = bb_indicator.bollinger_mavg()
        
        # ADX
        # ADX requires High, Low, Close
        adx_indicator = ADXIndicator(high=df['high'], low=df['low'], close=df['close'], window=self.adx_period)
        df['adx'] = adx_indicator.adx()
            
        # RSI
        rsi_indicator = RSIIndicator(close=df['close'], window=14)
        df['rsi'] = rsi_indicator.rsi()
        
        # 2. Logic
        current = df.iloc[-1]
        
        # Filter: Is Market Trending?
        if current['adx'] > self.adx_threshold:
            # Market is Trending -> Bronze SLEEPS (Let Gold/Silver handle it)
            # Return NEUTRAL structure so user knows why
            structure_shim = type('obj', (object,), {'trend': 'NEUTRAL', 'current_phase': 'TRENDING_BLOCKED'})
            return {'signals': [], 'structure': structure_shim}
            
        # Entry Logic (Fade the Bands)
        signal_type = None
        current_price = current.close
        
        # BUY: Touch Lower Band + RSI Oversold (< 30)
        if current_price <= current['bbl'] and current['rsi'] < 35: # Broadened slightly to 35
             signal_type = 'BUY'
             
        # SELL: Touch Upper Band + RSI Overbought (> 70)
        elif current_price >= current['bbu'] and current['rsi'] > 65:
             signal_type = 'SELL'
             
        signals = []
        if signal_type:
            pip_size = 0.01 if 'JPY' in self.symbol else 0.0001
            sl_dist = self.fixed_sl_pips * pip_size
            
            # For Reversion, TP is often Measure to Middle Band or Opposite Band
            # But Fixed RR is simpler. Let's use Fixed RR 1.5
            tp_dist = sl_dist * self.rr_ratio
            
            sl_price = current_price - sl_dist if signal_type == 'BUY' else current_price + sl_dist
            tp1_price = current_price + tp_dist if signal_type == 'BUY' else current_price - tp_dist
            
            signal = {
                'symbol': self.symbol,
                'signal_type': signal_type,
                'price': current_price,
                'time': datetime.now().isoformat(),
                'stop_loss': sl_price,
                'take_profit_1': tp1_price,
                'take_profit_2': tp1_price,
                'strategy': 'BronzeReversion',
                'confluence_score': 10
            }
            signals.append(signal)
            logger.info(f"🟤 Bronze Signal Found: {signal_type} @ {current_price} | BB Touch | RSI {current['rsi']:.1f}")
            
        structure_shim = type('obj', (object,), {'trend': 'NEUTRAL', 'current_phase': 'RANGING'})
        
        return {
            'signals': signals,
            'structure': structure_shim,
            'debug_info': {'adx': current['adx']}
        }

    def update_news(self, events: List):
        pass
