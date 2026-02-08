"""
Portfolio-Level Optimizer Configuration (V2)

Three-tier parameter classification:
- FROZEN: Architecture parameters that define the strategy (never optimize)
- TUNABLE: Execution parameters that can be optimized (≤12 params)
- FORBIDDEN: Parameters that break the strategy if optimized

This prevents Optuna from redesigning the strategy and focuses on execution tuning.
"""

# ============================================================================
# FROZEN PARAMETERS - Strategy Architecture (Hard-coded, never optimize)
# ============================================================================
# These define WHAT the strategy IS. Changing these = different strategy.

FROZEN_PARAMS = {
    # Core strategy logic (non-negotiable)
    "use_smc": 1,                      # SMC is core to the edge
    "use_mtf": 1,                      # Multi-timeframe confirmation required
    "use_displacement": 1,             # Displacement is part of the signal
    "use_chop_filter": 1,              # Chop filter prevents bad trades
    "use_trend_filter": 1,             # Trend alignment required
    "use_news_filter": 1,              # News filter is risk management

    # Session filters (hard-code your session strategy)
    "use_killzone_filter": 1,          # Trade specific killzones
    "enable_london_open_kz": 1,        # London open killzone
    "enable_ny_kz": 1,                 # New York killzone
    "enable_asian_kz": 0,              # Disable Asian (typically)
    "enable_london_close_kz": 0,       # Disable London close

    # Optional filters (decide based on your edge)
    "use_volume_filter": 0,            # Optional, test separately
    "use_correlation_filter": 1,       # Prevent correlated entries
    "use_reversal_filter": 1,          # Reversal protection

    # Risk management architecture (stable foundation)
    "enable_margin_check": 1,          # Always check margin
    "use_session_governor": 1,         # Limit trades per session
    "max_trades_per_session": 2,       # Max 2 trades per session (conservative)
    "trade_cooldown_minutes": 30,      # 30min cooldown between trades

    # Exit mode (pick one strategy)
    "tp_mode": 0,                      # 0=Fixed R, 1=Dynamic (use fixed initially)
    "trailing_mode": 1,                # Trailing enabled

    # Learning & adaptation (disable during optimization)
    "enable_learning": 0,              # Turn OFF during optimization
    "enable_adaptive_risk": 0,         # Turn OFF during optimization
    "enable_adaptive_exits": 0,        # Turn OFF during optimization
    "enable_adaptive_filters": 0,      # Turn OFF during optimization

    # Addons (disable for simplicity)
    "enable_addons": 0,                # No addon positions during optimization

    # Database/logging
    "log_trades_to_file": 1,           # Keep logs
}


# ============================================================================
# TUNABLE PARAMETERS - Execution Tuning (Optimize these, ≤12 params)
# ============================================================================
# These control HOW the strategy executes, not WHAT it is.
# Narrow ranges prevent overfitting.

TUNABLE_PARAMS = {
    # --- Fibonacci Structure (4 params) ---
    "swing_lookback": {"type": "int", "low": 30, "high": 80, "step": 10},
    "zone_tolerance": {"type": "float", "low": 0.08, "high": 0.15, "step": 0.01},
    "fib_level_low": {"type": "float", "low": 0.38, "high": 0.70, "step": 0.01},
    "fib_level_high": {"type": "float", "low": 0.65, "high": 0.88, "step": 0.01},

    # --- ATR & Volatility (2 params) ---
    "atr_period": {"type": "int", "low": 12, "high": 18, "step": 2},
    "chop_threshold": {"type": "float", "low": 0.4, "high": 0.7, "step": 0.05},

    # --- Entry Threshold (1 param) ---
    "min_confluence_entry": {"type": "int", "low": 12, "high": 22, "step": 2},

    # --- Risk (1 param - conservative range) ---
    "risk_base": {"type": "float", "low": 0.3, "high": 0.7, "step": 0.05},

    # --- Take Profit (2 params) ---
    "fixed_tp_r": {"type": "float", "low": 2.0, "high": 4.0, "step": 0.2},
    "min_tp_r": {"type": "float", "low": 1.5, "high": 2.5, "step": 0.2},

    # --- Trailing (2 params) ---
    "trail_start_r": {"type": "float", "low": 1.0, "high": 2.0, "step": 0.2},
    "trail_atr_mult": {"type": "float", "low": 1.5, "high": 2.5, "step": 0.2},
}

# Total tunable params: 12 (perfect!)


# ============================================================================
# FORBIDDEN PARAMETERS - Never Optimize (Use Strategy Defaults)
# ============================================================================
# These break the strategy if optimized. Use sensible defaults.

