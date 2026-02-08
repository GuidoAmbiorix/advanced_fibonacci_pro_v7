# Optimizer Configuration
# Defines the search spaces for Optuna covering all DatabaseManager.mqh inputs

PARAM_SPACES = {
    "default": {
        # --- Fibonacci Structure (8 params) ---
        "swing_lookback": {"type": "int", "low": 20, "high": 100, "step": 10},
        "zone_tolerance": {"type": "float", "low": 0.05, "high": 0.2, "step": 0.01},
        "fib_level_low": {"type": "float", "low": 0.38, "high": 0.70, "step": 0.01},
        "fib_level_high": {"type": "float", "low": 0.65, "high": 0.88, "step": 0.01},
        "use_fib_extensions": {"type": "int", "low": 0, "high": 1},
        "fib_ext_161": {"type": "int", "low": 0, "high": 1},
        "fib_ext_261": {"type": "int", "low": 0, "high": 1},
        "min_swing_points": {"type": "int", "low": 3, "high": 10, "step": 1},

        # --- Displacement (3 params) ---
        "use_displacement": {"type": "int", "low": 0, "high": 1},
        "displacement_atr": {"type": "float", "low": 0.5, "high": 3.0, "step": 0.1},
        "displacement_lookback": {"type": "int", "low": 5, "high": 30, "step": 5},

        # --- SMC Smart Money Concepts (6 params) ---
        "use_smc": {"type": "int", "low": 0, "high": 1},
        "smc_swing_lookback": {"type": "int", "low": 10, "high": 50, "step": 5},
        "smc_min_impulse_atr": {"type": "float", "low": 1.0, "high": 5.0, "step": 0.5},
        "smc_min_fvg_atr": {"type": "float", "low": 0.5, "high": 3.0, "step": 0.25},
        "smc_order_block_strength": {"type": "int", "low": 1, "high": 5, "step": 1},
        "smc_bos_confirmation": {"type": "int", "low": 0, "high": 1},

        # --- RSI (3 params) ---
        "rsi_period": {"type": "int", "low": 7, "high": 21, "step": 1},
        "rsi_oversold": {"type": "int", "low": 20, "high": 40, "step": 5},
        "rsi_overbought": {"type": "int", "low": 60, "high": 80, "step": 5},

        # --- Trend/EMA (2 params) ---
        "ema_period": {"type": "int", "low": 50, "high": 200, "step": 25},
        "ema_min_slope": {"type": "float", "low": 0.0, "high": 0.5, "step": 0.1},

        # --- Multi-Timeframe (4 params) ---
        "use_mtf": {"type": "int", "low": 0, "high": 1},
        "htf": {"type": "int", "low": 15, "high": 240, "step": 15},
        "mtf_ema_period": {"type": "int", "low": 20, "high": 200, "step": 20},
        "mtf_require_alignment": {"type": "int", "low": 0, "high": 1},

        # --- Chop Filter (2 params) ---
        "use_chop_filter": {"type": "int", "low": 0, "high": 1},
        "chop_threshold": {"type": "float", "low": 35.0, "high": 60.0, "step": 5.0},

        # --- Confluence (1 param) ---
        "min_confluence_entry": {"type": "int", "low": 8, "high": 14, "step": 1},

        # --- Adaptive Systems (3 params) ---
        "enable_adaptive_risk": {"type": "int", "low": 0, "high": 1},
        "enable_adaptive_exits": {"type": "int", "low": 0, "high": 1},
        "enable_adaptive_filters": {"type": "int", "low": 0, "high": 1},

        # --- Risk Management (2 params) ---
        "risk_base": {"type": "float", "low": 0.1, "high": 0.5, "step": 0.05},
        "max_risk": {"type": "float", "low": 1.0, "high": 3.0, "step": 0.5},

        # --- Take Profit Modes (4 params) ---
        "tp_mode": {"type": "int", "low": 0, "high": 2},
        "fixed_tp_r": {"type": "float", "low": 1.5, "high": 5.0, "step": 0.1},
        "min_tp_r": {"type": "float", "low": 1.0, "high": 2.5, "step": 0.1},
        "max_tp_r": {"type": "float", "low": 3.0, "high": 8.0, "step": 0.25},
        "tp_use_learned_mfe": {"type": "int", "low": 0, "high": 1},

        # --- Partial TP & Breakeven (4 params) ---
        "use_partial_tp": {"type": "int", "low": 0, "high": 1},
        "partial_tp_r": {"type": "float", "low": 0.5, "high": 2.0, "step": 0.1},
        "partial_close_percent": {"type": "float", "low": 0.3, "high": 0.7, "step": 0.05},
        "be_threshold_r": {"type": "float", "low": 0.3, "high": 1.5, "step": 0.1},

        # --- Trailing Stop (2 params) ---
        "trail_start_r": {"type": "float", "low": 0.5, "high": 2.0, "step": 0.1},
        "trail_atr_mult": {"type": "float", "low": 1.0, "high": 3.0, "step": 0.1},

        # --- News Filter (3 params) ---
        "use_news_filter": {"type": "int", "low": 0, "high": 1},
        "news_minutes_before": {"type": "int", "low": 15, "high": 120, "step": 15},
        "news_minutes_after": {"type": "int", "low": 15, "high": 120, "step": 15},

        # --- Kelly Criterion (3 params) ---
        "use_kelly": {"type": "int", "low": 0, "high": 1},
        "kelly_fraction": {"type": "float", "low": 0.1, "high": 0.5, "step": 0.05},
        "kelly_max_multiplier": {"type": "float", "low": 1.5, "high": 3.0, "step": 0.25},

        # --- Volatility (1 param) ---
        "volatility_threshold": {"type": "float", "low": 2.0, "high": 6.0, "step": 0.5},

        # --- Spread (1 param) ---
        "max_spread_points": {"type": "int", "low": 20, "high": 100, "step": 10},

        # --- Session Filters (4 params) ---
        "trade_london": {"type": "int", "low": 0, "high": 1},
        "trade_newyork": {"type": "int", "low": 0, "high": 1},
        "trade_asia": {"type": "int", "low": 0, "high": 1},
        "avoid_rollover": {"type": "int", "low": 0, "high": 1},

        # --- Pattern Recognition (3 params) ---
        "use_engulfing": {"type": "int", "low": 0, "high": 1},
        "use_pinbar": {"type": "int", "low": 0, "high": 1},
        "pattern_min_size_atr": {"type": "float", "low": 0.5, "high": 2.0, "step": 0.25},

        # --- Volume Analysis (3 params) ---
        "use_volume_filter": {"type": "int", "low": 0, "high": 1},
        "volume_ma_period": {"type": "int", "low": 10, "high": 50, "step": 5},
        "volume_threshold_mult": {"type": "float", "low": 1.0, "high": 3.0, "step": 0.25},

        # --- ATR Settings (3 params) ---
        "atr_period": {"type": "int", "low": 10, "high": 20, "step": 2},
        "atr_sl_multiplier": {"type": "float", "low": 1.0, "high": 3.0, "step": 0.25},
        "min_atr_points": {"type": "int", "low": 5, "high": 50, "step": 5},

        # --- Trade Management (5 params) ---
        "max_trades_per_day": {"type": "int", "low": 1, "high": 10, "step": 1},
        "max_consecutive_losses": {"type": "int", "low": 2, "high": 5, "step": 1},
        "daily_loss_limit_pct": {"type": "float", "low": 1.0, "high": 5.0, "step": 0.5},
        "position_spacing_bars": {"type": "int", "low": 5, "high": 50, "step": 5},
        "weekend_close_positions": {"type": "int", "low": 0, "high": 1},

        # --- Exit Strategies (4 params) ---
        "use_time_exit": {"type": "int", "low": 0, "high": 1},
        "max_trade_duration_bars": {"type": "int", "low": 20, "high": 200, "step": 20},
        "use_opposite_signal_exit": {"type": "int", "low": 0, "high": 1},
        "use_trailing_activation": {"type": "int", "low": 0, "high": 1},
    },
    
    "JPY": {
        "risk_base": {"type": "float", "low": 0.2, "high": 0.6, "step": 0.05},
        "fixed_tp_r": {"type": "float", "low": 2.0, "high": 6.0, "step": 0.2},
        "trail_atr_mult": {"type": "float", "low": 1.5, "high": 3.9, "step": 0.2},
        "volatility_threshold": {"type": "float", "low": 3.0, "high": 6.0, "step": 0.5},
    },
    
    "XAU": {
        "risk_base": {"type": "float", "low": 0.3, "high": 1.0, "step": 0.1},
        "fixed_tp_r": {"type": "float", "low": 2.5, "high": 8.0, "step": 0.2},
        "volatility_threshold": {"type": "float", "low": 4.0, "high": 10.0, "step": 0.5},
        "max_spread_points": {"type": "int", "low": 50, "high": 200, "step": 10},
        "swing_lookback": {"type": "int", "low": 10, "high": 50, "step": 5},
    }
}

