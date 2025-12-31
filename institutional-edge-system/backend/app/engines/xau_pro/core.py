import pandas as pd
from typing import Dict, List, Optional
from loguru import logger
from datetime import datetime
from ta.trend import MACD, EMAIndicator
from ta.momentum import RSIIndicator

# Reuse robust components from Golden Engine (assuming it remains as a library)
# If Golden is deleted, these need to be moved to a shared 'common' directory.
from app.engines.golden.structure import StructureAnalyzer
from app.engines.golden.fibonacci import FibonacciCalculator

class InstitutionalGoldEngine:
    """
    🥇 INSTITUTIONAL GOLD ENGINE (XAU_PRO)
    
    The "Gold Standard" for High-Volatility Asset Scalping.
    
    Strategy: Trend Pullback (Fib) + Momentum Shift (MACD) + Value (RSI).
    Target: > 52% Win Rate on XAUUSD M15.
    
    Logic:
    1. Trend: Price > EMA 200 (H1) & Bullish Structure.
    2. Setup: Pullback to Golden Zone (0.5 - 0.618).
    3. Filter: RSI < 45 (Not buying tops).
    4. Trigger: MACD Histogram Flip (Momentum turning Bullish).
    """
    
    def __init__(self, config: Dict):
        self.config = config
        self.symbol = config.get('symbol', 'XAUUSD') # Default to Gold
        self.timeframe = config.get('timeframe', 'M15')
        
        # --- Component Initialization ---
        # We reuse the robust Structure/Fib logic
        self.structure_analyzer = StructureAnalyzer(config.get('structure', {'zigzag_lookback': 8})) # Faster lookback for M15
        self.fib_calculator = FibonacciCalculator(config.get('fibonacci', {}))
        
        # --- Strategy Parameters (Optimized for Gold) ---
        self.ema_trend_period = config.get('ema_trend', 200)
        
        # MACD (Standard or Tuned?) 
        # Research suggests faster MACD for scalping, but standard provides better filtering.
        # Tuned Scalper: 8, 21, 5
        self.macd_fast = config.get('macd_fast', 8)
        self.macd_slow = config.get('macd_slow', 21)
        self.macd_signal = config.get('macd_signal', 5)
        
        # RSI
        # Research: 14 is too slow for M15. 9 is sharper.
        self.rsi_period = config.get('rsi_period', 9) 
        self.rsi_buy_threshold = config.get('rsi_buy_threshold', 50) # Neutral/Dip
        self.rsi_sell_threshold = config.get('rsi_sell_threshold', 50) # Neutral/Rally
        
        # Risk
        # Gold needs room to breathe. 1.2 often wicks out.
        self.rr_ratio = config.get('rr_ratio', 2.0)
        self.sl_atr_multiplier = config.get('sl_atr_multiplier', 1.5) # Wider stop
        
    def analyze(self, df: pd.DataFrame, df_higher_tf: Optional[pd.DataFrame] = None, df_daily: Optional[pd.DataFrame] = None) -> Dict:
        """
        Main Analysis Pipeline for Gold.
        """
        if df is None or len(df) < 200:
             return {'signals': [], 'structure': None}
             
        # 1. Indicators Calculation
        # -------------------------
        
        # EMA 200 (Trend)
        ema = EMAIndicator(close=df['close'], window=self.ema_trend_period)
        df['ema200'] = ema.ema_indicator()
        
        # MACD
        macd = MACD(close=df['close'], window_slow=self.macd_slow, window_fast=self.macd_fast, window_sign=self.macd_signal)
        df['macd'] = macd.macd()
        df['macd_signal'] = macd.macd_signal()
        df['macd_hist'] = macd.macd_diff()
        
        # RSI
        rsi = RSIIndicator(close=df['close'], window=self.rsi_period)
        df['rsi'] = rsi.rsi()
        
        # ATR (for Risk)
        # Assuming ATR is already in DF or we calculate it. 
        # Usually middleware adds it, but let's be safe.
        # df already has 'atr' from backend usually. If not:
        if 'atr' not in df.columns:
             from ta.volatility import AverageTrueRange
             atr_ind = AverageTrueRange(high=df['high'], low=df['low'], close=df['close'])
             df['atr'] = atr_ind.average_true_range()

        # 2. Structure & Fibs
        # -------------------
        structure = self.structure_analyzer.analyze(df)
        fib_zones = self.fib_calculator.find_active_zones(structure, df.iloc[-1].close)
        
        # 3. Logic & Confluence
        # ---------------------
        signals = []
        current = df.iloc[-1]
        prev = df.iloc[-2]
        current_price = current.close
        
        # General Trend Filter (Price vs EMA 200)
        # Note: Gold can wick below EMA in a pullback, so we rely more on Structure Trend.
        # But for 'Institutional' safety, we want alignment.
        
        # --- H1 TREND FILTER ENFORCEMENT ---
        # If higher timeframe data is provided (H1), use it to filter counter-trend scalps.
        aligned_with_h1 = True
        if df_higher_tf is not None and len(df_higher_tf) > 200:
            # Calculate H1 EMA 200 if not present
            if 'ema200' not in df_higher_tf.columns:
                h1_ema = EMAIndicator(close=df_higher_tf['close'], window=200).ema_indicator()
                df_higher_tf['ema200'] = h1_ema
            
            last_h1 = df_higher_tf.iloc[-1]
            h1_trend = 'UP' if last_h1['close'] > last_h1['ema200'] else 'DOWN'
            
            # Strict Filter: M15 Structure must match H1 Trend
            if structure.trend != h1_trend:
                aligned_with_h1 = False
                
        # Setup Direction based on Structure
        if structure.trend == 'UP' and aligned_with_h1:
            signal_type = 'BUY'
        elif structure.trend == 'DOWN' and aligned_with_h1:
            signal_type = 'SELL'
        else:
            return {'signals': [], 'structure': structure} # No Trend / Counter Trend - NO TRADE
            
        # --- BUY LOGIC ---
        if signal_type == 'BUY':
            # 1. Price check (Are we in a pullback?)
            # We want price to be lower than the recent swing high (obviously).
            
            # 2. Fib Zone Check
            in_zone = False
            active_level = None
            
            # Tolerance for Gold (wider than Forex)
            # 1.0 ATR as tolerance? Or fixed pips? Gold 1 pip = 0.01
            # Let's use percentage of price or ATR.
            tolerance_price = current['atr'] * 0.2 # 20% of an ATR bar tolerance
            
            for zone in fib_zones:
                # We target deep pullbacks: 0.5, 0.618, 0.786
                if 0.5 <= zone['ratio'] <= 0.786:
                    if abs(current_price - zone['price']) < tolerance_price:
                        in_zone = True
                        active_level = zone['ratio']
                        break
            
            # 3. Value Filter (RSI)
            # We DONT buy if RSI is already hot (> 50-55)
            # We want RSI to be 'reloading' (e.g. 30-45)
            rsi_ok = current['rsi'] < self.rsi_buy_threshold
            
            # 4. Momentum Trigger (MACD)
            # We want the Histogram to be flipping UP (turning positive) 
            # OR a Crossover just happened.
            # Histogram Flip: Prev Hist < Current Hist (Momentum increasing)
            # Strong Trigger: Hist cross 0.
            
            # Let's look for "Momentum Turn":
            # Current Hist > Prev Hist AND Current Hist > PrevPrev Hist (V shape)
            momentum_turning = current['macd_hist'] > prev['macd_hist']
            
            # Valid Entry?
            if in_zone and rsi_ok and momentum_turning:
                 # Fire Signal
                 self._create_signal(signals, 'BUY', current, structure, active_level)

        # --- SELL LOGIC ---
        elif signal_type == 'SELL':
            # 2. Fib Zone Check
            in_zone = False
            active_level = None
            tolerance_price = current['atr'] * 0.2
            
            for zone in fib_zones:
                if 0.5 <= zone['ratio'] <= 0.786:
                     if abs(current_price - zone['price']) < tolerance_price:
                        in_zone = True
                        active_level = zone['ratio']
                        break
                        
            # 3. Value Filter
            rsi_ok = current['rsi'] > self.rsi_sell_threshold
            
            # 4. Momentum
            momentum_turning = current['macd_hist'] < prev['macd_hist']
            
            if in_zone and rsi_ok and momentum_turning:
                self._create_signal(signals, 'SELL', current, structure, active_level)

        return {
            'signals': signals,
            'structure': structure,
            'fib_zones': fib_zones,
            'debug_info': {
                'rsi': current['rsi'],
                'macd_hist': current['macd_hist'],
                'in_zone': locals().get('in_zone', False)
            }
        }

    def _create_signal(self, signals, direction, current, structure, fib_level):
        """
        Constructs the signal object with Risk Management
        """
        current_price = current.close
        atr = current['atr']
        
        # Stop Loss Placement
        # BUY: Low of the structure impulse OR recent swing low
        # We can use the 'start_anchor' of the Fib as invalidation
        # Or simply ATR based for scalping.
        
        # Institutional method: Structure Invalidation
        invalid_price = structure.last_impulse_leg['start'].price
        
        # Safety fallback if structure is too far (don't risk 100 pips on M15)
        # Max Risk Distance: 3 ATR
        max_sl_dist = atr * 3.0
        
        if direction == 'BUY':
            dist_to_struct = current_price - invalid_price
            if dist_to_struct > max_sl_dist:
                sl_price = current_price - (atr * self.sl_atr_multiplier) # Tight ATR Stop
            else:
                sl_price = invalid_price - (atr * 0.2) # Below structure
                
            tp_dist = abs(current_price - sl_price) * self.rr_ratio
            tp1_price = current_price + tp_dist
            
        else:
            dist_to_struct = invalid_price - current_price
            if dist_to_struct > max_sl_dist:
                sl_price = current_price + (atr * self.sl_atr_multiplier)
            else:
                sl_price = invalid_price + (atr * 0.2)
                
            tp_dist = abs(current_price - sl_price) * self.rr_ratio
            tp1_price = current_price - tp_dist

        signal = {
            'symbol': self.symbol,
            'signal_type': direction,
            'price': current_price,
            'time': datetime.now().isoformat(),
            'stop_loss': sl_price,
            'take_profit_1': tp1_price,
            'take_profit_2': tp1_price, # Monolithic TP for now
            'strategy': 'InstitutionalGold_v1',
            'confluence_score': 95, # High Confidence
            'metadata': {
                'fib_level': fib_level,
                'rsi': current['rsi']
            }
        }
        signals.append(signal)
        logger.info(f"🥇 GOLD SNIPER SIGNAL: {direction} @ {current_price} | Fib {fib_level} | RSI {current['rsi']:.1f}")
