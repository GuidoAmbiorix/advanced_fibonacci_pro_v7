# NEW ENHANCED CONFLUENCE METHOD - COMPLETE INTEGRATION
# This replaces _calculate_confluence_enhanced in trading_engine.py

def _calculate_confluence_enhanced(self, df: pd.DataFrame, bos_choch_data: Dict) -> Dict:
    """
    FULLY ENHANCED confluence calculation with ALL new factors

    Integrates:
    - Displacement detection
    - OB/FVG quality scoring
    - Market structure quality
    - Internal vs External liquidity
    - EQH/EQL detection
    - Killzones
    - ATR regime filter
    - SMT divergence (placeholder)

    Returns separate scores for CONTINUATION vs REVERSAL
    """
    current_price = df.iloc[-1]['close']
    current_low = df.iloc[-1]['low']
    current_high = df.iloc[-1]['high']
    current_time = df.iloc[-1]['time']
    atr = df.iloc[-1]['atr']

    # ===== RUN ALL DETECTORS =====

    # 🔥 NEW: Displacement
    displacement = self._detect_displacement(df)
    has_bull_displacement = displacement['bullish_displacement']
    has_bear_displacement = displacement['bearish_displacement']

    # 🔥 NEW: EQH/EQL
    eqh_eql = self._detect_equal_highs_lows(df)
    has_eqh = len(eqh_eql['eqh_levels']) > 0
    has_eql = len(eqh_eql['eql_levels']) > 0

    # 🔥 NEW: Killzone
    killzone = self._is_in_killzone(current_time)
    in_killzone = killzone['in_killzone']

    # 🔥 NEW: ATR Regime
    atr_regime = self._check_atr_regime(df)
    atr_ok = atr_regime['is_suitable']

    # 🔥 NEW: SMT Divergence (placeholder for now)
    smt = self._detect_smt_divergence(df)

    # 1. Structure
    has_bos_bull = bos_choch_data.get('bos_bullish', False) and bos_choch_data.get('bos_recent', False)
    has_bos_bear = bos_choch_data.get('bos_bearish', False) and bos_choch_data.get('bos_recent', False)
    has_choch_bull = bos_choch_data.get('choch_to_bullish', False)
    has_choch_bear = bos_choch_data.get('choch_to_bearish', False)

    # 🔥 NEW: Calculate Market Structure Quality
    bull_ms_quality = 0
    bear_ms_quality = 0
    if has_bos_bull or has_choch_bull:
        bull_ms_quality = self._calculate_bos_choch_quality(
            df, len(df) - 1, 'BOS_BULL' if has_bos_bull else 'CHOCH_BULL'
        )
    if has_bos_bear or has_choch_bear:
        bear_ms_quality = self._calculate_bos_choch_quality(
            df, len(df) - 1, 'BOS_BEAR' if has_bos_bear else 'CHOCH_BEAR'
        )

    # 2. Price Action with Quality Scoring
    bull_ob = None
    bear_ob = None
    bull_fvg = None
    bear_fvg = None
    bull_ob_quality = 0
    bear_ob_quality = 0
    bull_fvg_quality = 0
    bear_fvg_quality = 0

    # Find OB with quality
    for ob in self.bullish_obs:
        if not ob.is_mitigated and ob.bottom <= current_low <= ob.top:
            bull_ob = ob
            bull_ob_quality = ob.quality_score if hasattr(ob, 'quality_score') else 0
            break

    for ob in self.bearish_obs:
        if not ob.is_mitigated and ob.bottom <= current_high <= ob.top:
            bear_ob = ob
            bear_ob_quality = ob.quality_score if hasattr(ob, 'quality_score') else 0
            break

    # Find FVG with quality
    for fvg in self.bullish_fvgs:
        if not fvg.is_filled and fvg.bottom <= current_price <= fvg.top:
            bull_fvg = fvg
            bull_fvg_quality = fvg.quality_score if hasattr(fvg, 'quality_score') else 0
            break

    for fvg in self.bearish_fvgs:
        if not fvg.is_filled and fvg.bottom <= current_price <= fvg.top:
            bear_fvg = fvg
            bear_fvg_quality = fvg.quality_score if hasattr(fvg, 'quality_score') else 0
            break

    at_bullish_ob = bull_ob is not None
    at_bearish_ob = bear_ob is not None
    at_bullish_fvg = bull_fvg is not None
    at_bearish_fvg = bear_fvg is not None

    # 3. Fibonacci
    fib_data = self._calculate_fibonacci_levels(df)
    bull_fib_score = 0
    bear_fib_score = 0

    if fib_data['bullish_level']:
        is_golden = fib_data['is_golden_zone']
        bull_fib_score = self.confluence_scorer.WEIGHTS['FIB_SINGLE_TF']
        if is_golden:
            bull_fib_score += self.confluence_scorer.WEIGHTS['GOLDEN_POCKET']

    if fib_data['bearish_level']:
        is_golden = fib_data['is_golden_zone']
        bear_fib_score = self.confluence_scorer.WEIGHTS['FIB_SINGLE_TF']
        if is_golden:
            bear_fib_score += self.confluence_scorer.WEIGHTS['GOLDEN_POCKET']

    # Log Fibonacci
    if bull_fib_score > 0:
        level = fib_data.get('bullish_level', 'N/A')
        price = fib_data.get('bullish_price', 0)
        is_golden = fib_data.get('is_golden_zone', False)
        logger.debug(f"🟢 Bull Fibonacci Score: {bull_fib_score} (level: {level}@{price:.5f}, golden: {is_golden})")
    if bear_fib_score > 0:
        level = fib_data.get('bearish_level', 'N/A')
        price = fib_data.get('bearish_price', 0)
        is_golden = fib_data.get('is_golden_zone', False)
        logger.debug(f"🔴 Bear Fibonacci Score: {bear_fib_score} (level: {level}@{price:.5f}, golden: {is_golden})")

    # 4. Liquidity with Internal/External classification
    bull_sweep, bear_sweep = self._detect_liquidity_sweeps(df)
    stop_hunt = self._detect_stop_hunt(df)

    # 🔥 NEW: Classify liquidity type
    bull_liq_type = "NONE"
    bear_liq_type = "NONE"

    if bull_sweep and self.swing_lows:
        last_low = self.swing_lows[-1].price
        liq_type = self._check_internal_vs_external_liquidity(last_low, df)
        bull_liq_type = liq_type

    if bear_sweep and self.swing_highs:
        last_high = self.swing_highs[-1].price
        liq_type = self._check_internal_vs_external_liquidity(last_high, df)
        bear_liq_type = liq_type

    # 5. Volume
    delta_vol_bull = self._check_volume_confirmation(df, "BUY")
    delta_vol_bear = self._check_volume_confirmation(df, "SELL")
    has_volume_spike = df.iloc[-1]['volume_spike']

    # 6. POC
    poc_trend = self._calculate_vp_trend()
    at_poc = self.poc_level and abs(current_price - self.poc_level) < atr * 0.5
    poc_rising = poc_trend == "RISING"
    poc_falling = poc_trend == "FALLING"

    # 7. HTF Alignment
    htf_bull = self.higher_tf_trend == "BULLISH"
    htf_bear = self.higher_tf_trend == "BEARISH"

    # 8. Zones
    pd_zone = self._get_premium_discount_zone(df)
    in_discount = pd_zone['zone'] == 'DISCOUNT'
    in_premium = pd_zone['zone'] == 'PREMIUM'

    # 9. Session Levels
    near_session_levels = self._check_session_level_proximity(current_price, atr)
    at_session_low = any('low' in level for level in near_session_levels) if near_session_levels else False
    at_session_high = any('high' in level for level in near_session_levels) if near_session_levels else False

    # ===== SCORE BULLISH SIGNALS =====

    bull_continuation = None
    bull_reversal = None

    # Bullish CONTINUATION (BOS + retracement)
    if has_bos_bull or self.trend_bullish:
        bull_continuation = self.confluence_scorer.score_continuation(
            has_bos=has_bos_bull,
            at_ob=at_bullish_ob,
            at_fvg=at_bullish_fvg,
            fib_score=bull_fib_score,
            has_delta_volume=delta_vol_bull,
            has_volume_spike=has_volume_spike,
            at_poc=at_poc,
            poc_rising=poc_rising,
            htf_aligned=htf_bull,
            in_discount_zone=in_discount,
            at_session_level=at_session_low,
            # 🔥 NEW PARAMETERS
            has_displacement=has_bull_displacement,
            ob_quality=bull_ob_quality,
            fvg_quality=bull_fvg_quality,
            ms_quality=bull_ms_quality,
            has_eqh_eql=has_eql,
            in_killzone=in_killzone,
            atr_regime_ok=atr_ok,
            htf_imbalance=False,  # TODO: implement HTF imbalance detection
            liquidity_type=bull_liq_type
        )

    # Bullish REVERSAL (CHoCH + liquidity grab)
    if has_choch_bull:
        bull_reversal = self.confluence_scorer.score_reversal(
            has_choch=has_choch_bull,
            at_ob=at_bullish_ob,
            at_fvg=at_bullish_fvg,
            fib_score=bull_fib_score,
            has_liquidity_sweep=bull_sweep,
            has_stop_hunt=stop_hunt.get('bull_stop_hunt', False),
            has_delta_volume=delta_vol_bull,
            htf_aligned=htf_bull,
            in_correct_zone=in_discount,
            # 🔥 NEW PARAMETERS
            has_displacement=has_bull_displacement,
            ob_quality=bull_ob_quality,
            fvg_quality=bull_fvg_quality,
            ms_quality=bull_ms_quality,
            has_eqh_eql=has_eql,
            in_killzone=in_killzone,
            atr_regime_ok=atr_ok,
            htf_imbalance=False,
            liquidity_type=bull_liq_type
        )

    # ===== SCORE BEARISH SIGNALS =====

    bear_continuation = None
    bear_reversal = None

    # Bearish CONTINUATION (BOS + retracement)
    if has_bos_bear or (not self.trend_bullish):
        bear_continuation = self.confluence_scorer.score_continuation(
            has_bos=has_bos_bear,
            at_ob=at_bearish_ob,
            at_fvg=at_bearish_fvg,
            fib_score=bear_fib_score,
            has_delta_volume=delta_vol_bear,
            has_volume_spike=has_volume_spike,
            at_poc=at_poc,
            poc_rising=poc_falling,
            htf_aligned=htf_bear,
            in_discount_zone=in_premium,
            at_session_level=at_session_high,
            # 🔥 NEW PARAMETERS
            has_displacement=has_bear_displacement,
            ob_quality=bear_ob_quality,
            fvg_quality=bear_fvg_quality,
            ms_quality=bear_ms_quality,
            has_eqh_eql=has_eqh,
            in_killzone=in_killzone,
            atr_regime_ok=atr_ok,
            htf_imbalance=False,
            liquidity_type=bear_liq_type
        )

    # Bearish REVERSAL (CHoCH + liquidity grab)
    if has_choch_bear:
        bear_reversal = self.confluence_scorer.score_reversal(
            has_choch=has_choch_bear,
            at_ob=at_bearish_ob,
            at_fvg=at_bearish_fvg,
            fib_score=bear_fib_score,
            has_liquidity_sweep=bear_sweep,
            has_stop_hunt=stop_hunt.get('bear_stop_hunt', False),
            has_delta_volume=delta_vol_bear,
            htf_aligned=htf_bear,
            in_correct_zone=in_premium,
            # 🔥 NEW PARAMETERS
            has_displacement=has_bear_displacement,
            ob_quality=bear_ob_quality,
            fvg_quality=bear_fvg_quality,
            ms_quality=bear_ms_quality,
            has_eqh_eql=has_eqh,
            in_killzone=in_killzone,
            atr_regime_ok=atr_ok,
            htf_imbalance=False,
            liquidity_type=bear_liq_type
        )

    # ===== PICK BEST VALID SIGNAL =====

    all_signals = []

    # Check bull continuation
    if bull_continuation:
        is_valid, reason = bull_continuation.is_valid()
        logger.debug(f"🔵 Bull CONTINUATION: score={bull_continuation.total_score}, valid={is_valid}, reason={reason}, factors={bull_continuation.factors}")
        if is_valid:
            all_signals.append({
                'type': 'BUY',
                'trade_type': 'CONTINUATION',
                'score': bull_continuation.total_score,
                'breakdown': bull_continuation
            })

    # Check bull reversal
    if bull_reversal:
        is_valid, reason = bull_reversal.is_valid()
        logger.debug(f"🔵 Bull REVERSAL: score={bull_reversal.total_score}, valid={is_valid}, reason={reason}, factors={bull_reversal.factors}")
        if is_valid:
            all_signals.append({
                'type': 'BUY',
                'trade_type': 'REVERSAL',
                'score': bull_reversal.total_score,
                'breakdown': bull_reversal
            })

    # Check bear continuation
    if bear_continuation:
        is_valid, reason = bear_continuation.is_valid()
        logger.debug(f"🔴 Bear CONTINUATION: score={bear_continuation.total_score}, valid={is_valid}, reason={reason}, factors={bear_continuation.factors}")
        if is_valid:
            all_signals.append({
                'type': 'SELL',
                'trade_type': 'CONTINUATION',
                'score': bear_continuation.total_score,
                'breakdown': bear_continuation
            })

    # Check bear reversal
    if bear_reversal:
        is_valid, reason = bear_reversal.is_valid()
        logger.debug(f"🔴 Bear REVERSAL: score={bear_reversal.total_score}, valid={is_valid}, reason={reason}, factors={bear_reversal.factors}")
        if is_valid:
            all_signals.append({
                'type': 'SELL',
                'trade_type': 'REVERSAL',
                'score': bear_reversal.total_score,
                'breakdown': bear_reversal
            })

    # Pick highest score
    if not all_signals:
        return {
            'bullish_score': 0,
            'bearish_score': 0,
            'bias': 'NEUTRAL',
            'signals': []
        }

    # Sort by score descending
    all_signals.sort(key=lambda x: x['score'], reverse=True)
    best_signal = all_signals[0]

    return {
        'bullish_score': bull_continuation.total_score if (bull_continuation and bull_continuation.is_valid()[0]) else 0,
        'bearish_score': bear_continuation.total_score if (bear_continuation and bear_continuation.is_valid()[0]) else 0,
        'bias': best_signal['type'],
        'signals': all_signals,
        'best_signal': best_signal
    }
