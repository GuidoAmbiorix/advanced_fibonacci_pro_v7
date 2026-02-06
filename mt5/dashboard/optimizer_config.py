# Optimizer Configuration
# Defines the search spaces for Optuna

PARAM_SPACES = {
    "default": {
        "risk_base": {"type": "float", "low": 0.1, "high": 0.5, "step": 0.05},
        "fixed_tp_r": {"type": "float", "low": 1.5, "high": 4.0, "step": 0.1},
        "trail_start_r": {"type": "float", "low": 0.5, "high": 2.0, "step": 0.1},
        "trail_atr_mult": {"type": "float", "low": 1.0, "high": 3.0, "step": 0.1},
        "min_confluence_entry": {"type": "int", "low": 8, "high": 15},
    },
    
    "JPY": {
        "risk_base": {"type": "float", "low": 0.2, "high": 0.6, "step": 0.05},
        "fixed_tp_r": {"type": "float", "low": 2.0, "high": 5.0, "step": 0.1}, # JPY trends harder
        "trail_atr_mult": {"type": "float", "low": 1.5, "high": 4.0, "step": 0.2},
    },
    
    "XAU": {
        "risk_base": {"type": "float", "low": 0.3, "high": 1.0, "step": 0.1},
        "fixed_tp_r": {"type": "float", "low": 2.5, "high": 6.0, "step": 0.2},
        "volatility_threshold": {"type": "float", "low": 3.0, "high": 8.0, "step": 0.5},
        "max_spread_points": {"type": "int", "low": 50, "high": 150},
    }
}

# Optimization Settings
OPTIMIZATION_SETTINGS = {
    "n_trials": 50,           # Number of trials per optimization run
    "train_days": 90,         # Lookback period for training
    "test_days": 14,          # Out-of-Sample verification period
    "min_trades": 30,         # Minimum trades required to consider a result valid
    "target_metric": "sharpe" # maximize: sharpe, win_rate, or profit
}