# Timeframe Mappings (MT5 format)
TIMEFRAMES = {
    "M1": 1,
    "M5": 5,
    "M15": 15,
    "M30": 30,
    "H1": 60,
    "H4": 240,
    "D1": 1440,
    "W1": 10080
}

# Timeframe-specific data requirements
TIMEFRAME_DATA_LIMITS = {
    1: 10000,      # M1: Need lots of bars
    5: 5000,       # M5: 5000 bars ≈ 17 days
    15: 3000,      # M15: 3000 bars ≈ 31 days
    30: 2000,      # M30: 2000 bars ≈ 42 days
    60: 1500,      # H1: 1500 bars ≈ 62 days
    240: 1000,     # H4: 1000 bars ≈ 166 days
    1440: 500,     # D1: 500 bars ≈ 1.4 years
    10080: 200     # W1: 200 bars ≈ 3.8 years
}

# Timeframe-specific minimum trades for valid backtest
TIMEFRAME_MIN_TRADES = {
    1: 50,         # M1: Expect many trades
    5: 40,         # M5: Expect many trades
    15: 30,        # M15: Moderate trades
    30: 25,        # M30: Moderate trades
    60: 20,        # H1: Fewer trades
    240: 15,       # H4: Few trades
    1440: 10,      # D1: Very few trades
    10080: 5       # W1: Minimal trades
}

