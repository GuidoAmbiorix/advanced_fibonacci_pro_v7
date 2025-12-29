import pandas as pd
import numpy as np
from typing import List, Dict, Optional
from dataclasses import dataclass

@dataclass
class SwingPoint:
    time: pd.Timestamp
    price: float
    type: str  # 'HIGH' or 'LOW'
    index: int

@dataclass
class MarketStructure:
    swings: List[SwingPoint]
    trend: str # 'UP', 'DOWN', 'NEUTRAL'
    current_phase: str # 'IMPULSE', 'CORRECTION'
    last_impulse_leg: Optional[Dict] = None

class StructureAnalyzer:
    """
    Analyzes market structure using ZigZag/Pivot points to identify 
    Highs/Lows and market phases (Impulse vs Correction).
    """
    
    def __init__(self, config: Dict):
        self.lookback = config.get('zigzag_lookback', 5)
        self.deviation = config.get('zigzag_deviation', 0.05) # Percent deviation
        
        # Dynamic Mode Params
        self.dynamic_mode = config.get('dynamic_mode', False)
        self.atr_multiplier = config.get('atr_multiplier', 1.5)

    def analyze(self, df: pd.DataFrame) -> MarketStructure:
        """
        Identify market structure from dataframe.
        """
        if df is None or len(df) < 50:
            return MarketStructure([], "NEUTRAL", "CORRECTION")

        swings = self._calculate_zigzag(df)
        if len(swings) < 4:
            swings = self._calculate_zigzag(df) # Retry? No, just return.
            # If swings empty, return empty
            pass 

        if len(swings) < 4:
             return MarketStructure(swings, "NEUTRAL", "CORRECTION")
            
        # Determine Trend based on last 4 swings (HH/HL or LH/LL)
        trend = self._determine_trend(swings)
        
        # Determine Current Phase (Impulse or Correction)
        # If trend is UP, and we are moving DOWN from a High -> Correction
        current_phase = self._determine_phase(swings, df.iloc[-1].close, trend)
        
        # Identify the last impulse leg (for Fib drawing)
        last_impulse = self._find_last_impulse(swings, trend)
        
        return MarketStructure(
            swings=swings,
            trend=trend,
            current_phase=current_phase,
            last_impulse_leg=last_impulse
        )

    def _calculate_zigzag(self, df: pd.DataFrame) -> List[SwingPoint]:
        """
        Standard ZigZag algorithm:
        - Identify pivots based on self.deviation% moves OR ATR moves.
        """
        swings = []
        if len(df) == 0:
            return swings
            
        # Series for speed
        highs = df['high'].values
        lows = df['low'].values
        closes = df['close'].values
        times = df.index
        
        # Prepare ATR if dynamic
        atrs = []
        if self.dynamic_mode and 'atr' in df.columns:
            atrs = df['atr'].values
        elif self.dynamic_mode:
            # Fallback if no ATR column: Calculate simple ATR-14
            # (Simplified for now, assumes 'atr' exists or uses fixed)
            pass 
        
        last_swing_type = None # 'HIGH' or 'LOW'
        last_swing_val = closes[0]
        last_swing_idx = 0
        
        # Setup first point
        swings.append(SwingPoint(times[0], closes[0], 'START', 0))
        
        # Implementation relying on deviation:
        current_trend = 0 # 1 = Up, -1 = Down
        temp_high = highs[0]
        temp_low = lows[0]
        temp_high_idx = 0
        temp_low_idx = 0
        
        for i in range(1, len(df)):
            close = closes[i]
            high = highs[i]
            low = lows[i]
            
            # --- CALCULATE THRESHOLD ---
            threshold_move = 0.0
            if self.dynamic_mode and len(atrs) > i:
                # Dynamic Threshold: ATR * Multiplier
                threshold_move = atrs[i] * self.atr_multiplier
            else:
                # Fixed Percentage Threshold (e.g. 0.05% of price)
                # Use current price reference (temp_low or temp_high)
                threshold_move = 0 # Calculated relative to base
            
            # Helper to check move size
            def is_move_enough(price, base):
                if self.dynamic_mode and len(atrs) > i:
                    return abs(price - base) > threshold_move
                else:
                    return abs(price - base) / base > self.deviation / 100

            # Simple Percentage / ATR Reversal logic
            if current_trend == 0:
                if high > temp_high:
                    temp_high = high
                    temp_high_idx = i
                if low < temp_low:
                    temp_low = low
                    temp_low_idx = i
                    
                # Initial move detection
                if is_move_enough(high, temp_low):
                    current_trend = 1
                    swings.append(SwingPoint(times[temp_low_idx], temp_low, 'LOW', temp_low_idx))
                    last_swing_type = 'LOW'
                elif is_move_enough(low, temp_high): # moving down from temp_high
                     # Note: logic check: (temp_high - low) > thresh
                    current_trend = -1
                    swings.append(SwingPoint(times[temp_high_idx], temp_high, 'HIGH', temp_high_idx))
                    last_swing_type = 'HIGH'
                    
            elif current_trend == 1: # Trend Up, looking for High
                if high > temp_high:
                    temp_high = high
                    temp_high_idx = i
                
                # Check for reversal down
                # If Price < High - Threshold
                if is_move_enough(low, temp_high): # "Is move from TempHigh to Low enough?"
                    # Confirmed High
                    swings.append(SwingPoint(times[temp_high_idx], temp_high, 'HIGH', temp_high_idx))
                    current_trend = -1
                    last_swing_type = 'HIGH'
                    temp_low = low
                    temp_low_idx = i
            
            elif current_trend == -1: # Trend Down, looking for Low
                if low < temp_low:
                    temp_low = low
                    temp_low_idx = i
                
                # Check for reversal up
                # If Price > Low + Threshold
                if is_move_enough(high, temp_low):
                    # Confirmed Low
                    swings.append(SwingPoint(times[temp_low_idx], temp_low, 'LOW', temp_low_idx))
                    current_trend = 1
                    last_swing_type = 'LOW'
                    temp_high = high
                    temp_high_idx = i
                    
        return swings

    def _determine_trend(self, swings: List[SwingPoint]) -> str:
        if len(swings) < 4:
            return "NEUTRAL"
            
        last_4 = swings[-4:] # [H, L, H, L] e.g.
        
        # Check Highs
        highs = [s.price for s in last_4 if s.type == 'HIGH']
        lows = [s.price for s in last_4 if s.type == 'LOW']
        
        if len(highs) < 2 or len(lows) < 2:
            return "NEUTRAL"
            
        # Uptrend: HH + HL
        if highs[-1] > highs[-2] and lows[-1] > lows[-2]:
            return "UP"
            
        # Downtrend: LH + LL
        if highs[-1] < highs[-2] and lows[-1] < lows[-2]:
            return "DOWN"
            
        return "NEUTRAL"

    def _determine_phase(self, swings: List[SwingPoint], current_price: float, trend: str) -> str:
        """
        Impulse = Moving WITH trend
        Correction = Moving AGAINST trend
        """
        if trend == "NEUTRAL" or not swings:
            return "CORRECTION"
            
        last_swing = swings[-1]
        
        if trend == "UP":
            # If last confirmed swing was a HIGH, and we are moving down (price < high)
            # OR logic: typically ZigZag logs confirmed points. We are currently building the next leg.
            if last_swing.type == 'HIGH':
                return "CORRECTION" # Pulling back from High
            if last_swing.type == 'LOW':
                return "IMPULSE" # Moving up from Low
                
        if trend == "DOWN":
            if last_swing.type == 'LOW':
                return "CORRECTION" # Pulling up from Low
            if last_swing.type == 'HIGH':
                return "IMPULSE" # Moving down from High
                
        return "CORRECTION" # Default safe

    def _find_last_impulse(self, swings: List[SwingPoint], trend: str) -> Optional[Dict]:
        """
        Find the anchor points for the Fibonacci Retracement.
        Trend UP: Need Low -> High (the last completed impulse)
        """
        if len(swings) < 2:
            return None
            
        if trend == "UP":
            # We want the swing that created the Higher High?
            # Or the most recent confirmed impulse for us to retrace into.
            # If we are in Correction (from High), we need Low -> High
            
            # Find last High
            for i in range(len(swings)-1, 0, -1):
                s2 = swings[i]
                s1 = swings[i-1]
                if s2.type == 'HIGH' and s1.type == 'LOW':
                    return {'start': s1, 'end': s2}
                    
        elif trend == "DOWN":
            # Find last Low
             for i in range(len(swings)-1, 0, -1):
                s2 = swings[i]
                s1 = swings[i-1]
                if s2.type == 'LOW' and s1.type == 'HIGH':
                    return {'start': s1, 'end': s2}
                    
        return None
