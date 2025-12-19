"""
Enhanced Confluence Scoring System
Separates continuation vs reversal signals with proper validation
Based on professional ICT best practices 2024-2025
"""

from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple
from loguru import logger


@dataclass
class ConfluenceBreakdown:
    """Detailed breakdown of confluence score by category"""
    # Core structure (MANDATORY)
    structure_score: int = 0
    structure_type: str = ""  # "BOS", "CHOCH", or ""

    # Categories
    price_action_score: int = 0
    fibonacci_score: int = 0
    volume_score: int = 0
    liquidity_score: int = 0
    timeframe_score: int = 0
    zone_score: int = 0

    # Details
    factors: Dict[str, int] = None
    trade_type: str = ""  # "CONTINUATION", "REVERSAL", or ""

    def __post_init__(self):
        if self.factors is None:
            self.factors = {}

    @property
    def total_score(self) -> int:
        """Calculate total confluence score"""
        return (
            self.structure_score +
            self.price_action_score +
            self.fibonacci_score +
            self.volume_score +
            self.liquidity_score +
            self.timeframe_score +
            self.zone_score
        )

    def is_valid(self) -> Tuple[bool, str]:
        """
        Validate if this is a tradeable signal

        Returns:
            Tuple of (is_valid, reason)
        """
        # Rule 1: Structure helps but not mandatory (RELAXED)
        # if self.structure_score == 0:
        #     return False, "No market structure (BOS/CHoCH)"

        # Rule 2: CONTINUATION requirements (IMPROVED)
        if self.trade_type == "CONTINUATION":
            # Allow if NO CHoCH (don't strictly require BOS)
            if self.structure_type == "CHOCH":
                return False, "Continuation cannot have CHoCH (reversal signal)"

            # Must have EITHER:
            # - Price action (OB/FVG) OR
            # - Fibonacci OR
            # - Displacement (new institutional factor)
            has_setup = (
                self.price_action_score > 0 or
                self.fibonacci_score > 0 or
                'Displacement' in self.factors
            )

            if not has_setup:
                return False, "Continuation needs price action OR fibonacci OR displacement"

            # Dynamic threshold based on factors present
            # If has displacement, allow lower score (displacement is strong)
            min_score = 7 if 'Displacement' not in self.factors else 6

            if self.total_score < min_score:
                return False, f"Continuation score {self.total_score} < {min_score} minimum"

            return True, "Valid continuation setup"

        # Rule 3: REVERSAL requirements (STRICTER - Higher bar)
        elif self.trade_type == "REVERSAL":
            if self.structure_type != "CHOCH":
                return False, "Reversal requires CHoCH, not BOS"

            # Reversals need STRONG confluence (at least 2 of 3):
            # 1. Liquidity sweep (preferably external)
            # 2. Fibonacci level
            # 3. Displacement

            factors_present = 0
            if self.liquidity_score > 0:
                factors_present += 1
            if self.fibonacci_score > 0:
                factors_present += 1
            if 'Displacement' in self.factors:
                factors_present += 1

            if factors_present < 2:
                return False, "Reversal needs 2+ of: liquidity/fibonacci/displacement"

            # Higher minimum score for reversals
            min_score = 8

            if self.total_score < min_score:
                return False, f"Reversal score {self.total_score} < {min_score} minimum"

            return True, "Valid reversal setup"

        return False, "Unknown trade type"


