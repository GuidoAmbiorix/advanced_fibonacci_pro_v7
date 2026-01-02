"""
============================================================================
Volume Profile v1.0 - VPVR/POC/Value Area Analysis
============================================================================
Volume Profile analysis for institutional entry zone detection.

Key concepts:
- POC (Point of Control): Price level with highest volume
- Value Area: Range where ~70% of volume occurred
- VAH (Value Area High) / VAL (Value Area Low)
- HVN (High Volume Node) / LVN (Low Volume Node)

Note: For forex/CFD where real volume isn't available, we use
tick volume as a proxy, which correlates reasonably well with
actual volume for liquid pairs.
"""

import pandas as pd
import numpy as np
from typing import Dict, List, Tuple, Optional
from loguru import logger


class VolumeProfileAnalyzer:
    """
    Volume Profile analysis for institutional trading.
    Uses tick volume to approximate real volume distribution.
    """
    
    def __init__(self, config: Dict):
        """
        Initialize with slot configuration.
        
        Args:
            config: Slot config dict with:
                - enable_volume_profile: bool
                - vp_lookback: int (default 100 bars)
                - vp_num_bins: int (default 24 price levels)
                - vp_value_area_pct: float (default 0.70 = 70%)
        """
        self.enabled = config.get('enable_volume_profile', False)
        self.lookback = config.get('vp_lookback', 100)
        self.num_bins = config.get('vp_num_bins', 24)
        self.value_area_pct = config.get('vp_value_area_pct', 0.70)
    
    def calculate_profile(self, df: pd.DataFrame) -> Dict:
        """
        Calculate volume profile from OHLCV data.
        
        Returns:
            Dict with:
                - poc: float (Point of Control price)
                - vah: float (Value Area High)
                - val: float (Value Area Low)
                - profile: List[Dict] (binned volume distribution)
                - hvn: List[float] (High Volume Nodes)
                - lvn: List[float] (Low Volume Nodes)
        """
        if not self.enabled or df is None or len(df) < self.lookback:
            return self._empty_profile()
        
        # Use recent data
        data = df.tail(self.lookback).copy()
        
        # Get price range
        price_min = data['low'].min()
        price_max = data['high'].max()
        
        if price_max == price_min:
            return self._empty_profile()
        
        # Create price bins
        bin_size = (price_max - price_min) / self.num_bins
        bins = np.linspace(price_min, price_max, self.num_bins + 1)
        
        # Distribute volume across price levels
        # For each candle, assign volume proportionally to price levels it touched
        volume_at_price = np.zeros(self.num_bins)
        
        for _, row in data.iterrows():
            candle_low = row['low']
            candle_high = row['high']
            candle_vol = row['tick_volume'] if 'tick_volume' in row else row.get('volume', 1)
            
            # Find bins this candle touches
            for i in range(self.num_bins):
                bin_low = bins[i]
                bin_high = bins[i + 1]
                
                # Check if candle overlaps with this bin
                if candle_high >= bin_low and candle_low <= bin_high:
                    # Calculate overlap ratio
                    overlap_low = max(candle_low, bin_low)
                    overlap_high = min(candle_high, bin_high)
                    candle_range = candle_high - candle_low if candle_high > candle_low else 1
                    overlap_ratio = (overlap_high - overlap_low) / candle_range
                    
                    volume_at_price[i] += candle_vol * overlap_ratio
        
        # Find POC (highest volume bin)
        poc_bin = np.argmax(volume_at_price)
        poc = (bins[poc_bin] + bins[poc_bin + 1]) / 2
        
        # Calculate Value Area (70% of total volume)
        total_volume = volume_at_price.sum()
        target_volume = total_volume * self.value_area_pct
        
        # Start from POC and expand outward
        va_bins = {poc_bin}
        current_volume = volume_at_price[poc_bin]
        
        lower_idx = poc_bin - 1
        upper_idx = poc_bin + 1
        
        while current_volume < target_volume:
            lower_vol = volume_at_price[lower_idx] if lower_idx >= 0 else 0
            upper_vol = volume_at_price[upper_idx] if upper_idx < self.num_bins else 0
            
            if lower_vol >= upper_vol and lower_idx >= 0:
                va_bins.add(lower_idx)
                current_volume += lower_vol
                lower_idx -= 1
            elif upper_idx < self.num_bins:
                va_bins.add(upper_idx)
                current_volume += upper_vol
                upper_idx += 1
            else:
                break
        
        # Calculate VAH and VAL
        va_bin_list = sorted(va_bins)
        val = bins[va_bin_list[0]]
        vah = bins[va_bin_list[-1] + 1]
        
        # Find HVN (High Volume Nodes) - bins with volume > mean + 1 std
        mean_vol = np.mean(volume_at_price)
        std_vol = np.std(volume_at_price)
        hvn_threshold = mean_vol + std_vol
        hvn = [(bins[i] + bins[i + 1]) / 2 for i in range(self.num_bins) 
               if volume_at_price[i] > hvn_threshold]
        
        # Find LVN (Low Volume Nodes) - bins with volume < mean - 0.5 std
        lvn_threshold = mean_vol - 0.5 * std_vol
        lvn = [(bins[i] + bins[i + 1]) / 2 for i in range(self.num_bins) 
               if volume_at_price[i] < lvn_threshold and volume_at_price[i] > 0]
        
        # Build profile for visualization
        profile = []
        for i in range(self.num_bins):
            profile.append({
                'price': (bins[i] + bins[i + 1]) / 2,
                'volume': float(volume_at_price[i]),
                'pct': float(volume_at_price[i] / total_volume * 100) if total_volume > 0 else 0,
                'is_poc': i == poc_bin,
                'in_value_area': i in va_bins
            })
        
        return {
            'poc': round(float(poc), 5),
            'vah': round(float(vah), 5),
            'val': round(float(val), 5),
            'hvn': [round(float(h), 5) for h in hvn[:3]],  # Top 3 HVN
            'lvn': [round(float(l), 5) for l in lvn[:3]],   # Top 3 LVN
            'profile': profile,
            'total_volume': float(total_volume)
        }
    
    def _empty_profile(self) -> Dict:
        """Return empty profile structure."""
        return {
            'poc': None,
            'vah': None,
            'val': None,
            'hvn': [],
            'lvn': [],
            'profile': [],
            'total_volume': 0
        }
    
    def is_near_poc(self, current_price: float, df: pd.DataFrame, tolerance_atr: float = 0.5) -> Tuple[bool, float]:
        """
        Check if current price is near POC.
        
        Args:
            current_price: Current market price
            df: OHLCV data
            tolerance_atr: How close to POC (in ATR units)
        
        Returns:
            Tuple of (is_near: bool, distance: float)
        """
        profile = self.calculate_profile(df)
        
        if profile['poc'] is None:
            return False, float('inf')
        
        # Calculate ATR for tolerance
        if 'atr' in df.columns:
            atr = df['atr'].iloc[-1]
        else:
            tr = pd.concat([
                df['high'] - df['low'],
                (df['high'] - df['close'].shift()).abs(),
                (df['low'] - df['close'].shift()).abs()
            ], axis=1).max(axis=1)
            atr = tr.rolling(14).mean().iloc[-1]
        
        distance = abs(current_price - profile['poc'])
        tolerance = atr * tolerance_atr
        
        return distance <= tolerance, distance
    
    def get_entry_zone_quality(self, entry_price: float, direction: str, df: pd.DataFrame) -> Dict:
        """
        Evaluate entry zone quality based on volume profile.
        
        Args:
            entry_price: Proposed entry price
            direction: 'BUY' or 'SELL'
            df: OHLCV data
        
        Returns:
            Dict with quality score and reasoning
        """
        if not self.enabled:
            return {'quality': 'NEUTRAL', 'score': 0, 'reason': 'Volume Profile disabled'}
        
        profile = self.calculate_profile(df)
        
        if profile['poc'] is None:
            return {'quality': 'NEUTRAL', 'score': 0, 'reason': 'Insufficient data'}
        
        poc = profile['poc']
        vah = profile['vah']
        val = profile['val']
        
        score = 0
        reasons = []
        
        if direction == 'BUY':
            # Good: Entry near VAL (support area)
            if entry_price <= val:
                score += 2
                reasons.append('Entry at Value Area Low (support)')
            elif entry_price <= poc:
                score += 1
                reasons.append('Entry below POC')
            # Bad: Entry above VAH (overbought area)
            elif entry_price >= vah:
                score -= 2
                reasons.append('Entry at Value Area High (resistance)')
                
        elif direction == 'SELL':
            # Good: Entry near VAH (resistance area)
            if entry_price >= vah:
                score += 2
                reasons.append('Entry at Value Area High (resistance)')
            elif entry_price >= poc:
                score += 1
                reasons.append('Entry above POC')
            # Bad: Entry below VAL (oversold area)
            elif entry_price <= val:
                score -= 2
                reasons.append('Entry at Value Area Low (support)')
        
        # Quality rating
        if score >= 2:
            quality = 'EXCELLENT'
        elif score >= 1:
            quality = 'GOOD'
        elif score >= 0:
            quality = 'NEUTRAL'
        else:
            quality = 'POOR'
        
        return {
            'quality': quality,
            'score': score,
            'reason': ', '.join(reasons) if reasons else 'Standard entry',
            'poc': poc,
            'vah': vah,
            'val': val
        }
