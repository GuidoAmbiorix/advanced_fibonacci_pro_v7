"""
============================================================================
INSTRUMENT CONFIGURATION MODULE
============================================================================
Provides symbol-specific trading parameters for different asset classes.
Handles pip sizes, contract sizes, pip values, spread tolerances, and risk adjustments.
"""

from dataclasses import dataclass
from typing import Dict, Optional
from loguru import logger


@dataclass
class InstrumentProfile:
    """
    Trading parameters for a specific instrument type.
    
    Attributes:
        pip_size: Price movement that equals 1 pip (e.g., 0.0001 for EURUSD, 0.01 for Gold)
        contract_size: Units per standard lot (100,000 for Forex, 100 oz for Gold)
        pip_value_per_lot: USD value of 1 pip movement for 1 standard lot
        max_spread_pips: Maximum acceptable spread in pips
        risk_multiplier: Adjustment factor for risk % (0.5 = reduce risk by 50%)
        atr_multiplier: Multiplier for ATR-based calculations (wider for volatile)
        symbol_type: Category ("forex", "commodity", "crypto", "index")
        description: Human-readable description
    """
    pip_size: float
    contract_size: float
    pip_value_per_lot: float
    max_spread_pips: float
    risk_multiplier: float
    atr_multiplier: float
    symbol_type: str
    description: str = ""


# ============================================================================
# INSTRUMENT PROFILES REGISTRY
# ============================================================================

# Gold profiles (symbol variations for different brokers)
GOLD_PROFILE = InstrumentProfile(
    pip_size=0.01,           # Most brokers: 0.01 (some use 0.10)
    contract_size=100.0,     # 100 troy ounces per lot
    pip_value_per_lot=1.0,   # $1 per 0.01 pip per lot
    max_spread_pips=50.0,    # Gold spreads are typically 15-50 pips
    risk_multiplier=0.5,     # Reduce risk by 50% due to high volatility
    atr_multiplier=2.0,      # Use 2x ATR for SL/TP calculations
    symbol_type="commodity",
    description="Gold (XAU/USD)"
)

# Standard Forex profile (majors)
FOREX_MAJOR_PROFILE = InstrumentProfile(
    pip_size=0.0001,          # 4th decimal place
    contract_size=100000.0,   # 100,000 units
    pip_value_per_lot=10.0,   # ~$10 per pip for USD pairs
    max_spread_pips=3.0,      # Tight spreads for majors
    risk_multiplier=1.0,      # Full risk
    atr_multiplier=1.5,       # Standard ATR multiplier
    symbol_type="forex",
    description="Forex Major"
)

# JPY pairs (3 decimal pricing)
FOREX_JPY_PROFILE = InstrumentProfile(
    pip_size=0.01,            # 2nd decimal place for JPY pairs
    contract_size=100000.0,
    pip_value_per_lot=10.0,   # ~$10 per pip for USDJPY
    max_spread_pips=3.0,
    risk_multiplier=1.0,
    atr_multiplier=1.5,
    symbol_type="forex",
    description="Forex JPY Pair"
)

# Crypto profile (BTC, ETH)
CRYPTO_PROFILE = InstrumentProfile(
    pip_size=1.0,             # $1 movement
    contract_size=1.0,        # 1 unit per lot (varies by broker)
    pip_value_per_lot=1.0,    # Varies significantly
    max_spread_pips=50.0,     # High spreads for crypto
    risk_multiplier=0.5,      # Reduce risk due to extreme volatility
    atr_multiplier=2.5,       # Wide ATR for crypto
    symbol_type="crypto",
    description="Cryptocurrency"
)

# Indices profile (US30, NAS100, etc.)
INDEX_PROFILE = InstrumentProfile(
    pip_size=1.0,             # 1 point
    contract_size=1.0,        # Varies by broker
    pip_value_per_lot=1.0,    # Varies by index
    max_spread_pips=5.0,      # Moderate spreads
    risk_multiplier=0.75,     # Slightly reduced risk
    atr_multiplier=1.5,
    symbol_type="index",
    description="Stock Index"
)


