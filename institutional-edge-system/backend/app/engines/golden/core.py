import pandas as pd
import logging
from typing import Dict, Optional, List, Tuple
from datetime import datetime

from .structure import StructureAnalyzer, MarketStructure
from .fibonacci import FibonacciCalculator
from .confluence import ConfluenceSystem
from .risk_manager import RiskManager

logger = logging.getLogger(__name__)

class GoldenEngine:
    """
    The Golden Engine: A professional trading engine prioritizing Market Structure and Fibonacci Precision.
    
    Pipeline:
    1. Structure Analysis (ZigZag + Elliott Wave)
    2. Fibonacci Zone Identification
    3. Confluence Validation (Volume, VWAP, Momentum)
    4. Risk Management (ATR Stops, Sizing)
    """
    
    def __init__(self, config: Dict):
        self.config = config
        
        # --- STRUCTURE CONFIGURATION ---
        structure_conf = config.get('structure', {})
        
        # 1. Dynamic ZigZag Mode (ATR-Based)
        # If enabled, deviation is calculated dynamically.
        if structure_conf.get('dynamic_mode', False):
             logger.info("⚙️ Dynamic ZigZag Mode ENABLED (ATR-Based Deviation)")
             # Ensure defaults for dynamic params
             if 'atr_multiplier' not in structure_conf:
                 structure_conf['atr_multiplier'] = 1.5
             if 'atr_period' not in structure_conf:
                 structure_conf['atr_period'] = 14
        
        # 2. Smart Defaults for Fixed Mode (Scalping Optimization)
        # Only suggest optimization if User has NOT customized the lookback (still default 5)
        # and we are on a fast timeframe.
        timeframe = config.get('timeframe', 'H1')
        user_lookback = structure_conf.get('zigzag_lookback', 5)
        
        if timeframe in ['M1', 'M5', 'M15']:
             if not structure_conf.get('dynamic_mode', False):
                 # Only Auto-Tune if using Fixed Mode AND default lookback
                 if user_lookback == 5:
                     logger.info(f"⚙️ Scalping Optimization: Auto-tuning ZigZag Lookback 5 -> 20 (Noise Reduction)")
                     structure_conf['zigzag_lookback'] = 20
                 else:
                     logger.info(f"⚙️ Custom ZigZag Lookback Detected: {user_lookback} (User Setting Respected)")
             
             # Tolerance Optimization (Always valid for scalping)
             if config.get('tolerance_pips', 5.0) > 3.0:
                 logger.info(f"   -> Auto-Adjusting Tolerance: {config.get('tolerance_pips')} -> 3.0 pips")
                 config['tolerance_pips'] = 3.0
                 
        config['structure'] = structure_conf

        self.structure_analyzer = StructureAnalyzer(config.get('structure', {}))
        self.fib_calculator = FibonacciCalculator(config.get('fibonacci', {}))
        self.confluence_system = ConfluenceSystem(config.get('confluence', {}))
        self.risk_manager = RiskManager(config.get('risk', {}))
        
        logger.info("🏆 Golden Engine Initialized")

    def analyze(self, df: pd.DataFrame, df_higher_tf: Optional[pd.DataFrame] = None, df_daily: Optional[pd.DataFrame] = None) -> Dict:
        """
        Main analysis pipeline.
        
        Args:
            df: Main timeframe data (M5, M15, etc.)
            df_higher_tf: Confirmation timeframe data (H1, H4)
            df_daily: Daily data for macro bias
            
        Returns:
            Dict containing 'signals', 'analysis_data', 'debug_info'
        """
        if df is None or len(df) < 100:
            return {'signals': [], 'structure': None}

        # 1. Structure Analysis
        structure = self.structure_analyzer.analyze(df)
        
        # 2. Identify Fib Zones
        fib_zones = self.fib_calculator.find_active_zones(structure, df.iloc[-1].close)
        
        # 3. Check for Entry Triggers
        signals = []
        current_price = df.iloc[-1].close
        current_time = df.index[-1]
        
        # We only trade if structure is favorable (Trend + Pullback)
        if structure.current_phase == "CORRECTION" and structure.trend != "NEUTRAL":
            
            direction = "BUY" if structure.trend == "UP" else "SELL"
            
            # --- MACRO BIAS CHECK (Tier 1) ---
            if df_daily is not None and len(df_daily) > 50:
                # We use 'df_daily' argument but it represents the Macro timeframe (D1/W1)
                macro_structure = self.structure_analyzer.analyze(df_daily)
                
                # STRICT FILTER:
                # If Macro Trend is UP, we ONLY allow BUYS.
                # If Macro Trend is DOWN, we ONLY allow SELLS.
                # If Macro Trend is NEUTRAL, we might allow both or block. For "Golden" scalping, we block.
                
                if macro_structure.trend == "UP" and direction == "SELL":
                     logger.info(f"🚫 Signal BLOCKED by Macro Bias (D1: {macro_structure.trend})")
                     return {'signals': [], 'structure': structure}
                     
                if macro_structure.trend == "DOWN" and direction == "BUY":
                     logger.info(f"🚫 Signal BLOCKED by Macro Bias (D1: {macro_structure.trend})")
                     return {'signals': [], 'structure': structure}
                     
                if macro_structure.trend == "NEUTRAL":
                    # Optional: Allow invalidation if immediate structure is very strong?
                    # For now, safe approach: Block.
                    logger.info(f"⚠️ Signal BLOCKED: Macro Bias is NEUTRAL (Ranging)")
                    return {'signals': [], 'structure': structure}
            # --- MACRO BIAS END ---

            # --- CONFIRMATION TIMEFRAME CHECK (Tier 2) ---
            if df_higher_tf is not None and len(df_higher_tf) > 50:
                htf_structure = self.structure_analyzer.analyze(df_higher_tf)
                
                # Filter Logic:
                # Must ALIGN with Execution Trend.
                # If M15 is UP, H1 must be UP. (Momentum alignment)
                
                if htf_structure.trend != structure.trend:
                     logger.info(f"🚫 Signal BLOCKED by Confirmation TF ({htf_structure.trend} != {structure.trend})")
                     return {'signals': [], 'structure': structure}
            # --- CONFIRMATION END ---
            
            for zone in fib_zones:
                # Check if we are touching the zone (within tolerance)
                # Tolerance is in pips, convert to price
                symbol = self.config.get('symbol', 'EURUSD')
                is_jpy = 'JPY' in symbol
                pip_size = 0.01 if is_jpy else 0.0001
                
                # Auto-adjust tolerance for timeframe?
                # For M15, 5 pips might be okay, but allow config override.
                base_tolerance = self.config.get('tolerance_pips', 3.0) 
                tolerance_price = base_tolerance * pip_size
                
                dist = abs(current_price - zone['price'])
                
                if dist <= tolerance_price:
                    
                    # 4. Confluence Check (Tier 3)
                    if self.confluence_system.check_entry_conditions(df, direction):
                        
                        # 5. Risk Calculation
                        # Structure Invalidation Level:
                        # For BUY: Start of Impulse (Low)
                        # For SELL: Start of Impulse (High)
                        invalid_level = zone['start_anchor_price'] if 'start_anchor_price' in zone else structure.last_impulse_leg['start'].price
                        
                        # Get ATR
                        atr = df.iloc[-1].get('atr', 0.0010) # Fallback if no ATR column
                        
                        risk_params = self.risk_manager.calculate_entry_params(
                            entry_price=current_price,
                            structure_invalid_level=invalid_level,
                            atr=atr,
                            account_balance=self.config.get('balance', 10000) # Default if missing
                        )
                        
                        # Create Signal
                        signal = {
                            'symbol': self.config.get('symbol', 'Unknown'),
                            'signal_type': direction,
                            'price': current_price,
                            'time': current_time,
                            'stop_loss': risk_params['stop_loss'],
                            'take_profit_1': risk_params['tp1'],
                            'take_profit_2': risk_params['tp2'],
                            'volume_pct_tp1': risk_params['tp1_volume_pct'],
                            'fib_level': zone['ratio'],
                            'risk_amount': risk_params['risk_amount'],
                            'sl_distance': risk_params['sl_distance'],
                            
                            # TSL Params
                            'enable_trailing_stop': risk_params.get('enable_trailing_stop', False),
                            'tsl_mode': risk_params.get('tsl_mode', 'ATR'),
                            'tsl_activation_r': risk_params.get('tsl_activation_r', 0.0),
                            'tsl_atr_multiplier': risk_params.get('tsl_atr_multiplier', 1.5),
                            
                            'strategy': 'GoldenWave'
                        }
                        signals.append(signal)
                        logger.info(f"✨ Signal Found: {direction} @ {current_price} (Fib {zone['ratio']}) | Macro: {macro_structure.trend if df_daily is not None else 'N/A'}")
                        
                        # Only take the best/first signal per tick
                        break 
        
        return {
            'signals': signals,
            'structure': structure,
            'fib_zones': fib_zones
        }

    def update_news(self, events: List[Dict]):
        """
        Update high-impact news events for filtering.
        Current implementation: Log only (Pass-through).
        """
        if events:
            logger.debug(f"📰 GoldenEngine received {len(events)} news events (No Filtering Active)")
