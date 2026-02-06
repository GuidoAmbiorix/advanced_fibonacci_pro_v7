# Optimizer Configuration
# Defines the search spaces for Optuna covering all DatabaseManager.mqh inputs

PARAM_SPACES = {
    "default": {
        # --- Fibonacci ---
        "swing_lookback": {"type": "int", "low": 20, "high": 100, "step": 10},
        "zone_tolerance": {"type": "float", "low": 0.05, "high": 0.2, "step": 0.01},
        
        # --- Displacement ---
        "use_displacement": {"type": "int", "low": 0, "high": 1},
        "displacement_atr": {"type": "float", "low": 0.5, "high": 3.0, "step": 0.1},
        "displacement_lookback": {"type": "int", "low": 5, "high": 30, "step": 5},
        
        # --- RSI ---
        "rsi_period": {"type": "int", "low": 7, "high": 21, "step": 1},
        "rsi_oversold": {"type": "int", "low": 20, "high": 40, "step": 5},
        "rsi_overbought": {"type": "int", "low": 60, "high": 80, "step": 5},
        
        # --- Trend ---
        "ema_period": {"type": "int", "low": 50, "high": 200, "step": 25},
        "ema_min_slope": {"type": "float", "low": 0.0, "high": 0.5, "step": 0.1},
        
        # --- Chop Filter ---
        "use_chop_filter": {"type": "int", "low": 0, "high": 1},
        "chop_threshold": {"type": "float", "low": 35.0, "high": 60.0, "step": 5.0},
        
        # --- Confluence ---
        "min_confluence_entry": {"type": "int", "low": 8, "high": 14, "step": 1},
        
        # --- Risk Management ---
        "risk_base": {"type": "float", "low": 0.1, "high": 0.5, "step": 0.05},
        "max_risk": {"type": "float", "low": 1.0, "high": 3.0, "step": 0.5},
        "enable_adaptive_risk": {"type": "int", "low": 0, "high": 1},
        
        # --- Take Profit ---
        "fixed_tp_r": {"type": "float", "low": 1.5, "high": 5.0, "step": 0.1},
        "min_tp_r": {"type": "float", "low": 1.0, "high": 2.0, "step": 0.1},
        
        # --- Trailing Stop ---
        "trail_start_r": {"type": "float", "low": 0.5, "high": 2.0, "step": 0.1},
        "trail_atr_mult": {"type": "float", "low": 1.0, "high": 3.0, "step": 0.1},
        
        # --- Volatility ---
        "volatility_threshold": {"type": "float", "low": 2.0, "high": 6.0, "step": 0.5},
        
        # --- Spread ---
        "max_spread_points": {"type": "int", "low": 20, "high": 100, "step": 10},
    },
    
    "JPY": {
        "risk_base": {"type": "float", "low": 0.2, "high": 0.6, "step": 0.05},
        "fixed_tp_r": {"type": "float", "low": 2.0, "high": 6.0, "step": 0.2}, 
        "trail_atr_mult": {"type": "float", "low": 1.5, "high": 4.0, "step": 0.2},
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

# Optimization Settings
OPTIMIZATION_SETTINGS = {
    "n_trials": 100,          # Increased trials for larger search space
    "train_days": 90,         
    "test_days": 14,          
    "min_trades": 30,         
    "target_metric": "sharpe" 
}