class EnhancedConfluenceScorer:
    """
    Enhanced confluence scoring with proper separation and validation

    Improvements:
    1. Separates continuation vs reversal signals
    2. Multi-timeframe Fibonacci confluence
    3. Golden Pocket detection (0.618-0.786)
    4. Category-based minimum requirements
    5. Proper weight distribution
    """

    # Enhanced scoring weights based on ICT best practices + 2024-2025 research
    # Sources: LuxAlgo, MentFX, ICT OTE V3, TradingFinder
    WEIGHTS = {
        # CORE STRUCTURE (Pick ONE direction)
        'BOS_CONTINUATION': 3,        # Break of structure (trend continuation) - Reduced from 4
        'CHOCH_REVERSAL': 4,          # Change of character (reversal) - INCREASED (reversals more important)

        # PRICE ACTION (Key levels) - Now with quality scoring
        'ORDER_BLOCK': 2,             # At OB (base score, quality adds more)
        'ORDER_BLOCK_HQ': 4,          # High quality OB (quality >= 4)
        'FVG': 2,                     # At FVG (base score)
        'FVG_HQ': 3,                  # High quality FVG (quality >= 4)
        'OB_FVG_CONFLUENCE': 5,       # BOTH OB + FVG together (powerful!)

        # 🔥 NEW: DISPLACEMENT (Critical factor)
        'DISPLACEMENT': 3,            # Institutional impulse detected

        # FIBONACCI (Multi-TF confluence)
        'FIB_SINGLE_TF': 2,           # One timeframe (INCREASED from 1)
        'FIB_2TF_CONFLUENCE': 3,      # 2 timeframes agree (+40% success)
        'FIB_3TF_CONFLUENCE': 5,      # 3 timeframes agree (rare, very strong!)
        'GOLDEN_POCKET': 2,           # 0.618-0.786 zone (bonus)

        # LIQUIDITY (Smart money footprint) - Now differentiated
        'LIQUIDITY_SWEEP_EXTERNAL': 3,   # External liquidity sweep (STRONG)
        'LIQUIDITY_SWEEP_INTERNAL': 1,   # Internal liquidity (weak)
        'STOP_HUNT': 2,               # Wick manipulation + reversal
        'EQH_EQL_PRESENT': 2,         # Equal highs/lows detected

        # 🔥 NEW: SMT DIVERGENCE (When implemented)
        'SMT_DIVERGENCE': 4,          # Smart Money divergence (future)

        # VOLUME (Institutional activity)
        'DELTA_VOLUME': 2,            # Strong buy/sell pressure
        'POC_ALIGNED': 1,             # At POC (one direction only!)
        'VOLUME_SPIKE': 1,            # High volume confirmation

        # TIMEFRAME (HTF bias) - INCREASED importance
        'HTF_ALIGNMENT': 4,           # Higher timeframe confirms (was 3)
        'HTF_IMBALANCE': 3,           # HTF FVG aligned (NEW)

        # ZONES (Context)
        'PREMIUM_DISCOUNT': 1,        # In correct zone
        'SESSION_LEVEL': 1,           # At key session level

        # 🔥 NEW: FILTERS (Binary filters - must pass)
        'KILLZONE_ACTIVE': 2,         # In ICT killzone
        'ATR_REGIME_OK': 1,           # Suitable volatility

        # 🔥 NEW: MARKET STRUCTURE QUALITY
        'MS_QUALITY_HIGH': 2,         # High quality BOS/CHoCH (quality >= 4)
    }

    def __init__(self):
        """Initialize Enhanced Confluence Scorer"""
        logger.info("EnhancedConfluenceScorer initialized")

    def calculate_fibonacci_confluence(
        self,
        current_price: float,
        fib_h1: Optional[Dict],
        fib_h4: Optional[Dict],
        fib_d1: Optional[Dict],
        atr_value: float,
        tolerance_in_atr: float = 1.0
    ) -> Tuple[int, bool, int, Dict]:
        """
        Calculate multi-timeframe Fibonacci confluence with PROPER price validation

        Args:
            current_price: Current market price
            fib_h1: H1 Fibonacci levels dict {'level': '0.618', 'price': 1.2345}
            fib_h4: H4 Fibonacci levels dict (optional)
            fib_d1: D1 Fibonacci levels dict (optional)
            atr_value: ATR value in price units
            tolerance_in_atr: Tolerance multiplier (default 1.0 ATR)

        Returns:
            Tuple of (fib_score, is_golden, timeframes_matched, matches_info)

        References:
            - ACY: Multi-timeframe Fibonacci requires ACTUAL price proximity
            - Tolerance should be ATR-based for volatility adaptation
        """
        matches = {}
        timeframes_matched = 0
        is_golden = False
        fib_score = 0

        # Calculate tolerance in price units
        tolerance_price = atr_value * tolerance_in_atr

        def check_level_match(fib_obj: Optional[Dict], tf_name: str) -> Optional[Dict]:
            """Helper to validate Fibonacci level proximity"""
            if not fib_obj:
                return None
            if 'level' not in fib_obj or 'price' not in fib_obj:
                logger.warning(f"❌ {tf_name} Fib missing 'level' or 'price' keys: {fib_obj}")
                return None

            lvl = str(fib_obj['level'])
            lvl_price = float(fib_obj['price'])
            diff = abs(current_price - lvl_price)
            matched = diff <= tolerance_price

            return {
                'level': lvl,
                'price': lvl_price,
                'diff': diff,
                'tolerance': tolerance_price,
                'matched': matched
            }

        # ✅ FIX: Check H1 with PRICE PROXIMITY (not just presence)
        h1_info = check_level_match(fib_h1, 'H1')
        if h1_info:
            matches['H1'] = h1_info
            if h1_info['matched']:
                timeframes_matched += 1
                # Check golden pocket (0.618-0.786)
                if h1_info['level'] in ['0.618', '0.786']:
                    is_golden = True
                logger.debug(f"✅ H1 Fib MATCH: {h1_info['level']}@{h1_info['price']:.5f}, diff={h1_info['diff']:.5f}")
            else:
                logger.debug(f"❌ H1 Fib no match: {h1_info['level']}@{h1_info['price']:.5f}, diff={h1_info['diff']:.5f} > tol={tolerance_price:.5f}")

        # Check H4 confluence
        h4_info = check_level_match(fib_h4, 'H4')
        if h4_info:
            matches['H4'] = h4_info
            if h4_info['matched']:
                timeframes_matched += 1
                logger.debug(f"✅ H4 Fib MATCH: {h4_info['level']}@{h4_info['price']:.5f}")

        # Check D1 confluence
        d1_info = check_level_match(fib_d1, 'D1')
        if d1_info:
            matches['D1'] = d1_info
            if d1_info['matched']:
                timeframes_matched += 1
                logger.debug(f"✅ D1 Fib MATCH: {d1_info['level']}@{d1_info['price']:.5f}")

        # Calculate score based on confluence
        if timeframes_matched == 1:
            fib_score = self.WEIGHTS['FIB_SINGLE_TF']
        elif timeframes_matched == 2:
            fib_score = self.WEIGHTS['FIB_2TF_CONFLUENCE']
        elif timeframes_matched >= 3:
            fib_score = self.WEIGHTS['FIB_3TF_CONFLUENCE']

        # Add golden pocket bonus
        if is_golden and timeframes_matched >= 1:
            fib_score += self.WEIGHTS['GOLDEN_POCKET']
            logger.debug(f"🟡 Golden Pocket bonus applied: +{self.WEIGHTS['GOLDEN_POCKET']}")

        # Summary log
        if timeframes_matched > 0:
            logger.debug(f"📊 Fib Confluence: {timeframes_matched} TF(s) matched, score={fib_score}, golden={is_golden}")

        return fib_score, is_golden, timeframes_matched, matches

    def score_continuation(
        self,
        has_bos: bool,
        at_ob: bool,
        at_fvg: bool,
        fib_score: int,
        has_delta_volume: bool,
        has_volume_spike: bool,
        at_poc: bool,
        poc_rising: bool,
        htf_aligned: bool,
        in_discount_zone: bool,
        at_session_level: bool,
        # NEW parameters
        has_displacement: bool = False,
        ob_quality: int = 0,
        fvg_quality: int = 0,
        ms_quality: int = 0,
        has_eqh_eql: bool = False,
        in_killzone: bool = False,
        atr_regime_ok: bool = True,
        htf_imbalance: bool = False,
        liquidity_type: str = "NONE"  # "EXTERNAL", "INTERNAL", "NONE"
    ) -> ConfluenceBreakdown:
        """
        Score a CONTINUATION trade setup (ENHANCED)

        Continuation = BOS + Price retracement to support (OB/FVG/Fib) + Displacement
        """
        breakdown = ConfluenceBreakdown(trade_type="CONTINUATION")

        # Structure
        if has_bos:
            breakdown.structure_score = self.WEIGHTS['BOS_CONTINUATION']
            breakdown.structure_type = "BOS"
            breakdown.factors['BOS'] = self.WEIGHTS['BOS_CONTINUATION']

            # Add MS quality bonus
            if ms_quality >= 4:
                breakdown.structure_score += self.WEIGHTS['MS_QUALITY_HIGH']
                breakdown.factors['MS Quality'] = self.WEIGHTS['MS_QUALITY_HIGH']

        # 🔥 NEW: Displacement (Critical for continuations)
        if has_displacement:
            breakdown.price_action_score += self.WEIGHTS['DISPLACEMENT']
            breakdown.factors['Displacement'] = self.WEIGHTS['DISPLACEMENT']

        # Price Action (with quality scoring)
        if at_ob and at_fvg:
            # BOTH OB + FVG = very strong!
            breakdown.price_action_score += self.WEIGHTS['OB_FVG_CONFLUENCE']
            breakdown.factors['OB+FVG Confluence'] = self.WEIGHTS['OB_FVG_CONFLUENCE']
        elif at_ob:
            # Use quality-based scoring
            if ob_quality >= 4:
                breakdown.price_action_score += self.WEIGHTS['ORDER_BLOCK_HQ']
                breakdown.factors['HQ Order Block'] = self.WEIGHTS['ORDER_BLOCK_HQ']
            else:
                breakdown.price_action_score += self.WEIGHTS['ORDER_BLOCK']
                breakdown.factors['Order Block'] = self.WEIGHTS['ORDER_BLOCK']
        elif at_fvg:
            # Use quality-based scoring
            if fvg_quality >= 4:
                breakdown.price_action_score += self.WEIGHTS['FVG_HQ']
                breakdown.factors['HQ FVG'] = self.WEIGHTS['FVG_HQ']
            else:
                breakdown.price_action_score += self.WEIGHTS['FVG']
                breakdown.factors['FVG'] = self.WEIGHTS['FVG']

        # Fibonacci
        breakdown.fibonacci_score = fib_score
        if fib_score > 0:
            breakdown.factors['Fibonacci'] = fib_score

        # 🔥 NEW: Liquidity (differentiated)
        if liquidity_type == "EXTERNAL":
            breakdown.liquidity_score += self.WEIGHTS['LIQUIDITY_SWEEP_EXTERNAL']
            breakdown.factors['External Liquidity'] = self.WEIGHTS['LIQUIDITY_SWEEP_EXTERNAL']
        elif liquidity_type == "INTERNAL":
            breakdown.liquidity_score += self.WEIGHTS['LIQUIDITY_SWEEP_INTERNAL']
            breakdown.factors['Internal Liquidity'] = self.WEIGHTS['LIQUIDITY_SWEEP_INTERNAL']

        if has_eqh_eql:
            breakdown.liquidity_score += self.WEIGHTS['EQH_EQL_PRESENT']
            breakdown.factors['EQH/EQL'] = self.WEIGHTS['EQH_EQL_PRESENT']

        # Volume
        if has_delta_volume:
            breakdown.volume_score += self.WEIGHTS['DELTA_VOLUME']
            breakdown.factors['Delta Volume'] = self.WEIGHTS['DELTA_VOLUME']

        if has_volume_spike:
            breakdown.volume_score += self.WEIGHTS['VOLUME_SPIKE']
            breakdown.factors['Volume Spike'] = self.WEIGHTS['VOLUME_SPIKE']

        if at_poc and poc_rising:
            breakdown.volume_score += self.WEIGHTS['POC_ALIGNED']
            breakdown.factors['POC Rising'] = self.WEIGHTS['POC_ALIGNED']

        # Timeframe (enhanced)
        if htf_aligned:
            breakdown.timeframe_score += self.WEIGHTS['HTF_ALIGNMENT']
            breakdown.factors['HTF Aligned'] = self.WEIGHTS['HTF_ALIGNMENT']

        if htf_imbalance:
            breakdown.timeframe_score += self.WEIGHTS['HTF_IMBALANCE']
            breakdown.factors['HTF Imbalance'] = self.WEIGHTS['HTF_IMBALANCE']

        # Zones
        if in_discount_zone:
            breakdown.zone_score += self.WEIGHTS['PREMIUM_DISCOUNT']
            breakdown.factors['Discount Zone'] = self.WEIGHTS['PREMIUM_DISCOUNT']

        if at_session_level:
            breakdown.zone_score += self.WEIGHTS['SESSION_LEVEL']
            breakdown.factors['Session Level'] = self.WEIGHTS['SESSION_LEVEL']

        # 🔥 NEW: Filters (bonus points)
        if in_killzone:
            breakdown.zone_score += self.WEIGHTS['KILLZONE_ACTIVE']
            breakdown.factors['Killzone'] = self.WEIGHTS['KILLZONE_ACTIVE']

        if atr_regime_ok:
            breakdown.zone_score += self.WEIGHTS['ATR_REGIME_OK']
            breakdown.factors['ATR OK'] = self.WEIGHTS['ATR_REGIME_OK']

        return breakdown

    def score_reversal(
        self,
        has_choch: bool,
        at_ob: bool,
        at_fvg: bool,
        fib_score: int,
        has_liquidity_sweep: bool,
        has_stop_hunt: bool,
        has_delta_volume: bool,
        htf_aligned: bool,
        in_correct_zone: bool,
        # NEW parameters
        has_displacement: bool = False,
        ob_quality: int = 0,
        fvg_quality: int = 0,
        ms_quality: int = 0,
        has_eqh_eql: bool = False,
        in_killzone: bool = False,
        atr_regime_ok: bool = True,
        htf_imbalance: bool = False,
        liquidity_type: str = "NONE"
    ) -> ConfluenceBreakdown:
        """
        Score a REVERSAL trade setup (ENHANCED - STRICTER)

        Reversal = CHoCH + EXTERNAL Liquidity grab + Fibonacci + Displacement
        Higher requirements than continuation - needs strong confluence
        """
        breakdown = ConfluenceBreakdown(trade_type="REVERSAL")

        # Structure (MANDATORY for reversal)
        if has_choch:
            breakdown.structure_score = self.WEIGHTS['CHOCH_REVERSAL']
            breakdown.structure_type = "CHOCH"
            breakdown.factors['CHoCH'] = self.WEIGHTS['CHOCH_REVERSAL']

            # Add MS quality bonus
            if ms_quality >= 4:
                breakdown.structure_score += self.WEIGHTS['MS_QUALITY_HIGH']
                breakdown.factors['MS Quality'] = self.WEIGHTS['MS_QUALITY_HIGH']

        # 🔥 NEW: Displacement (IMPORTANT for reversals)
        if has_displacement:
            breakdown.price_action_score += self.WEIGHTS['DISPLACEMENT']
            breakdown.factors['Displacement'] = self.WEIGHTS['DISPLACEMENT']

        # Price Action (with quality scoring)
        if at_ob and at_fvg:
            breakdown.price_action_score += self.WEIGHTS['OB_FVG_CONFLUENCE']
            breakdown.factors['OB+FVG Confluence'] = self.WEIGHTS['OB_FVG_CONFLUENCE']
        elif at_ob:
            if ob_quality >= 4:
                breakdown.price_action_score += self.WEIGHTS['ORDER_BLOCK_HQ']
                breakdown.factors['HQ Order Block'] = self.WEIGHTS['ORDER_BLOCK_HQ']
            else:
                breakdown.price_action_score += self.WEIGHTS['ORDER_BLOCK']
                breakdown.factors['Order Block'] = self.WEIGHTS['ORDER_BLOCK']
        elif at_fvg:
            if fvg_quality >= 4:
                breakdown.price_action_score += self.WEIGHTS['FVG_HQ']
                breakdown.factors['HQ FVG'] = self.WEIGHTS['FVG_HQ']
            else:
                breakdown.price_action_score += self.WEIGHTS['FVG']
                breakdown.factors['FVG'] = self.WEIGHTS['FVG']

        # Fibonacci (IMPORTANT for reversals)
        breakdown.fibonacci_score = fib_score
        if fib_score > 0:
            breakdown.factors['Fibonacci'] = fib_score

        # 🔥 NEW: Liquidity (CRITICAL - prefer external)
        if has_liquidity_sweep:
            if liquidity_type == "EXTERNAL":
                breakdown.liquidity_score += self.WEIGHTS['LIQUIDITY_SWEEP_EXTERNAL']
                breakdown.factors['External Liquidity'] = self.WEIGHTS['LIQUIDITY_SWEEP_EXTERNAL']
            else:
                breakdown.liquidity_score += self.WEIGHTS['LIQUIDITY_SWEEP_INTERNAL']
                breakdown.factors['Internal Liquidity'] = self.WEIGHTS['LIQUIDITY_SWEEP_INTERNAL']

        if has_stop_hunt:
            breakdown.liquidity_score += self.WEIGHTS['STOP_HUNT']
            breakdown.factors['Stop Hunt'] = self.WEIGHTS['STOP_HUNT']

        if has_eqh_eql:
            breakdown.liquidity_score += self.WEIGHTS['EQH_EQL_PRESENT']
            breakdown.factors['EQH/EQL'] = self.WEIGHTS['EQH_EQL_PRESENT']

        # Volume
        if has_delta_volume:
            breakdown.volume_score += self.WEIGHTS['DELTA_VOLUME']
            breakdown.factors['Delta Volume'] = self.WEIGHTS['DELTA_VOLUME']

        # Timeframe (enhanced)
        if htf_aligned:
            breakdown.timeframe_score += self.WEIGHTS['HTF_ALIGNMENT']
            breakdown.factors['HTF Aligned'] = self.WEIGHTS['HTF_ALIGNMENT']

        if htf_imbalance:
            breakdown.timeframe_score += self.WEIGHTS['HTF_IMBALANCE']
            breakdown.factors['HTF Imbalance'] = self.WEIGHTS['HTF_IMBALANCE']

        # Zones
        if in_correct_zone:
            breakdown.zone_score += self.WEIGHTS['PREMIUM_DISCOUNT']
            breakdown.factors['Correct Zone'] = self.WEIGHTS['PREMIUM_DISCOUNT']

        # 🔥 NEW: Filters
        if in_killzone:
            breakdown.zone_score += self.WEIGHTS['KILLZONE_ACTIVE']
            breakdown.factors['Killzone'] = self.WEIGHTS['KILLZONE_ACTIVE']

        if atr_regime_ok:
            breakdown.zone_score += self.WEIGHTS['ATR_REGIME_OK']
            breakdown.factors['ATR OK'] = self.WEIGHTS['ATR_REGIME_OK']

        return breakdown
