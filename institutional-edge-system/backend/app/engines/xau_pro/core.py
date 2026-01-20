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

class InstitutionalProEngine:
    """
    🥇 INSTITUTIONAL PRO ENGINE v5.0 - Multi-Asset SMC
    
    The "Gold Standard" logic now generalized for all assets (Forex, Crypto, Indices).
    
    v5.0 Changes:
    1. Dynamic Symbol Adaptation: Automated defaults for XAU, BTC, EURUSD, etc.
    2. Configurable Tolerance: Logic depends on ATR, not fixed price points.
    3. Session Agnostic: Defaults to 'ALL' for Crypto, 'LONDON/NY' for Forex.
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
        self.symbol = config.get('symbol', 'XAUUSD').upper()
        self.timeframe = config.get('timeframe', 'M15')
        
        # Load defaults based on symbol type (Crypto vs Forex vs Metals)
        defaults = self._get_symbol_defaults(self.symbol)
        
        # --- Component Initialization (v3.0: ZigZag 12) ---
        self.structure_analyzer = StructureAnalyzer(config.get('structure', {'zigzag_lookback': defaults['zigzag']}))
        self.fib_calculator = FibonacciCalculator(config.get('fibonacci', {}))
        
        # --- Trend EMAs ---
        self.ema_trend_period = config.get('ema_trend', 200)
        self.ema_fast_trend = 50
        
        # MACD
        self.macd_fast = config.get('macd_fast', defaults['macd_fast'])
        self.macd_slow = config.get('macd_slow', defaults['macd_slow'])
        self.macd_signal = config.get('macd_signal', defaults['macd_signal'])
        
        # RSI
        self.rsi_period = config.get('rsi_period', 14)
        self.rsi_buy_threshold = config.get('rsi_buy_threshold', defaults['rsi_buy']) 
        self.rsi_sell_threshold = config.get('rsi_sell_threshold', defaults['rsi_sell'])
        
        # Stochastic (14, 3, 3)
        self.stoch_k = config.get('stoch_k', 14)
        self.stoch_d = config.get('stoch_d', 3)
        
        # Risk (v3.0: ATR 1.4)
        self.rr_ratio = config.get('rr_ratio', 2.0)
        self.sl_atr_multiplier = config.get('sl_atr_multiplier', defaults['sl_atr'])
        
        # Tolerance Multiplier (New in v5.0)
        self.tolerance_multiplier = config.get('tolerance_multiplier', 0.25)
        
        # Session Killzone
        self.session_mode = config.get('session_mode', config.get('trading_session', defaults['session']))
        logger.info(f"⚙️ InstitutionalProEngine ({self.symbol}): Session={self.session_mode} | RSI={self.rsi_buy_threshold}/{self.rsi_sell_threshold}")

        
        # SMC v4.0 - Smart Money Concepts Analyzer
        self.smc = SMCAnalyzer(config)
        
    def _get_symbol_defaults(self, symbol: str) -> Dict:
        """
        Return optimized defaults based on asset class.
        """
        # 1. CRYPTO (BTC, ETH, SOL) - High Volatility, 24/7
        if any(x in symbol for x in ['BTC', 'ETH', 'SOL', 'XRP', 'BNB']):
            return {
                'macd_fast': 12, 'macd_slow': 26, 'macd_signal': 9, # Standard is better for crypto trend
                'rsi_buy': 35, 'rsi_sell': 65, # Wider RSI
                'sl_atr': 2.0, # Wider stops
                'zigzag': 5, # Faster reactions
                'session': 'ALL' # Crypto never sleeps
            }
            
        # 2. METALS (XAU, XAG) - Mean Reverting + Trending
        elif 'XAU' in symbol or 'GOLD' in symbol:
            return {
                'macd_fast': 6, 'macd_slow': 18, 'macd_signal': 9, # Optimized for Gold scalping
                'rsi_buy': 40, 'rsi_sell': 60, # Tight ranges
                'sl_atr': 1.4,
                'zigzag': 12,
                'session': 'BOTH_KZ' # Volatility is key
            }
            
        # 3. FOREX MAJORS (EUR, GBP, JPY)
        else:
             return {
                'macd_fast': 12, 'macd_slow': 26, 'macd_signal': 9,
                'rsi_buy': 30, 'rsi_sell': 70, # Standard Oversold/Overbought
                'sl_atr': 1.0, # Tighter stops for fx
                'zigzag': 10,
                'session': 'BOTH_KZ' if 'JPY' not in symbol else 'ALL' # JPY moves in Asia too
            }
        
    def analyze(self, df: pd.DataFrame, df_higher_tf: Optional[pd.DataFrame] = None, df_daily: Optional[pd.DataFrame] = None) -> Dict:
        """
        Main Analysis Pipeline (SMC + Fib + Killzone Filter).
        v5.0: Configurable for any asset class.
        """
        if df is None or len(df) < 50: 
             # Return valid structure object even for empty data to prevent AttributeError in caller
             empty_struct = self.structure_analyzer.analyze(pd.DataFrame() if df is None else df)
             return {'signals': [], 'structure': empty_struct}
        
        # 0. Prevent Mutation Side-Effects
        df = df.copy()
        if df_higher_tf is not None:
             df_higher_tf = df_higher_tf.copy()
             
        if len(df) < 200:
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

        # 1. NaN Guard (Critical for stability)
        if df.iloc[-1][['rsi', 'macd_hist', 'stoch_k', 'atr']].isna().any():
             # logger.warning(f"⚠️ {self.symbol}: Indicators contain NaN values (RSI/MACD/Stoch/ATR). Skipping.")
             structure = self.structure_analyzer.analyze(df)
             return {'signals': [], 'structure': structure, 'reason': "NaN Indicators"}

        # --- SESSION KILLZONE FILTER ---
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
        
        # TIMEZONE MATH (Use UTC consistently)
        try:
            from datetime import timedelta
            # Calculate UTC time once
            utc_time = current_time - timedelta(hours=2) # Broker offset approx
            local_time = utc_time - timedelta(hours=4)
        except Exception as e:
             utc_time = current_time
             local_time = current_time

        # Prepare debug info
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
            'session_mode': self.session_mode
        }

        # 2. Performance: Analyze Structure ONCE
        structure = self.structure_analyzer.analyze(df)

        # Check Killzone using pure UTC time
        if not self._is_in_killzone_utc(utc_time.hour):
            # logger.debug(f"⏳ SKIP KZ: UTC {utc_time.strftime('%H:%M')} (Outside {self.session_mode})")
            return {
                'signals': [], 
                'structure': structure, 
                'reason': f"Outside killzone (UTC {utc_time.strftime('%H:%M')})",
                'debug_info': debug_info 
            }
        
        # 2b. Identify Fib Zones (reusing structure)
        fib_zones = self.fib_calculator.find_active_zones(structure, df.iloc[-1].close)
        
        # 3. Logic & Confluence
        # ---------------------
        signals = []
        current = df.iloc[-1]
        prev = df.iloc[-2]
        current_price = current.close
        
        # --- STELLAR TREND LOGIC (M15 EMA Only) ---
        signal_type = None
        
        # EMA Trend Check
        is_bullish = current['close'] > current['ema200']
        is_bearish = current['close'] < current['ema200']
        
        # HTF Confirmation
        if self.timeframe.upper() == 'M5' and df_higher_tf is not None and len(df_higher_tf) > 50:
             # Calculate HTF EMA200 if missing
             if 'ema200' not in df_higher_tf.columns:
                 df_higher_tf['ema200'] = EMAIndicator(close=df_higher_tf['close'], window=200).ema_indicator()
             
             htf_last = df_higher_tf.iloc[-1]
             htf_bullish = htf_last['close'] > htf_last['ema200']
             htf_bearish = htf_last['close'] < htf_last['ema200']
             
             if is_bullish and not htf_bullish: is_bullish = False
             if is_bearish and not htf_bearish: is_bearish = False

        if is_bullish:
            signal_type = 'BUY'
        elif is_bearish:
            signal_type = 'SELL'
            
        if not signal_type:
             return {'signals': [], 'structure': structure} 

        # --- DYNAMIC TOLERANCE (v5.0) ---
        # Instead of hardcoded 0.0008, use ATR fraction
        # This scales for BTC (60000) and EURUSD (1.05)
        tolerance_price = current['atr'] * self.tolerance_multiplier 
            
        # --- BUY LOGIC ---
        if signal_type == 'BUY':
            in_zone = False
            active_level = None
            
            for zone in fib_zones:
                if 0.61 <= zone['ratio'] <= 0.79: # Strict Deep Discount
                    if abs(current_price - zone['price']) < tolerance_price or (current['low'] <= zone['price'] <= current['high']):
                        in_zone = True
                        active_level = zone['ratio']
                        break
            
            indicators_aligned = self._triple_confirmation(current, prev, 'BUY')
            price_action_trigger = self._validate_entry_trigger(current, prev, 'BUY')
            
            # SMC Logic
            smc_enabled = self.smc.ob_enabled or self.smc.fvg_enabled
            is_smc_entry = False
            
            if smc_enabled:
                smc_result = self.smc.get_smc_confluence(
                    df, 'BUY', current_price, current['atr'],
                    candle_high=current['high'], candle_low=current['low']
                )
                if (smc_result['in_order_block'] or smc_result['in_fvg']) and smc_result['liquidity_swept']:
                    is_smc_entry = True
            else:
                 smc_result = {} 

            # Combined Entry Logic
            if is_smc_entry and price_action_trigger:
                 # logger.info(f"🚀 SMC BUY: {smc_result.get('smc_details')}")
                 self._create_signal(signals, 'BUY', current, structure, None, smc_result)
                 
            elif in_zone and indicators_aligned and price_action_trigger:
                 if not signals:
                    self._create_signal(signals, 'BUY', current, structure, active_level, smc_result)

        # --- SELL LOGIC ---
        elif signal_type == 'SELL':
            in_zone = False
            active_level = None
            
            for zone in fib_zones:
                if 0.61 <= zone['ratio'] <= 0.79:
                     if abs(current_price - zone['price']) < tolerance_price or (current['low'] <= zone['price'] <= current['high']):
                        in_zone = True
                        active_level = zone['ratio']
                        break
                        
            indicators_aligned = self._triple_confirmation(current, prev, 'SELL')
            price_action_trigger = self._validate_entry_trigger(current, prev, 'SELL')
            
            smc_enabled = self.smc.ob_enabled or self.smc.fvg_enabled
            is_smc_entry = False
            
            if smc_enabled:
                smc_result = self.smc.get_smc_confluence(
                    df, 'SELL', current_price, current['atr'],
                    candle_high=current['high'], candle_low=current['low']
                )
                if (smc_result['in_order_block'] or smc_result['in_fvg']) and smc_result['liquidity_swept']:
                    is_smc_entry = True
            else:
                smc_result = {}
            
            if is_smc_entry and price_action_trigger:
                 self._create_signal(signals, 'SELL', current, structure, None, smc_result)
                 
            elif in_zone and indicators_aligned and price_action_trigger:
                 if not signals:
                    self._create_signal(signals, 'SELL', current, structure, active_level, smc_result)

        # Prepare final debug info
        debug_info.update({
             'in_zone': locals().get('in_zone', False),
             'indicators_aligned': locals().get('indicators_aligned', False),
             'smc': locals().get('smc_result', {}),
             'price_action': locals().get('price_action_trigger', False)
        })

        return {
            'signals': signals,
            'structure': structure,
            'fib_zones': fib_zones,
            'debug_info': debug_info
        }

    def update_news(self, events: List[Dict]):
        """
        Update high-impact news events for filtering.
        """
        if events:
            pass # logger.debug(f"News update: {len(events)} events")

    def _is_in_killzone_utc(self, hour_utc: int) -> bool:
        """
        v4.1: Pure UTC Killzone check.
        Requires 'hour_utc' to be the already converted UTC hour.
        """
        if self.session_mode == 'ALL':
            return True
        
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
        v3.0: RSI + MACD + Stochastic check with CONFIGURABLE thresholds.
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
            # RSI must be in deep discount zone (<= buy threshold)
            rsi_ok = rsi <= self.rsi_buy_threshold
            
            # MACD: Rising histogram (Momentum shift)
            macd_ok = macd_hist > prev_macd
            
            # Stoch: Rising and not overbought (generic 80)
            stoch_ok = stoch_k > prev_stoch and stoch_k < 80
            
            return rsi_ok and macd_ok and stoch_ok
            
        else: # SELL
            # RSI must be in premium zone (>= sell threshold)
            rsi_ok = rsi >= self.rsi_sell_threshold
            
            # MACD: Falling
            macd_ok = macd_hist < prev_macd
            
            # Stoch: Falling and not oversold (generic 20)
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
        v5.0: Pro Engine generalized logic
        """
        current_price = current.close
        atr = current['atr']
        
        # Minimum SL distance (0.5 ATR to prevent "Invalid stops" errors)
        min_sl_distance = atr * 0.5
        
        # SMC / Institutional Stop Loss
        # We look for the INVALIDATION point (Structure start) + ATR breathing room
        
        sl_price = None
        use_fallback = False
        
        if structure and structure.last_impulse_leg:
             start_node = structure.last_impulse_leg.get('start')
             
             if not hasattr(start_node, 'price'):
                 use_fallback = True
                 invalid_price = 0
             else:
                 invalid_price = start_node.price
             
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
                    use_fallback = True
             else: # SELL
                # For SELL: invalid_price MUST be above current_price
                if invalid_price > current_price:
                    dist_to_struct = invalid_price - current_price
                    if dist_to_struct > max_sl_dist:
                        sl_price = current_price + (atr * self.sl_atr_multiplier)
                    else:
                        sl_price = invalid_price + (atr * 0.2)
                else:
                    use_fallback = True
        else:
             use_fallback = True
             
        # Fallback: Use Standard ATR SL
        if use_fallback or sl_price is None:
             sl_dist = atr * self.sl_atr_multiplier
             
             if direction == 'BUY':
                 sl_price = current_price - sl_dist
             else:
                 sl_price = current_price + sl_dist
                 
        # CRITICAL VALIDATION
        if direction == 'BUY':
            sl_distance = current_price - sl_price
            if sl_distance < min_sl_distance:
                sl_price = current_price - min_sl_distance
            if sl_price >= current_price:
                sl_price = current_price - (atr * self.sl_atr_multiplier)
        else:  # SELL
            sl_distance = sl_price - current_price
            if sl_distance < min_sl_distance:
                sl_price = current_price + min_sl_distance
            if sl_price <= current_price:
                sl_price = current_price + (atr * self.sl_atr_multiplier)
                
        # Calculate TP
        tp_dist = abs(current_price - sl_price) * self.rr_ratio
        if direction == 'BUY':
            tp1_price = current_price + tp_dist
        else:
            tp1_price = current_price - tp_dist

        # SMC metadata
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
            'strategy': f"INSTITUTIONAL_PRO_{self.symbol}",
            'confluence_score': min(100, 95 + (smc_info.get('smc_score', 0) * 2)),
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
        logger.info(f"💎 PRO SIGNAL [{self.symbol}]: {direction} @ {current_price} | RSI {current['rsi']:.1f}{smc_tag}")

