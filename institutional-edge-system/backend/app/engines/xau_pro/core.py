import pandas as pd
from typing import Dict, List, Optional
from loguru import logger
from datetime import datetime
from ta.trend import MACD, EMAIndicator
from ta.momentum import RSIIndicator, StochasticOscillator

# Reuse robust components from Golden Engine (assuming it remains as a library)
# If Golden is deleted, these need to be moved to a shared 'common' directory.
from app.engines.golden.structure import StructureAnalyzer
from app.engines.golden.fibonacci import FibonacciCalculator
from app.engines.xau_pro.smc import SMCAnalyzer

class InstitutionalGoldEngine:
    """
    🥇 INSTITUTIONAL GOLD ENGINE (XAU_PRO) v4.0 - SMC Enhanced
    
    The "Gold Standard" for High-Volatility Asset Scalping.
    
    v4.0 Changes:
    1. Smart Money Concepts: Order Blocks, Liquidity Sweeps, FVG
    2. Session Killzones: London (07-10 UTC) + NY (12-15 UTC) only
    3. RSI Thresholds: Buy ≤ 40, Sell ≥ 60
    4. MACD: 6/18/9 | ZigZag: 12 | SL ATR: 1.4
    
    Target: > 70% Win Rate on XAUUSD M15.
    """
    
    # Session Killzone Definitions (UTC)
    KILLZONES = {
        'LONDON_KZ': {'start': 7, 'end': 10},   # 07:00-10:00 UTC
        'NY_KZ': {'start': 12, 'end': 15},      # 12:00-15:00 UTC
        'OVERLAP_KZ': {'start': 13, 'end': 16}, # 13:00-16:00 UTC (peak liquidity)
        'BOTH_KZ': [{'start': 7, 'end': 10}, {'start': 12, 'end': 15}],
        'ALL': {'start': 0, 'end': 24}
    }
    
    def __init__(self, config: Dict):
        self.config = config
        self.symbol = config.get('symbol', 'XAUUSD')
        self.timeframe = config.get('timeframe', 'M15')
        
        # --- Component Initialization (v3.0: ZigZag 12) ---
        self.structure_analyzer = StructureAnalyzer(config.get('structure', {'zigzag_lookback': 12}))
        self.fib_calculator = FibonacciCalculator(config.get('fibonacci', {}))
        
        # --- Trend EMAs ---
        self.ema_trend_period = config.get('ema_trend', 200)
        self.ema_fast_trend = 50
        
        # MACD (v3.0: 6/18/9 for noise reduction)
        self.macd_fast = config.get('macd_fast', 6)
        self.macd_slow = config.get('macd_slow', 18)
        self.macd_signal = config.get('macd_signal', 9)
        
        # RSI (v3.0: Tighter thresholds based on trade data)
        self.rsi_period = config.get('rsi_period', 14)
        self.rsi_buy_threshold = config.get('rsi_buy_threshold', 40)  # Only deep discount
        self.rsi_sell_threshold = config.get('rsi_sell_threshold', 60) # Only premium zone
        
        # Stochastic (14, 3, 3)
        self.stoch_k = config.get('stoch_k', 14)
        self.stoch_d = config.get('stoch_d', 3)
        
        # Risk (v3.0: ATR 1.4)
        self.rr_ratio = config.get('rr_ratio', 2.0)
        self.sl_atr_multiplier = config.get('sl_atr_multiplier', 1.4)
        
        # Session Killzone (v3.0)
        self.session_mode = config.get('session_mode', 'BOTH_KZ')
        
        # SMC v4.0 - Smart Money Concepts Analyzer
        self.smc = SMCAnalyzer(config)
        
    def analyze(self, df: pd.DataFrame, df_higher_tf: Optional[pd.DataFrame] = None, df_daily: Optional[pd.DataFrame] = None) -> Dict:
        """
        Main Analysis Pipeline for Gold (SMC + Fib + Killzone Filter).
        v3.0: Now includes session killzone check to reduce over-trading.
        """
        if df is None or len(df) < 50: # Lowered threshold to 50 to match StructureAnalyzer
             # Return valid structure object even for empty data to prevent AttributeError in caller
             empty_struct = self.structure_analyzer.analyze(pd.DataFrame() if df is None else df)
             return {'signals': [], 'structure': empty_struct}
             
        if len(df) < 200:
             # Still analyze structure for small datasets
             structure = self.structure_analyzer.analyze(df)
             return {'signals': [], 'structure': structure}
        
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
        
        # Stochastic (SMC Confirmation)
        stoch = StochasticOscillator(high=df['high'], low=df['low'], close=df['close'], window=self.stoch_k, smooth_window=self.stoch_d)
        df['stoch_k'] = stoch.stoch()
        df['stoch_d'] = stoch.stoch_signal()
        
        # ATR (for Risk)
        if 'atr' not in df.columns:
             from ta.volatility import AverageTrueRange
             atr_ind = AverageTrueRange(high=df['high'], low=df['low'], close=df['close'])
             df['atr'] = atr_ind.average_true_range()

        # --- v3.0: SESSION KILLZONE FILTER ---
        try:
            # Handle both DatetimeIndex and RangeIndex with 'time' column
            if isinstance(df.index, pd.DatetimeIndex):
                current_time = df.index[-1]
            elif 'time' in df.columns:
                current_time = pd.Timestamp(df['time'].iloc[-1])
            else:
                current_time = pd.Timestamp(df.index[-1])
        except Exception as e:
            logger.error(f"Time conversion failed: {e} | Index Type: {type(df.index)}")
            current_time = datetime.now()

        current = df.iloc[-1]
        
        # TIMEZONE MATH (User Reference)
        # Broker = UTC+2 (FundingPips Winter)
        # User   = UTC-4 (RD/EST)
        try:
            from datetime import timedelta
            utc_time = current_time - timedelta(hours=2)
            local_time = utc_time - timedelta(hours=4)
        except:
             utc_time = current_time
             local_time = current_time

        # Prepare debug info immediately so it's available even if we skip
        debug_info = {
            'rsi': current['rsi'],
            'macd_hist': current['macd_hist'],
            'stoch': current.get('stoch_k', 0),
            'in_zone': False,
            'indicators_aligned': False,
            'smc': {},
            'price_action': False,
            'time_broker': str(current_time.time()),
            'time_utc': str(utc_time.time()),
            'time_local': str(local_time.time())
        }

        if not self._is_in_killzone(current_time):
            # Only log if we haven't logged recently? No, log every check for clarity now.
            # Use INFO so user sees it clearly.
            logger.info(f"⏳ SKIP KZ: Local {local_time.strftime('%H:%M')} | UTC {utc_time.strftime('%H:%M')} | Broker {current_time.strftime('%H:%M')} (Outside Session)")
            structure = self.structure_analyzer.analyze(df)
            return {
                'signals': [], 
                'structure': structure, 
                'reason': f"Outside killzone (Local {local_time.strftime('%H:%M')})",
                'debug_info': debug_info 
            }
        
        # logger.warning(f"✅ Passed KZ: {current_time}")
        # -------------------------

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
        
        # --- STELLAR TREND LOGIC (M15 EMA Only) ---
        # "Smart Trend" = Price vs EMA200. 
        # Structure is used for Entry Context, not blocking Trend.
        
        signal_type = None
        
        # EMA Trend Check
        is_bullish = current['close'] > current['ema200']
        is_bearish = current['close'] < current['ema200']
        
        # M5 SCALPING SAFETY: Require HTF (M30/H1) Confirmation
        timeframe = self.config.get('timeframe', '15m')
        if timeframe.upper() == 'M5' and df_higher_tf is not None and len(df_higher_tf) > 50:
             # Calculate HTF EMA200 if missing
             if 'ema200' not in df_higher_tf.columns:
                 df_higher_tf['ema200'] = EMAIndicator(close=df_higher_tf['close'], window=200).ema_indicator()
             
             htf_last = df_higher_tf.iloc[-1]
             htf_bullish = htf_last['close'] > htf_last['ema200']
             htf_bearish = htf_last['close'] < htf_last['ema200']
             
             # Filter: Must align with HTF
             if is_bullish and not htf_bullish: 
                 is_bullish = False
                 # logger.info(f"🚫 M5 Bullish Signal Vetoed by HTF Bearish Trend")
                 
             if is_bearish and not htf_bearish: 
                 is_bearish = False
                 # logger.info(f"🚫 M5 Bearish Signal Vetoed by HTF Bullish Trend")

        if is_bullish:
            signal_type = 'BUY'
        elif is_bearish:
            signal_type = 'SELL'
            
        # Structure Confirmation (Optional/Bonus, not blocking)
        # if structure.trend != 'UP' and signal_type == 'BUY': ... (We ignore this for volume)

        if not signal_type:
             return {'signals': [], 'structure': structure} 
        
        # logger.warning(f"✅ Trend Aligned: {signal_type} @ {current_price}") 
        
        # logger.warning(f"✅ Trend Aligned: {signal_type} @ {current_price}") 

 
            
        # --- BUY LOGIC ---
        if signal_type == 'BUY':
            in_zone = False
            active_level = None
            
            # SMC Golden Zone: 0.618 - 0.786
            # Retail buys at 0.50, Banks buy at 0.70ish
            tolerance_price = current['atr'] * 0.25 
            
            for zone in fib_zones:
                if 0.61 <= zone['ratio'] <= 0.79: # Strict Deep Discount
                    if abs(current_price - zone['price']) < tolerance_price or (current['low'] <= zone['price'] <= current['high']):
                        in_zone = True
                        active_level = zone['ratio']
                        break
            
            # ENTRY FLIP: 
            # 1. Triple Confirmation (Indicators aligned)
            # 2. Candlestick Trigger (Pinbar/Engulfing)
            
            indicators_aligned = self._triple_confirmation(current, prev, 'BUY')
            price_action_trigger = self._validate_entry_trigger(current, prev, 'BUY')
            
            # SMC v4.3: Decoupled Entry Logic
            # Path A: SMC Strategy (Structure + OB/FVG + Trigger)
            # Path B: Fib Strategy (Structure + Golden Zone + Indicators + Trigger)
            
            # Re-enable SMC check (undoing debug bypass)
            smc_enabled = self.smc.ob_enabled or self.smc.fvg_enabled
            is_smc_entry = False
            
            if smc_enabled:
                # v4.1 STRICT: SMC Sweep + Zone Required
                smc_result = self.smc.get_smc_confluence(
                    df, 'BUY', current_price, current['atr'],
                    candle_high=current['high'], candle_low=current['low']
                )
                if (smc_result['in_order_block'] or smc_result['in_fvg']) and smc_result['liquidity_swept']:
                    is_smc_entry = True
            else:
                 smc_result = {} # Init for later use
            
            # Debug SMC Failure
            if not is_smc_entry and smc_enabled:
                 pass # logger.warning(f"❌ SMC FAIL: No Entry (Zone/Sweep missing? Swept={smc_result.get('liquidity_swept')})")
            elif not smc_enabled:
                smc_result = {}

            # Combined Entry Logic
            if is_smc_entry and price_action_trigger:
                 logger.info(f"🚀 SMC BUY TRIGGERED! Prob: {smc_result}")
                 self._create_signal(signals, 'BUY', current, structure, None, smc_result)
                 
            elif in_zone and indicators_aligned and price_action_trigger:
                 # Fib Path: Valid Structure + Fib Zone + Indicators + Candle Trigger
                 self._create_signal(signals, 'BUY', current, structure, active_level, smc_result)

        # --- SELL LOGIC ---
        elif signal_type == 'SELL':
            in_zone = False
            active_level = None
            tolerance_price = current['atr'] * 0.25
            
            for zone in fib_zones:
                if 0.61 <= zone['ratio'] <= 0.79:
                     if abs(current_price - zone['price']) < tolerance_price or (current['low'] <= zone['price'] <= current['high']):
                        in_zone = True
                        active_level = zone['ratio']
                        break
                        
            indicators_aligned = self._triple_confirmation(current, prev, 'SELL')
            price_action_trigger = self._validate_entry_trigger(current, prev, 'SELL')
            
            # SMC v4.3: Decoupled Entry Logic (SELL)
            smc_enabled = self.smc.ob_enabled or self.smc.fvg_enabled
            is_smc_entry = False
            
            if smc_enabled:
                smc_result = self.smc.get_smc_confluence(
                    df, 'SELL', current_price, current['atr'],
                    candle_high=current['high'], candle_low=current['low']
                )
                # v4.1 STRICT: SMC Sweep + Zone Required
                if (smc_result['in_order_block'] or smc_result['in_fvg']) and smc_result['liquidity_swept']:
                    is_smc_entry = True
            else:
                smc_result = {}
            
            # Combined Entry Logic
            if is_smc_entry and price_action_trigger:
                 # SMC Path
                 self._create_signal(signals, 'SELL', current, structure, None, smc_result)
                 
            elif in_zone and indicators_aligned and price_action_trigger:
                 # Fib Path
                 self._create_signal(signals, 'SELL', current, structure, active_level, smc_result)

        return {
            'signals': signals,
            'structure': structure,
            'fib_zones': fib_zones,
            'debug_info': {
                'rsi': current['rsi'],
                'macd_hist': current['macd_hist'],
                'stoch': current.get('slow_k', 0),
                'in_zone': locals().get('in_zone', False),
                'indicators_aligned': locals().get('indicators_aligned', False),
                'smc': locals().get('smc_result', {}),
                'price_action': locals().get('price_action_trigger', False)
            }
        }

    def update_news(self, events: List[Dict]):
        """
        Update high-impact news events for filtering.
        Current implementation: Log only (Pass-through).
        """
        if events:
            logger.debug(f"📰 InstitutionalGoldEngine received {len(events)} news events (No Filtering Active)")

    def _is_in_killzone(self, current_time) -> bool:
        """
        v3.0: Check if current UTC hour is within the configured session killzone.
        Returns True if we should trade, False if outside killzone.
        
        Auto-adjusts for Broker Time (UTC+2) by subtracting 2 hours.
        """
        if self.session_mode == 'ALL':
            return True
        
        try:
            hour_broker = current_time.hour if hasattr(current_time, 'hour') else datetime.now().hour
            # Hack: Broker is usually UTC+2 or UTC+3. User confirms Broker=15 when Local/RD=9 (UTC=13).
            # So Broker = UTC + 2.
            # Convert Broker Hour to UTC Hour:
            hour_utc = (hour_broker - 2) % 24 
        except:
            return True  # Fail open if we can't determine time
        
        killzone_config = self.KILLZONES.get(self.session_mode, self.KILLZONES['BOTH_KZ'])
        
        # Handle BOTH_KZ (list of windows)
        if isinstance(killzone_config, list):
            for window in killzone_config:
                if window['start'] <= hour_utc < window['end']:
                    return True
            return False
        else:
            return killzone_config['start'] <= hour_utc < killzone_config['end']

    def _triple_confirmation(self, current, prev, direction: str) -> bool:
        """
        v3.0: RSI + MACD + Stochastic check with DATA-DRIVEN thresholds.
        RSI Buy <= 40, RSI Sell >= 60 (from trade analysis)
        """
        # RSI
        rsi = current['rsi']
        
        # MACD
        macd_hist = current['macd_hist']
        prev_macd = prev['macd_hist']
        
        # Stochastic
        stoch_k = current['stoch_k']
        prev_stoch = prev['stoch_k']
        
        if direction == "BUY":
            # v3.0: RSI must be in deep discount zone (<= buy threshold)
            rsi_ok = rsi <= self.rsi_buy_threshold
            
            # MACD: Rising histogram (Momentum shift)
            macd_ok = macd_hist > prev_macd
            
            # Stoch: Rising and not overbought
            stoch_ok = stoch_k > prev_stoch and stoch_k < 80
            
            return rsi_ok and macd_ok and stoch_ok
            
        else: # SELL
            # v3.0: RSI must be in premium zone (>= sell threshold)
            rsi_ok = rsi >= self.rsi_sell_threshold
            
            # MACD: Falling
            macd_ok = macd_hist < prev_macd
            
            # Stoch: Falling and not oversold
            stoch_ok = stoch_k < prev_stoch and stoch_k > 20
            
            return rsi_ok and macd_ok and stoch_ok

    def _validate_entry_trigger(self, current: pd.Series, prev: pd.Series, direction: str) -> bool:
        """
        Candlestick Pattern & Liquidity Sweep Check.
        To avoid catching a falling knife, we wait for a REACTION.
        """
        curr_body = abs(current['close'] - current['open'])
        prev_body = abs(prev['close'] - prev['open'])
        
        # 1. Engulfing
        is_bullish_engulfing = (direction == 'BUY' and 
                               current['close'] > current['open'] and 
                               prev['close'] < prev['open'] and 
                               curr_body > prev_body)
                               
        is_bearish_engulfing = (direction == 'SELL' and 
                               current['close'] < current['open'] and 
                               prev['close'] > prev['open'] and 
                               curr_body > prev_body)
                               
        # 2. Pinbar ( Hammer / Shooting Star )
        total_range = current['high'] - current['low']
        if total_range == 0: return False
        
        lower_wick = min(current['open'], current['close']) - current['low']
        upper_wick = current['high'] - max(current['open'], current['close'])
        
        is_bullish_pinbar = (direction == 'BUY' and lower_wick > (curr_body * 2))
        is_bearish_pinbar = (direction == 'SELL' and upper_wick > (curr_body * 2))
        
        return is_bullish_engulfing or is_bearish_engulfing or is_bullish_pinbar or is_bearish_pinbar

    def _create_signal(self, signals, direction, current, structure, fib_level, smc_result=None):
        """
        Constructs the signal object with Risk Management
        v4.1: Fixed SL calculation to always be on correct side of entry
        """
        current_price = current.close
        atr = current['atr']
        
        # Minimum SL distance (0.5 ATR to prevent "Invalid stops" errors)
        min_sl_distance = atr * 0.5
        
        # SMC / Institutional Stop Loss
        # We look for the INVALIDATION point (Structure start) + ATR breathing room
        
        # FIX M5 CRASH: structure.last_impulse_leg can be None if zigzag undefined
        sl_price = None
        use_fallback = False
        
        if structure and structure.last_impulse_leg:
             invalid_price = structure.last_impulse_leg['start'].price
             
             # Max Risk Distance: 3 ATR (to avoid huge stops on large impulses)
             max_sl_dist = atr * 3.0
             
             if direction == 'BUY':
                # For BUY: invalid_price MUST be below current_price
                if invalid_price < current_price:
                    dist_to_struct = current_price - invalid_price
                    if dist_to_struct > max_sl_dist:
                        sl_price = current_price - (atr * self.sl_atr_multiplier) 
                    else:
                        sl_price = invalid_price - (atr * 0.2) 
                else:
                    # Structure invalid for BUY - use ATR fallback
                    use_fallback = True
                    logger.debug(f"⚠️ BUY: Structure invalid_price ({invalid_price:.2f}) >= entry ({current_price:.2f}), using ATR SL")
                    
             else: # SELL
                # For SELL: invalid_price MUST be above current_price
                if invalid_price > current_price:
                    dist_to_struct = invalid_price - current_price
                    if dist_to_struct > max_sl_dist:
                        sl_price = current_price + (atr * self.sl_atr_multiplier)
                    else:
                        sl_price = invalid_price + (atr * 0.2)
                else:
                    # Structure invalid for SELL - use ATR fallback
                    use_fallback = True
                    logger.debug(f"⚠️ SELL: Structure invalid_price ({invalid_price:.2f}) <= entry ({current_price:.2f}), using ATR SL")
        else:
             use_fallback = True
             
        # Fallback: Use Standard ATR SL
        if use_fallback or sl_price is None:
             sl_dist = atr * self.sl_atr_multiplier
             
             if direction == 'BUY':
                 sl_price = current_price - sl_dist
             else:
                 sl_price = current_price + sl_dist
                 
        # CRITICAL VALIDATION: Ensure SL is on correct side with minimum distance
        if direction == 'BUY':
            sl_distance = current_price - sl_price
            if sl_distance < min_sl_distance:
                # Force minimum SL distance
                sl_price = current_price - min_sl_distance
                logger.warning(f"⚙️ BUY SL adjusted: was too close ({sl_distance:.2f}), now {min_sl_distance:.2f} ATR")
            # Final sanity check
            if sl_price >= current_price:
                sl_price = current_price - (atr * self.sl_atr_multiplier)
                logger.error(f"🚨 BUY SL was ABOVE entry! Forced to ATR-based: {sl_price:.5f}")
        else:  # SELL
            sl_distance = sl_price - current_price
            if sl_distance < min_sl_distance:
                # Force minimum SL distance
                sl_price = current_price + min_sl_distance
                logger.warning(f"⚙️ SELL SL adjusted: was too close ({sl_distance:.2f}), now {min_sl_distance:.2f} ATR")
            # Final sanity check
            if sl_price <= current_price:
                sl_price = current_price + (atr * self.sl_atr_multiplier)
                logger.error(f"🚨 SELL SL was BELOW entry! Forced to ATR-based: {sl_price:.5f}")
                
        # Calculate TP based on validated SL
        tp_dist = abs(current_price - sl_price) * self.rr_ratio
        if direction == 'BUY':
            tp1_price = current_price + tp_dist
        else:
            tp1_price = current_price - tp_dist
            


        # SMC metadata (v4.0)
        smc_info = {}
        if smc_result:
            smc_info = {
                'smc_score': smc_result.get('smc_score', 0),
                'in_order_block': smc_result.get('in_order_block', False),
                'liquidity_swept': smc_result.get('liquidity_swept', False),
                'in_fvg': smc_result.get('in_fvg', False),
                'smc_details': smc_result.get('smc_details', [])
            }

        signal = {
            'symbol': self.symbol,
            'signal_type': direction,
            'price': current_price,
            'time': datetime.now().isoformat(),
            'stop_loss': sl_price,
            'take_profit_1': tp1_price,
            'take_profit_2': tp1_price, 
            'strategy': 'XAU_PRO_v4 (SMC Enhanced)',
            'confluence_score': 95 + (smc_info.get('smc_score', 0) * 2),  # Boost for SMC
            'metadata': {
                'fib_level': fib_level,
                'rsi': current['rsi'],
                'stoch_k': current.get('stoch_k', 0),
                'macd': current['macd_hist'],
                **smc_info
            }
        }
        signals.append(signal)
        smc_tag = f" | SMC: {', '.join(smc_info.get('smc_details', []))}" if smc_info.get('smc_details') else ""
        logger.info(f"🥇 GOLD SNIPER v4.0: {direction} @ {current_price} | Fib {fib_level} | RSI {current['rsi']:.1f}{smc_tag}")

