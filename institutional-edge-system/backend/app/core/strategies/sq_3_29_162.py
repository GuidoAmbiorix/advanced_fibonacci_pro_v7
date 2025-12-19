import pandas as pd
import numpy as np
from typing import Optional, Dict, Any
from loguru import logger
from datetime import datetime

from app.core.strategies.base import BaseStrategy
from app.core.strategy_models import AdaptiveSignal, StrategyType, MarketRegime

class SQStrategy_3_29_162(BaseStrategy):
    """
    Strategy 3.29.162 (StrategyQuant)
    
    Logic:
    - Long Entry:
        - RollingVWAP(6)[1] Crosses Below RollingVWAP(58)[3] 
        - ADX(14)[3] < 20
    """
    
    def analyze(self, df: pd.DataFrame, df_higher_tf: Optional[pd.DataFrame] = None) -> Dict[str, Any]:
        """
        Analyze market data and generate signals.
        """
        signals = []
        
        if len(df) < 100:
            return {'signals': [], 'metadata': {}}
            
        # Parameters
        p_fast = 6
        p_slow = 58
        shift_fast = 1
        shift_slow = 3
        adx_period = 14
        adx_shift = 3
        adx_level = 20.0
        
        # Calculate Indicators - Rolling VWAP
        rvwap_fast = self._calculate_rolling_vwap(df, p_fast)
        rvwap_slow = self._calculate_rolling_vwap(df, p_slow)
        
        # ADX
        # Note: If ADX is already in df, use it, otherwise calculate
        df_ind = df.copy()
        if 'adx' not in df_ind.columns:
            df_ind = self._calculate_adx(df_ind)
            
        try:
            # Ensure enough data
            if len(df_ind) < max(p_slow, adx_period) + 10:
                return {'signals': [], 'metadata': {}}
                
            # ADX condition: ADX(14)[3] < 20
            adx_val = df_ind['adx'].iloc[-1 - adx_shift]
            
            if adx_val >= adx_level:
                 return {'signals': [], 'metadata': {'adx': adx_val, 'status': 'ADX_FILTERED'}}
            
            # Crosses Below Logic:
            # A = Fast[Shift 1], B = Slow[Shift 3]
            # Current (Signal Candle): A < B
            # Previous (Pre-Signal): Prev_A >= Prev_B
            
            A = rvwap_fast.iloc[-1 - shift_fast]
            B = rvwap_slow.iloc[-1 - shift_slow]
            
            Prev_A = rvwap_fast.iloc[-1 - (shift_fast + 1)]
            Prev_B = rvwap_slow.iloc[-1 - (shift_slow + 1)]
            
            # LONG SIGNAL
            if Prev_A >= Prev_B and A < B:
                # Signal Triggered
                current_price = df['close'].iloc[-1]
                atr = df_ind['atr'].iloc[-1] if 'atr' in df_ind.columns else 0.0
                
                # Exit Parameters
                entry = current_price
                sl_dist = entry * 0.062 # 6.2%
                tp_dist = entry * 0.025 # 2.5%
                
                stop_loss = entry - sl_dist
                take_profit = entry + tp_dist
                
                signal = AdaptiveSignal(
                    symbol=self.symbol,
                    timeframe=self.timeframe,
                    entry_price=entry,
                    stop_loss=stop_loss,
                    take_profit=take_profit,
                    direction="BUY",
                    strategy_type=StrategyType.TREND_FOLLOWING, 
                    market_regime=MarketRegime.TRENDING, # Assumption or pass detected regime
                    score=8.5,
                    confidence=0.8,
                    timestamp=df['time'].iloc[-1] if 'time' in df.columns else datetime.utcnow(),
                    metadata={
                        'strategy': 'SQ_3.29.162',
                        'rvwap_fast': A,
                        'rvwap_slow': B,
                        'adx': adx_val
                    }
                )
                signals.append(signal)
                logger.info(f"🧬 SQ Strategy 3.29.162 Signal: BUY @ {entry}")

        except Exception as e:
            logger.error(f"Error in Strategy 3.29.162: {e}")
            return {'signals': [], 'error': str(e)}
        
        return {
            'signals': signals,
            'metadata': {
                'strategy': 'SQ_3.29.162',
                'adx': adx_val if 'adx_val' in locals() else None
            }
        }

    def _calculate_rolling_vwap(self, df: pd.DataFrame, period: int) -> pd.Series:
        """Calculate Rolling VWAP"""
        tp = (df['high'] + df['low'] + df['close']) / 3
        pv_sum = (tp * df['volume']).rolling(window=period).sum()
        v_sum = df['volume'].rolling(window=period).sum()
        return pv_sum / v_sum

    def _calculate_adx(self, df: pd.DataFrame, period: int = 14) -> pd.DataFrame:
        """Calculate ADX"""
        df = df.copy()
        
        # TR
        df['h-l'] = df['high'] - df['low']
        df['h-pc'] = abs(df['high'] - df['close'].shift(1))
        df['l-pc'] = abs(df['low'] - df['close'].shift(1))
        df['tr'] = df[['h-l', 'h-pc', 'l-pc']].max(axis=1)
        
        # DM
        df['up_move'] = df['high'] - df['high'].shift(1)
        df['down_move'] = df['low'].shift(1) - df['low']
        
        df['plus_dm'] = np.where((df['up_move'] > df['down_move']) & (df['up_move'] > 0), df['up_move'], 0)
        df['minus_dm'] = np.where((df['down_move'] > df['up_move']) & (df['down_move'] > 0), df['down_move'], 0)
        
        # Smooth
        df['tr_s'] = df['tr'].rolling(window=period).sum() # Simplified smoothing
        df['plus_dm_s'] = df['plus_dm'].rolling(window=period).sum()
        df['minus_dm_s'] = df['minus_dm'].rolling(window=period).sum()
        
        df['plus_di'] = 100 * (df['plus_dm_s'] / df['tr_s'])
        df['minus_di'] = 100 * (df['minus_dm_s'] / df['tr_s'])
        
        df['dx'] = 100 * abs(df['plus_di'] - df['minus_di']) / (df['plus_di'] + df['minus_di'])
        df['adx'] = df['dx'].rolling(window=period).mean()
        
        # Also calc ATR for general use (if not present) since we have TR
        if 'atr' not in df.columns:
            df['atr'] = df['tr'].rolling(window=14).mean()
            
        return df