FORBIDDEN_PARAMS = {
    # Risk controls that compensate for weak entries if optimized
    "use_kelly": 0,
    "kelly_fraction": 0.25,
    "max_risk": 2.0,
    "max_lots_per_trade": 10.0,

    # Partial TP (use fixed logic, don't optimize)
    "use_partial_tp": 0,
    "partial_tp_r": 1.5,
    "partial_close_percent": 0.5,

    # Breakeven (use sensible default)
    "be_threshold_r": 0.8,

    # Stop management
    "max_spread_points": 30,

    # Position limits (conservative defaults)
    "max_positions": 3,
    "max_consecutive_losses": 3,
    "reversal_cooldown_minutes": 60,

    # Session rules (hard-coded in FROZEN)
    "trade_asia": 0,
    "trade_london": 1,
    "trade_newyork": 1,
    "avoid_rollover": 1,

    # Pattern recognition (disable or hard-code)
    "use_engulfing": 0,
    "use_pinbar": 0,
    "pattern_min_size_atr": 1.0,

    # Time-based exits (use defaults)
    "use_time_exit": 0,
    "max_trade_duration_bars": 48,
    "weekend_close_positions": 1,

    # Exits
    "use_opposite_signal_exit": 1,

    # Volatility
    "enable_volatility_filter": 1,
    "volatility_threshold": 1.5,
    "volatility_spike_cooldown": 30,

    # News filter params
    "news_minutes_before": 30,
    "news_minutes_after": 30,

    # Daily limits
    "daily_max_dd": 0.05,
    "weekly_max_dd": 0.10,
    "daily_max_loss_r": 3.0,
    "loss_cooldown_minutes": 60,

    # Learning (disabled)
    "learning_history": 100,
    "min_trades_for_learning": 30,

    # RSI (use reasonable defaults, don't optimize)
    "rsi_period": 14,
    "rsi_oversold": 30,
    "rsi_overbought": 70,
    "rsi_momentum": 1,

    # EMA
    "ema_period": 200,
    "ema_min_slope": 0.0001,

    # Displacement
    "displacement_atr": 2.0,
    "displacement_lookback": 10,

    # SMC (use defaults)
    "smc_swing_lookback": 20,
    "smc_min_impulse_atr": 2.0,
    "smc_min_fvg_atr": 1.0,
    "smc_order_block_strength": 3,
    "smc_bos_confirmation": 1,

    # MTF
    "htf": 240,  # H4
    "mtf": 60,   # H1
    "mtf_ema_period": 50,
    "mtf_require_alignment": 1,

    # Fib extensions
    "use_fib_extensions": 0,
    "fib_ext_161": 0,
    "fib_ext_261": 0,
    "min_swing_points": 3,

    # Volume
    "volume_ma_period": 20,
    "volume_threshold_mult": 1.5,

    # Other
    "atr_sl_multiplier": 1.5,
    "min_atr_points": 10,
    "max_trades_per_day": 5,
    "daily_loss_limit_pct": 0.03,
    "position_spacing_bars": 10,
    "use_trailing_activation": 1,

    # Symbol-specific (set per symbol, don't optimize)
    "magic_number": 100001,
    "enable_mobile_alerts": 0,
    "direction": 0,  # Both
    "broker_utc_offset": 2,
    "atr_ma_period": 14,
    "tp_use_learned_mfe": 0,
}


# ============================================================================
# PORTFOLIO OPTIMIZATION SETTINGS
# ============================================================================

