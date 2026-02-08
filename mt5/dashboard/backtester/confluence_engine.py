"""
Confluence Engine

Main orchestrator for calculating 30-point confluence scores.
Mirrors MT5 EA's CalculateConfluenceScore() function.

Scoring Breakdown:
- Core SMC & Price Action: ~11 pts
- Institutional Concepts: ~7 pts
- Advanced Confluence: ~12 pts
TOTAL: ~30 pts
"""

import pandas as pd
import numpy as np
from typing import Dict, Any
from .technical_indicators import TechnicalIndicators
from .smc_modules import (
    StructureBreakDetector,
    OrderBlockDetector,
    FairValueGapDetector,
    LiquiditySweepDetector
)
from .institutional_concepts import (
    BreakerBlockAnalyzer,
    MacroWindowChecker,
    PowerOf3Detector,
    WyckoffAnalyzer
)
from .advanced_confluence import (
    VolumeProfileAnalyzer,
    DivergenceDetector,
    MultiTimeframeAnalyzer,
    FibonacciZoneCalculator,
    RegimeConfirmation
)


class ConfluenceEngine:
    """
    Main confluence scoring engine.

    Calculates confluence scores (0-30 pts) for buy/sell signals.
    """

    def __init__(self, params: Dict[str, Any]):
        """
        Initialize confluence engine with parameters.

        Args:
            params: Parameter dictionary from optimization
        """
        self.params = params
        self.use_smc = params.get('use_smc', True)
        self.use_institutional = params.get('use_institutional', True)
        self.use_advanced = params.get('use_advanced', True)

    def calculate_core_smc_score(self, df: pd.DataFrame, direction: int) -> pd.Series:
        """
        Calculate Core SMC & Price Action score (~11 pts).

        Components:
        - EMA price alignment (1.5 pts)
        - EMA slope alignment (1.0 pt)
        - Market structure (2.0 pts)
        - RSI extremes (1.5 pts)
        - RSI momentum (1.0 pt)
        - Displacement (1.5 pts)
        - Volatility ratio (1.5 pts)
        - Chop filter (1.0 pt)

        Args:
            df: DataFrame with indicators calculated
            direction: Trade direction (1=long, -1=short)

        Returns:
            Series with core SMC scores (0-11 pts)
        """
        score = pd.Series(0.0, index=df.index)

        # 1. EMA Price Alignment (1.5 pts)
        if direction == 1:
            ema_price_align = df['close'] > df['ema']
        else:
            ema_price_align = df['close'] < df['ema']
        score += ema_price_align.astype(float) * 1.5

        # 2. EMA Slope Alignment (1.0 pt)
        ema_min_slope = self.params.get('ema_min_slope', 0.0001)
        atr = df['atr']
        slope_threshold = atr * ema_min_slope

        if direction == 1:
            slope_align = df['ema_slope'] > slope_threshold
        else:
            slope_align = df['ema_slope'] < -slope_threshold
        score += slope_align.astype(float) * 1.0

        # 3. Market Structure (2.0 pts)
        swing_lookback = self.params.get('swing_lookback', 10)
        structure_score = self._calculate_market_structure_score(df, direction, swing_lookback)
        score += structure_score

        # 4. RSI Extremes (regime aware) (1.5 pts)
        rsi_oversold = self.params.get('rsi_oversold', 30)
        rsi_overbought = self.params.get('rsi_overbought', 70)

        regime = df['regime'] if 'regime' in df.columns else pd.Series(0, index=df.index)
        rsi = df['rsi']

        rsi_score = pd.Series(0.0, index=df.index)

        # TREND regime (1)
        trend_mask = regime == 1
        if direction == 1:
            rsi_score.loc[trend_mask & (rsi < 50) & (rsi > 30)] = 1.5
        else:
            rsi_score.loc[trend_mask & (rsi > 50) & (rsi < 70)] = 1.5

        # RANGE regime (0)
        range_mask = regime == 0
        if direction == 1:
            rsi_score.loc[range_mask & (rsi <= rsi_oversold)] = 1.5
        else:
            rsi_score.loc[range_mask & (rsi >= rsi_overbought)] = 1.5

        score += rsi_score

        # 5. RSI Momentum (1.0 pt)
        if self.params.get('rsi_momentum', True):
            if direction == 1:
                rsi_mom = df['rsi'] > df['rsi_prev']
            else:
                rsi_mom = df['rsi'] < df['rsi_prev']
            score += rsi_mom.astype(float) * 1.0

        # 6. Displacement (1.5 pts)
        displacement = TechnicalIndicators.check_displacement(
            df, df['ema'], df['atr'], direction, multiplier=2.0
        )
        score += displacement.astype(float) * 1.5

        # 7. Volatility Ratio (1.5 pts)
        atr_ratio = df['atr'] / df['atr_ma'].replace(0, np.nan)
        valid_volatility = (atr_ratio >= 0.8) & (atr_ratio <= 1.3)
        score += valid_volatility.astype(float) * 1.5

        # 8. Chop Filter (1.0 pt) - penalize low volatility
        choppy = TechnicalIndicators.check_chop_filter(df['atr'], df['atr_ma'], min_ratio=0.5)
        not_choppy = ~choppy
        score += not_choppy.astype(float) * 1.0

        return score

    def _calculate_market_structure_score(self, df: pd.DataFrame, direction: int,
                                         lookback: int) -> pd.Series:
        """
        Calculate market structure score (0-2.0 pts).

        Args:
            df: DataFrame with OHLCV data
            direction: Trade direction
            lookback: Swing lookback period

        Returns:
            Series with structure scores
        """
        score = pd.Series(0.0, index=df.index)

        for i in range(lookback, len(df)):
            highest_bar_idx = df['high'].iloc[max(0, i-lookback):i].idxmax()
            lowest_bar_idx = df['low'].iloc[max(0, i-lookback):i].idxmin()

            # Get relative positions
            highest_pos = df.index.get_loc(highest_bar_idx) if highest_bar_idx in df.index else i
            lowest_pos = df.index.get_loc(lowest_bar_idx) if lowest_bar_idx in df.index else i

            # Calculate structure range
            struct_range = df['high'].iloc[max(0, i-lookback):i].max() - df['low'].iloc[max(0, i-lookback):i].min()
            atr = df['atr'].iloc[i] if not pd.isna(df['atr'].iloc[i]) else 0

            valid_structure = struct_range >= atr * 2.0 if atr > 0 else False

            if not valid_structure:
                continue

            # Bullish structure: Low before high
            if direction == 1 and lowest_pos < highest_pos:
                score.iloc[i] = 2.0

            # Bearish structure: High before low
            if direction == -1 and highest_pos < lowest_pos:
                score.iloc[i] = 2.0

        return score

    def calculate_institutional_score(self, df: pd.DataFrame, direction: int) -> pd.Series:
        """
        Calculate Institutional Concepts score (~7 pts).

        Components:
        - Structure breaks (0-1.5 pts)
        - Order blocks (0-2.25 pts)
        - Fair value gaps (0-1.0 pts)
        - Liquidity sweeps (0-2.25 pts)
        - Breaker blocks (0-2.0 pts)
        - Macro windows (0-1.5 pts)
        - Power of 3 (0-2.0 pts)
        - Wyckoff (0-1.5 pts)

        Args:
            df: DataFrame with indicators calculated
            direction: Trade direction (1=long, -1=short)

        Returns:
            Series with institutional scores (0-7+ pts)
        """
        if not self.use_institutional and not self.use_smc:
            return pd.Series(0.0, index=df.index)

        score = pd.Series(0.0, index=df.index)

        # Structure breaks
        structure_score = StructureBreakDetector.get_confluence_score(df, direction, self.params)
        score += structure_score

        # Order blocks
        ob_score = OrderBlockDetector.get_confluence_score(df, direction, self.params)
        score += ob_score

        # Fair value gaps
        fvg_score = FairValueGapDetector.get_confluence_score(df, direction, self.params)
        score += fvg_score

        # Liquidity sweeps
        liquidity_score = LiquiditySweepDetector.get_confluence_score(df, direction, self.params)
        score += liquidity_score

        # Breaker blocks
        breaker_score = BreakerBlockAnalyzer.get_confluence_score(df, direction, self.params)
        score += breaker_score

        # Macro windows
        macro_score = MacroWindowChecker.get_confluence_score(df, direction, self.params)
        score += macro_score

        # Power of 3
        po3_score = PowerOf3Detector.get_confluence_score(df, direction, self.params)
        score += po3_score

        # Wyckoff
        wyckoff_score = WyckoffAnalyzer.get_confluence_score(df, direction, self.params)
        score += wyckoff_score

        return score

    def calculate_advanced_score(self, df: pd.DataFrame, direction: int) -> pd.Series:
        """
        Calculate Advanced Confluence score (~12 pts).

        Components:
        - Volume profile (0-2.5 pts)
        - Multi-timeframe (0-2.0 pts)
        - Divergence (0-1.5 pts)
        - Fibonacci zones (0-1.5 pts)
        - Regime confirmation (0-1.0 pt)

        Args:
            df: DataFrame with indicators calculated
            direction: Trade direction (1=long, -1=short)

        Returns:
            Series with advanced scores (0-12+ pts)
        """
        if not self.use_advanced:
            return pd.Series(0.0, index=df.index)

        score = pd.Series(0.0, index=df.index)

        # Volume profile
        volume_score = VolumeProfileAnalyzer.get_confluence_score(df, direction, self.params)
        score += volume_score

        # Multi-timeframe (expensive, only if enabled)
        if self.params.get('use_mtf', True):
            mtf_score = MultiTimeframeAnalyzer.get_confluence_score(df, direction, self.params)
            score += mtf_score

        # Divergence
        divergence_score = DivergenceDetector.get_confluence_score(df, direction, self.params)
        score += divergence_score

        # Fibonacci zones
        fib_score = FibonacciZoneCalculator.get_confluence_score(df, direction, self.params)
        score += fib_score

        # Regime confirmation
        regime_score = RegimeConfirmation.get_confluence_score(df, direction, self.params)
        score += regime_score

        return score

    def calculate_confluence_score(self, df: pd.DataFrame, direction: int,
                                  params: Dict[str, Any]) -> pd.Series:
        """
        Calculate total confluence score (0-30 pts).

        Args:
            df: DataFrame with OHLCV data (indicators will be calculated)
            direction: Trade direction (1=long, -1=short)
            params: Parameter dictionary (can override self.params)

        Returns:
            Series with total confluence scores (0-30 pts)
        """
        # Update params if provided
        if params:
            self.params = params

        # Calculate all indicators if not already present
        if 'rsi' not in df.columns or 'ema' not in df.columns:
            df = TechnicalIndicators.calculate_all_indicators(df, self.params)

        # Calculate component scores
        core_score = self.calculate_core_smc_score(df, direction)
        institutional_score = self.calculate_institutional_score(df, direction)
        advanced_score = self.calculate_advanced_score(df, direction)

        # Total score
        total_score = core_score + institutional_score + advanced_score

        return total_score

    def calculate_scores_with_breakdown(self, df: pd.DataFrame, direction: int) -> Dict[str, pd.Series]:
        """
        Calculate confluence scores with component breakdown.

        Args:
            df: DataFrame with OHLCV data
            direction: Trade direction (1=long, -1=short)

        Returns:
            Dictionary with score breakdown
        """
        # Calculate all indicators if not already present
        if 'rsi' not in df.columns or 'ema' not in df.columns:
            df = TechnicalIndicators.calculate_all_indicators(df, self.params)

        # Calculate component scores
        core_score = self.calculate_core_smc_score(df, direction)
        institutional_score = self.calculate_institutional_score(df, direction)
        advanced_score = self.calculate_advanced_score(df, direction)
        total_score = core_score + institutional_score + advanced_score

        return {
            'core_smc': core_score,
            'institutional': institutional_score,
            'advanced': advanced_score,
            'total': total_score
        }
