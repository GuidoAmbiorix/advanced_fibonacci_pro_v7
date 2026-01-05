"""
Smart Money Concepts (SMC) Analyzer v4.0
Based on ICT (Inner Circle Trader) methodology.

Core Concepts:
- Order Blocks: Institutional entry zones
- Fair Value Gaps (FVG): Price imbalances
- Liquidity Sweeps: Stop hunts before reversals
"""

from typing import Dict, List, Optional
import pandas as pd
import numpy as np


class SMCAnalyzer:
    """
    Smart Money Concepts detector for institutional-level trading.
    All parameters are configurable from slot config (UI).
    """
    
    def __init__(self, config: Dict):
        # Order Blocks config
        self.ob_enabled = config.get('enable_order_blocks', True)
        self.ob_lookback = config.get('ob_lookback', 20)
        
        # Liquidity Sweep config
        self.sweep_enabled = config.get('enable_liquidity_sweep', True)
        self.sweep_lookback = config.get('sweep_lookback', 10)
        
        # Fair Value Gap config
        self.fvg_enabled = config.get('enable_fvg', True)
        self.fvg_min_size = config.get('fvg_min_size_atr', 0.5)
    
    def find_order_blocks(self, df: pd.DataFrame, direction: str, atr: float) -> List[Dict]:
        """
        Find Order Blocks - last opposing candle before a strong impulse move.
        
        BULLISH OB: Last bearish candle before strong bullish move
        BEARISH OB: Last bullish candle before strong bearish move
        
        Returns list of unmitigated order blocks with high/low zones.
        """
        if not self.ob_enabled or len(df) < self.ob_lookback:
            return []
        
        order_blocks = []
        lookback = min(self.ob_lookback, len(df) - 2)
        
        for i in range(len(df) - lookback, len(df) - 1):
            current = df.iloc[i]
            next_candle = df.iloc[i + 1]
            
            # Check for displacement (strong move = 1.5x ATR)
            next_body = abs(next_candle['close'] - next_candle['open'])
            is_displacement = next_body > (atr * 1.5)
            
            if not is_displacement:
                continue
            
            if direction == 'BUY':
                # Bullish OB: Bearish candle followed by bullish displacement
                is_bearish_candle = current['close'] < current['open']
                is_bullish_move = next_candle['close'] > next_candle['open']
                
                if is_bearish_candle and is_bullish_move:
                    order_blocks.append({
                        'type': 'BULLISH_OB',
                        'high': current['high'],
                        'low': current['low'],
                        'time': current.name if hasattr(current, 'name') else i,
                        'strength': next_body / atr
                    })
            
            else:  # SELL
                # Bearish OB: Bullish candle followed by bearish displacement
                is_bullish_candle = current['close'] > current['open']
                is_bearish_move = next_candle['close'] < next_candle['open']
                
                if is_bullish_candle and is_bearish_move:
                    order_blocks.append({
                        'type': 'BEARISH_OB',
                        'high': current['high'],
                        'low': current['low'],
                        'time': current.name if hasattr(current, 'name') else i,
                        'strength': next_body / atr
                    })
        
        # Return most recent 3 OBs (oldest to newest)
        return order_blocks[-3:] if order_blocks else []
    
    def find_fair_value_gaps(self, df: pd.DataFrame, direction: str, atr: float) -> List[Dict]:
        """
        Find Fair Value Gaps (FVG) - 3-candle imbalance patterns.
        
        Bullish FVG: Candle 1 high < Candle 3 low (gap up)
        Bearish FVG: Candle 1 low > Candle 3 high (gap down)
        
        Returns list of unfilled FVGs.
        """
        if not self.fvg_enabled or len(df) < 3:
            return []
        
        fvgs = []
        min_gap_size = atr * self.fvg_min_size
        
        for i in range(2, len(df)):
            c1 = df.iloc[i - 2]  # First candle
            c2 = df.iloc[i - 1]  # Middle candle (the gap)
            c3 = df.iloc[i]      # Third candle
            
            if direction == 'BUY':
                # Bullish FVG: Gap up
                gap = c3['low'] - c1['high']
                if gap > min_gap_size:
                    fvgs.append({
                        'type': 'BULLISH_FVG',
                        'top': c3['low'],
                        'bottom': c1['high'],
                        'size': gap,
                        'time': c2.name if hasattr(c2, 'name') else i - 1
                    })
            
            else:  # SELL
                # Bearish FVG: Gap down
                gap = c1['low'] - c3['high']
                if gap > min_gap_size:
                    fvgs.append({
                        'type': 'BEARISH_FVG',
                        'top': c1['low'],
                        'bottom': c3['high'],
                        'size': gap,
                        'time': c2.name if hasattr(c2, 'name') else i - 1
                    })
        
        # Return most recent 5 FVGs
        return fvgs[-5:] if fvgs else []
    
    def detect_liquidity_sweep(self, df: pd.DataFrame, direction: str) -> bool:
        """
        Detect if a liquidity sweep just occurred.
        
        Bullish Sweep: Price breaks below recent low, then closes above it
        Bearish Sweep: Price breaks above recent high, then closes below it
        
        This is THE KEY SMC confirmation - wait for stop hunt before entry.
        """
        if not self.sweep_enabled or len(df) < self.sweep_lookback + 2:
            return False
        
        current = df.iloc[-1]
        prev = df.iloc[-2]
        
        # Find recent swing high/low (excluding last 2 candles)
        lookback_data = df.iloc[-(self.sweep_lookback + 2):-2]
        recent_high = lookback_data['high'].max()
        recent_low = lookback_data['low'].min()
        
        if direction == 'BUY':
            # Bullish sweep: Price swept below low, then closed above
            swept_low = prev['low'] < recent_low
            closed_above = current['close'] > recent_low
            bullish_close = current['close'] > current['open']
            
            return swept_low and closed_above and bullish_close
        
        else:  # SELL
            # Bearish sweep: Price swept above high, then closed below
            swept_high = prev['high'] > recent_high
            closed_below = current['close'] < recent_high
            bearish_close = current['close'] < current['open']
            
            return swept_high and closed_below and bearish_close
    
    def price_in_zone(self, candle_high: float, candle_low: float, zones: List[Dict]) -> Optional[Dict]:
        """
        Check if current candle's range overlaps with any zone (OB or FVG).
        Uses candle high/low for broader zone detection.
        Returns the zone if found, None otherwise.
        """
        for zone in zones:
            zone_high = zone.get('high') or zone.get('top')
            zone_low = zone.get('low') or zone.get('bottom')
            
            # Check if candle range overlaps with zone range
            # Overlap exists if: candle_low <= zone_high AND candle_high >= zone_low
            if candle_low <= zone_high and candle_high >= zone_low:
                return zone
        
        return None
    
    def get_smc_confluence(self, df: pd.DataFrame, direction: str, current_price: float, atr: float, 
                           candle_high: float = None, candle_low: float = None) -> Dict:
        """
        Get full SMC analysis with confluence score.
        Now uses candle range (high/low) for zone detection.
        
        Returns dict with:
        - in_order_block: bool
        - liquidity_swept: bool
        - in_fvg: bool
        - smc_score: 0-3 (how many conditions met)
        - smc_details: string description
        """
        # Use passed high/low or default to current price
        c_high = candle_high if candle_high is not None else current_price
        c_low = candle_low if candle_low is not None else current_price
        
        result = {
            'in_order_block': False,
            'order_block': None,
            'liquidity_swept': False,
            'in_fvg': False,
            'fvg': None,
            'smc_score': 0,
            'smc_details': []
        }
        
        # Check Order Blocks
        if self.ob_enabled:
            obs = self.find_order_blocks(df, direction, atr)
            ob_zone = self.price_in_zone(c_high, c_low, obs)
            if ob_zone:
                result['in_order_block'] = True
                result['order_block'] = ob_zone
                result['smc_score'] += 1
                result['smc_details'].append(f"In {ob_zone['type']}")
        
        # Check Liquidity Sweep
        if self.sweep_enabled:
            if self.detect_liquidity_sweep(df, direction):
                result['liquidity_swept'] = True
                result['smc_score'] += 1
                result['smc_details'].append("Liquidity Swept")
        
        # Check Fair Value Gaps
        if self.fvg_enabled:
            fvgs = self.find_fair_value_gaps(df, direction, atr)
            fvg_zone = self.price_in_zone(c_high, c_low, fvgs)
            if fvg_zone:
                result['in_fvg'] = True
                result['fvg'] = fvg_zone
                result['smc_score'] += 1
                result['smc_details'].append(f"In {fvg_zone['type']}")
        
        return result