PORTFOLIO_SETTINGS = {
    # Symbol universe (all pairs to optimize together)
    "symbols": [
        "EURUSD", "GBPUSD", "AUDUSD", "USDCAD", "USDCHF",
        "USDJPY", "EURJPY", "AUDJPY", "GBPJPY",
        "XAUUSD"
    ],

    # Optimization settings
    "n_trials": 100,                    # Trials for portfolio optimization
    "n_jobs": 1,                        # Parallel jobs (careful with DB locks)
    "timeout": 3600,                    # 1 hour max

    # Validation
    "train_test_split": 0.75,           # 75% train, 25% test
    "min_trades_per_symbol": 5,         # Minimum trades per symbol
    "max_oos_degradation": 0.5,         # Max allowed OOS degradation

    # Portfolio metrics weights
    "objective_weights": {
        "portfolio_sharpe": 0.50,       # 50% weight on portfolio Sharpe
        "diversification_ratio": 0.20,  # 20% on diversification
        "worst_symbol_sharpe": 0.15,    # 15% on worst performer (robustness)
        "avg_correlation": -0.15,       # 15% penalty for high correlation (negative = minimize)
    },

    # Penalties
    "penalty_weights": {
        "insufficient_trades": 0.5,     # Penalty per missing trade
        "excessive_drawdown": 3.0,      # Penalty multiplier for DD > 25%
        "high_correlation": 2.0,        # Penalty for avg corr > 0.7
        "parameter_instability": 1.0,   # Penalty for param variance
    },

    # Correlation settings
    "max_allowed_correlation": 0.75,    # Flag if avg correlation exceeds this
    "correlation_window": 252,          # Days for correlation calculation

    # Risk limits (portfolio-level)
    "max_portfolio_risk": 0.05,         # Max 5% portfolio risk at once
    "max_correlated_risk": 0.03,        # Max 3% in highly correlated pairs

    # Timeframe
    "default_timeframe": 15,            # M15
    "data_limit": 5000,                 # Bars per symbol
}


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def get_all_params():
    """
    Combine all parameter sets into a complete configuration.

    Returns:
        Dictionary with all parameters (frozen + forbidden + defaults for tunable)
    """
    all_params = {}

    # Add frozen params
    all_params.update(FROZEN_PARAMS)

    # Add forbidden params
    all_params.update(FORBIDDEN_PARAMS)

    # Add default values for tunable params (middle of range)
    for key, config in TUNABLE_PARAMS.items():
        if config["type"] == "int":
            default_value = (config["low"] + config["high"]) // 2
        else:
            default_value = (config["low"] + config["high"]) / 2
        all_params[key] = default_value

    return all_params


def get_param_info():
    """Get summary of parameter classification."""
    return {
        "frozen_count": len(FROZEN_PARAMS),
        "tunable_count": len(TUNABLE_PARAMS),
        "forbidden_count": len(FORBIDDEN_PARAMS),
        "total_count": len(FROZEN_PARAMS) + len(TUNABLE_PARAMS) + len(FORBIDDEN_PARAMS),
    }


def validate_param_set(params):
    """
    Validate that a parameter set respects frozen/forbidden constraints.

    Args:
        params: Parameter dictionary to validate

    Returns:
        Tuple[bool, List[str]]: (is_valid, list of issues)
    """
    issues = []

    # Check frozen params haven't changed
    for key, frozen_value in FROZEN_PARAMS.items():
        if key in params and params[key] != frozen_value:
            issues.append(f"Frozen param '{key}' was modified: {params[key]} != {frozen_value}")

    # Check tunable params are in valid ranges
    for key, config in TUNABLE_PARAMS.items():
        if key in params:
            value = params[key]
            if value < config["low"] or value > config["high"]:
                issues.append(f"Tunable param '{key}' out of range: {value} not in [{config['low']}, {config['high']}]")

    # Check logical constraints
    if "fib_level_low" in params and "fib_level_high" in params:
        if params["fib_level_low"] > params["fib_level_high"]:
            issues.append(f"fib_level_low ({params['fib_level_low']}) > fib_level_high ({params['fib_level_high']})")

    if "min_tp_r" in params and "fixed_tp_r" in params:
        if params["min_tp_r"] > params["fixed_tp_r"]:
            issues.append(f"min_tp_r ({params['min_tp_r']}) > fixed_tp_r ({params['fixed_tp_r']})")

    return len(issues) == 0, issues


# ============================================================================
# BACKWARD COMPATIBILITY
# ============================================================================
# For existing code that uses PARAM_SPACES

PARAM_SPACES = {
    "default": TUNABLE_PARAMS  # Only expose tunable params to optimizer
}

OPTIMIZATION_SETTINGS = PORTFOLIO_SETTINGS
TOTAL_PARAM_COUNT = len(TUNABLE_PARAMS)  # Only count tunable params

# Expose timeframe settings from original config
TIMEFRAMES = {
    1: {"name": "M1", "data_limit": 10000, "min_trades": 30},
    5: {"name": "M5", "data_limit": 8000, "min_trades": 25},
    15: {"name": "M15", "data_limit": 5000, "min_trades": 20},
    30: {"name": "M30", "data_limit": 3000, "min_trades": 15},
    60: {"name": "H1", "data_limit": 2000, "min_trades": 12},
    240: {"name": "H4", "data_limit": 1000, "min_trades": 8},
}

def get_timeframe_settings(timeframe):
    """Get settings for a specific timeframe."""
    settings = TIMEFRAMES.get(timeframe, TIMEFRAMES[15])
    return {
        "timeframe": timeframe,
        "timeframe_name": settings["name"],
        "data_limit": settings["data_limit"],
        "min_trades": settings["min_trades"],
    }