# Optimization Settings
OPTIMIZATION_SETTINGS = {
    "n_trials": 100,                    # Trials per optimization run
    "default_timeframe": 15,            # M15 default
    "train_days": 90,
    "test_days": 14,
    "min_trades": 30,                   # Will be adjusted based on timeframe
    "target_metric": "sharpe",          # Primary metric
    "optimization_mode": "single",      # 'single' or 'multi'
    "enable_oos_validation": True,      # Out-of-sample testing
    "oos_degradation_threshold": 0.5,   # Warn if train-test gap exceeds this
    "objectives": ["sharpe", "win_rate", "max_dd", "profit_factor"],
    "objective_weights": [0.4, 0.3, 0.2, 0.1],  # Composite score weights
    "walk_forward": {
        "enabled": False,
        "train_bars": 200,
        "test_bars": 50,
        "step": 50
    },
    "pruning": {
        "enabled": True,        # Enable Optuna pruning for faster optimization
        "patience": 20          # Stop unpromising trials early
    },
    "guardian_trials": 20       # Trials for High-Fidelity MT5 Backtest
}

# Total parameter count for tracking
TOTAL_PARAM_COUNT = 83

def get_timeframe_settings(timeframe):
    """
    Get optimization settings adjusted for specific timeframe.

    Args:
        timeframe: MT5 timeframe value (1, 5, 15, 60, etc.)

    Returns:
        Dictionary with timeframe-specific settings
    """
    return {
        'data_limit': TIMEFRAME_DATA_LIMITS.get(timeframe, 2000),
        'min_trades': TIMEFRAME_MIN_TRADES.get(timeframe, 20),
        'timeframe_name': next((k for k, v in TIMEFRAMES.items() if v == timeframe), f"TF{timeframe}")
    }