# ============================================================================
# SYMBOL MAPPING
# ============================================================================

# Explicit symbol -> profile mapping
SYMBOL_PROFILES: Dict[str, InstrumentProfile] = {
    # Gold variations
    "XAUUSD": GOLD_PROFILE,
    "XAUUSDm": GOLD_PROFILE,  # With suffix
    "GOLD": GOLD_PROFILE,
    
    # JPY pairs
    "USDJPY": FOREX_JPY_PROFILE,
    "USDJPYm": FOREX_JPY_PROFILE,
    "EURJPY": FOREX_JPY_PROFILE,
    "EURJPYm": FOREX_JPY_PROFILE,
    "GBPJPY": FOREX_JPY_PROFILE,
    "GBPJPYm": FOREX_JPY_PROFILE,
    
    # Crypto
    "BTCUSD": CRYPTO_PROFILE,
    "BTCUSDm": CRYPTO_PROFILE,
    "#BTC": CRYPTO_PROFILE,      # HFM format
    "#BTCUSD": CRYPTO_PROFILE,   # HFM format with USD
    "ETHUSD": CRYPTO_PROFILE,
    "ETHUSDm": CRYPTO_PROFILE,
    
    # Indices
    "US30": INDEX_PROFILE,
    "US30m": INDEX_PROFILE,
    "NAS100": INDEX_PROFILE,
    "NAS100m": INDEX_PROFILE,
    "SPX500": INDEX_PROFILE,
    "SPX500m": INDEX_PROFILE,
}


def get_instrument_profile(symbol: str) -> InstrumentProfile:
    """
    Get the instrument profile for a symbol.
    
    Args:
        symbol: Trading symbol (e.g., "EURUSD", "XAUUSD", "BTCUSD")
        
    Returns:
        InstrumentProfile with symbol-specific parameters
    """
    # Check explicit mapping first
    if symbol in SYMBOL_PROFILES:
        return SYMBOL_PROFILES[symbol]
    
    # Check for Gold variants
    symbol_upper = symbol.upper()
    if "XAU" in symbol_upper or "GOLD" in symbol_upper:
        logger.debug(f"Symbol {symbol} matched as Gold")
        return GOLD_PROFILE
    
    # Check for JPY pairs
    if "JPY" in symbol_upper and len(symbol_upper) >= 6:
        logger.debug(f"Symbol {symbol} matched as JPY pair")
        return FOREX_JPY_PROFILE
    
    # Check for Crypto
    if any(crypto in symbol_upper for crypto in ["BTC", "ETH", "XRP", "LTC"]):
        logger.debug(f"Symbol {symbol} matched as Crypto")
        return CRYPTO_PROFILE
    
    # Check for Indices
    if any(idx in symbol_upper for idx in ["US30", "NAS", "SPX", "DAX", "FTSE"]):
        logger.debug(f"Symbol {symbol} matched as Index")
        return INDEX_PROFILE
    
    # Default: Forex major
    logger.debug(f"Symbol {symbol} using default Forex profile")
    return FOREX_MAJOR_PROFILE


def get_symbol_type(symbol: str) -> str:
    """
    Get the symbol type for a given symbol.
    
    Args:
        symbol: Trading symbol
        
    Returns:
        Symbol type string ("forex", "commodity", "crypto", "index")
    """
    profile = get_instrument_profile(symbol)
    return profile.symbol_type


def is_high_volatility_symbol(symbol: str) -> bool:
    """
    Check if a symbol is considered high volatility.
    
    Args:
        symbol: Trading symbol
        
    Returns:
        True if high volatility (risk_multiplier < 1.0)
    """
    profile = get_instrument_profile(symbol)
    return profile.risk_multiplier < 1.0
