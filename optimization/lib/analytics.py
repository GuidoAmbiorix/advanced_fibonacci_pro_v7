"""
Advanced Analytics Module for Trading Optimization
Integrates: QuantStats, pandas-ta, SHAP
"""
import pandas as pd
import numpy as np
import optuna
from typing import Optional, Dict, List
import os

# Lazy imports to avoid startup overhead
def get_quantstats():
    import quantstats as qs
    return qs

def get_shap():
    import shap
    return shap

def get_sklearn():
    from sklearn.ensemble import RandomForestRegressor
    return RandomForestRegressor

# ============================================================
# QUANTSTATS: Performance Analytics
# ============================================================

def generate_performance_report(returns: pd.Series, benchmark: Optional[pd.Series] = None, output_path: str = None) -> str:
    """
    Generate a QuantStats HTML tearsheet report.
    
    Args:
        returns: Series of daily returns (index=date, values=pct return)
        benchmark: Optional benchmark returns for comparison
        output_path: Path to save HTML report
        
    Returns:
        Path to generated HTML file
    """
    qs = get_quantstats()
    
    if output_path is None:
        output_path = "quantstats_report.html"
    
    # Extend pandas with quantstats
    qs.extend_pandas()
    
    # Generate full report
    qs.reports.html(
        returns, 
        benchmark=benchmark,
        output=output_path,
        title="Strategy Performance Report"
    )
    
    return output_path

def calculate_performance_metrics(returns: pd.Series) -> Dict:
    """
    Calculate key performance metrics using QuantStats.
    
    Args:
        returns: Series of daily returns
        
    Returns:
        Dictionary of metrics
    """
    qs = get_quantstats()
    
    metrics = {
        "sharpe_ratio": qs.stats.sharpe(returns),
        "sortino_ratio": qs.stats.sortino(returns),
        "max_drawdown": qs.stats.max_drawdown(returns),
        "calmar_ratio": qs.stats.calmar(returns),
        "win_rate": qs.stats.win_rate(returns),
        "profit_factor": qs.stats.profit_factor(returns),
        "avg_win": qs.stats.avg_win(returns),
        "avg_loss": qs.stats.avg_loss(returns),
        "volatility": qs.stats.volatility(returns),
        "cagr": qs.stats.cagr(returns)
    }
    
    return metrics

# ============================================================
# SHAP: Parameter Explainability
# ============================================================

def explain_optuna_params(study: optuna.Study, top_n: int = 10):
    """
    Use SHAP to explain which parameters matter most.
    
    Args:
        study: Completed Optuna study
        top_n: Number of top parameters to show
        
    Returns:
        shap_values, feature_names, explainer
    """
    shap = get_shap()
    RandomForestRegressor = get_sklearn()
    
    # Extract trials data
    trials_data = []
    for trial in study.trials:
        if trial.state == optuna.trial.TrialState.COMPLETE and trial.value is not None:
            row = trial.params.copy()
            row['_value'] = trial.value
            trials_data.append(row)
    
    if len(trials_data) < 10:
        raise ValueError("Need at least 10 completed trials for SHAP analysis")
    
    df = pd.DataFrame(trials_data)
    
    # Prepare features and target
    feature_cols = [c for c in df.columns if c != '_value']
    X = df[feature_cols]
    y = df['_value']
    
    # Handle categorical features (convert to numeric)
    for col in X.columns:
        if X[col].dtype == 'object':
            X[col] = pd.Categorical(X[col]).codes
    
    # Train a simple model to understand feature importance
    model = RandomForestRegressor(n_estimators=100, random_state=42, n_jobs=-1)
    model.fit(X, y)
    
    # Calculate SHAP values
    explainer = shap.TreeExplainer(model)
    shap_values = explainer.shap_values(X)
    
    return shap_values, feature_cols, explainer, X

def get_shap_summary_fig(shap_values, feature_names, X):
    """
    Generate SHAP summary plot as matplotlib figure.
    """
    import matplotlib.pyplot as plt
    shap = get_shap()
    
    fig, ax = plt.subplots(figsize=(10, 6))
    shap.summary_plot(shap_values, X, feature_names=feature_names, show=False)
    plt.tight_layout()
    
    return fig

def get_feature_importance_df(shap_values, feature_names) -> pd.DataFrame:
    """
    Get feature importance as a DataFrame.
    """
    importance = np.abs(shap_values).mean(axis=0)
    
    df = pd.DataFrame({
        'Parameter': feature_names,
        'Importance': importance
    }).sort_values('Importance', ascending=False)
    
    return df

# ============================================================
# TA: Technical Indicator Utilities (using 'ta' library)
# ============================================================

def calculate_indicators(ohlc_df: pd.DataFrame) -> pd.DataFrame:
    """
    Calculate common technical indicators on OHLC data.
    
    Args:
        ohlc_df: DataFrame with columns: open, high, low, close, volume (optional)
        
    Returns:
        DataFrame with added indicator columns
    """
    import ta
    
    # Standardize column names
    df = ohlc_df.copy()
    df.columns = [c.lower() for c in df.columns]
    
    # Calculate indicators using 'ta' library
    df['rsi'] = ta.momentum.RSIIndicator(df['close'], window=14).rsi()
    df['adx'] = ta.trend.ADXIndicator(df['high'], df['low'], df['close'], window=14).adx()
    df['atr'] = ta.volatility.AverageTrueRange(df['high'], df['low'], df['close'], window=14).average_true_range()
    
    # Bollinger Bands
    bb = ta.volatility.BollingerBands(df['close'], window=20, window_dev=2)
    df['bb_upper'] = bb.bollinger_hband()
    df['bb_middle'] = bb.bollinger_mavg()
    df['bb_lower'] = bb.bollinger_lband()
    
    # MACD
    macd = ta.trend.MACD(df['close'], window_slow=26, window_fast=12, window_sign=9)
    df['macd'] = macd.macd()
    df['macd_signal'] = macd.macd_signal()
    
    # SMAs
    df['sma_50'] = ta.trend.SMAIndicator(df['close'], window=50).sma_indicator()
    df['sma_200'] = ta.trend.SMAIndicator(df['close'], window=200).sma_indicator()
    
    # Stochastic
    stoch = ta.momentum.StochasticOscillator(df['high'], df['low'], df['close'], window=14, smooth_window=3)
    df['stoch_k'] = stoch.stoch()
    df['stoch_d'] = stoch.stoch_signal()
    
    return df

def validate_indicator_values(mq5_values: Dict, python_values: Dict, tolerance: float = 0.01) -> Dict:
    """
    Compare MQL5 indicator values against Python calculations.
    
    Args:
        mq5_values: Dict of indicator values from MQL5
        python_values: Dict of indicator values from pandas-ta
        tolerance: Acceptable difference threshold
        
    Returns:
        Dict of comparison results
    """
    results = {}
    
    for key in mq5_values:
        if key in python_values:
            mq5_val = float(mq5_values[key])
            py_val = float(python_values[key])
            diff = abs(mq5_val - py_val)
            
            results[key] = {
                'mq5': mq5_val,
                'python': py_val,
                'difference': diff,
                'match': diff <= tolerance
            }
    
    return results
