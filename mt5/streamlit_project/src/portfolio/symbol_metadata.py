"""
Symbol Metadata - Static classification of all 20 trading symbols.
Contains asset class, risk profile, volatility, sessions, and correlation hints.
"""

from enum import Enum
from typing import Dict, List
from dataclasses import dataclass


class SymbolClass(Enum):
    """Asset class classification."""
    MAJOR = "major"      # Main USD pairs
    MINOR = "minor"      # Non-USD commodity currencies
    CROSS = "cross"      # Non-USD pairs
    METAL = "metal"      # Precious metals
    INDEX = "index"      # Stock indices


class RiskProfile(Enum):
    """Risk sentiment classification."""
    RISK_ON = "risk_on"      # Benefits from optimism
    RISK_OFF = "risk_off"    # Safe haven assets
    NEUTRAL = "neutral"      # Mixed behavior


class VolatilityLevel(Enum):
    """Volatility classification."""
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    VERY_HIGH = "very_high"


class Session(Enum):
    """Trading sessions."""
    ASIAN = "asian"
    LONDON = "london"
    NY = "ny"


@dataclass
class SymbolInfo:
    """Complete symbol metadata."""
    symbol: str
    symbol_class: SymbolClass
    primary_driver: str
    volatility: VolatilityLevel
    risk_profile: RiskProfile
    sessions: List[Session]
    base_currency: str
    quote_currency: str
    description: str


# ============================================================================
# SYMBOL METADATA DICTIONARY
# ============================================================================

SYMBOL_METADATA: Dict[str, SymbolInfo] = {
    # ==================== MAJORS ====================
    "EURUSD": SymbolInfo(
        symbol="EURUSD",
        symbol_class=SymbolClass.MAJOR,
        primary_driver="EUR",
        volatility=VolatilityLevel.MEDIUM,
        risk_profile=RiskProfile.NEUTRAL,
        sessions=[Session.LONDON, Session.NY],
        base_currency="EUR",
        quote_currency="USD",
        description="Euro Dollar - Most liquid pair"
    ),
    "GBPUSD": SymbolInfo(
        symbol="GBPUSD",
        symbol_class=SymbolClass.MAJOR,
        primary_driver="GBP",
        volatility=VolatilityLevel.HIGH,
        risk_profile=RiskProfile.NEUTRAL,
        sessions=[Session.LONDON, Session.NY],
        base_currency="GBP",
        quote_currency="USD",
        description="Cable - Volatile major"
    ),
    "USDJPY": SymbolInfo(
        symbol="USDJPY",
        symbol_class=SymbolClass.MAJOR,
        primary_driver="JPY",
        volatility=VolatilityLevel.MEDIUM,
        risk_profile=RiskProfile.RISK_OFF,
        sessions=[Session.ASIAN, Session.NY],
        base_currency="USD",
        quote_currency="JPY",
        description="Gopher - Risk barometer"
    ),
    "USDCHF": SymbolInfo(
        symbol="USDCHF",
        symbol_class=SymbolClass.MAJOR,
        primary_driver="CHF",
        volatility=VolatilityLevel.LOW,
        risk_profile=RiskProfile.RISK_OFF,
        sessions=[Session.LONDON],
        base_currency="USD",
        quote_currency="CHF",
        description="Swissie - Safe haven"
    ),
    "USDCAD": SymbolInfo(
        symbol="USDCAD",
        symbol_class=SymbolClass.MAJOR,
        primary_driver="CAD",
        volatility=VolatilityLevel.MEDIUM,
        risk_profile=RiskProfile.RISK_ON,
        sessions=[Session.NY],
        base_currency="USD",
        quote_currency="CAD",
        description="Loonie - Oil correlated"
    ),

    # ==================== MINORS ====================
    "AUDUSD": SymbolInfo(
        symbol="AUDUSD",
        symbol_class=SymbolClass.MINOR,
        primary_driver="AUD",
        volatility=VolatilityLevel.HIGH,
        risk_profile=RiskProfile.RISK_ON,
        sessions=[Session.ASIAN, Session.NY],
        base_currency="AUD",
        quote_currency="USD",
        description="Aussie - Risk-on commodity"
    ),
    "NZDUSD": SymbolInfo(
        symbol="NZDUSD",
        symbol_class=SymbolClass.MINOR,
        primary_driver="NZD",
        volatility=VolatilityLevel.MEDIUM,
        risk_profile=RiskProfile.RISK_ON,
        sessions=[Session.ASIAN],
        base_currency="NZD",
        quote_currency="USD",
        description="Kiwi - Risk-on dairy"
    ),

    # ==================== JPY CROSSES ====================
    "EURJPY": SymbolInfo(
        symbol="EURJPY",
        symbol_class=SymbolClass.CROSS,
        primary_driver="Risk",
        volatility=VolatilityLevel.HIGH,
        risk_profile=RiskProfile.RISK_ON,
        sessions=[Session.LONDON, Session.ASIAN],
        base_currency="EUR",
        quote_currency="JPY",
        description="Risk sentiment indicator"
    ),
    "GBPJPY": SymbolInfo(
        symbol="GBPJPY",
        symbol_class=SymbolClass.CROSS,
        primary_driver="Risk",
        volatility=VolatilityLevel.VERY_HIGH,
        risk_profile=RiskProfile.RISK_ON,
        sessions=[Session.LONDON, Session.ASIAN],
        base_currency="GBP",
        quote_currency="JPY",
        description="Beast - Most volatile cross"
    ),
    "CADJPY": SymbolInfo(
        symbol="CADJPY",
        symbol_class=SymbolClass.CROSS,
        primary_driver="Risk",
        volatility=VolatilityLevel.MEDIUM,
        risk_profile=RiskProfile.RISK_ON,
        sessions=[Session.ASIAN, Session.NY],
        base_currency="CAD",
        quote_currency="JPY",
        description="Commodity-risk cross"
    ),
    "CHFJPY": SymbolInfo(
        symbol="CHFJPY",
        symbol_class=SymbolClass.CROSS,
        primary_driver="Safe",
        volatility=VolatilityLevel.MEDIUM,
        risk_profile=RiskProfile.RISK_OFF,
        sessions=[Session.ASIAN],
        base_currency="CHF",
        quote_currency="JPY",
        description="Safe haven cross"
    ),
    "NZDJPY": SymbolInfo(
        symbol="NZDJPY",
        symbol_class=SymbolClass.CROSS,
        primary_driver="Risk",
        volatility=VolatilityLevel.MEDIUM,
        risk_profile=RiskProfile.RISK_ON,
        sessions=[Session.ASIAN],
        base_currency="NZD",
        quote_currency="JPY",
        description="Carry trade cross"
    ),
    "AUDJPY": SymbolInfo(
        symbol="AUDJPY",
        symbol_class=SymbolClass.CROSS,
        primary_driver="Risk",
        volatility=VolatilityLevel.HIGH,
        risk_profile=RiskProfile.RISK_ON,
        sessions=[Session.ASIAN],
        base_currency="AUD",
        quote_currency="JPY",
        description="Risk-on carry trade"
    ),

    # ==================== EUR/GBP CROSSES ====================
    "EURAUD": SymbolInfo(
        symbol="EURAUD",
        symbol_class=SymbolClass.CROSS,
        primary_driver="EUR",
        volatility=VolatilityLevel.HIGH,
        risk_profile=RiskProfile.NEUTRAL,
        sessions=[Session.LONDON],
        base_currency="EUR",
        quote_currency="AUD",
        description="EUR vs commodity"
    ),
    "EURCHF": SymbolInfo(
        symbol="EURCHF",
        symbol_class=SymbolClass.CROSS,
        primary_driver="EUR",
        volatility=VolatilityLevel.LOW,
        risk_profile=RiskProfile.NEUTRAL,
        sessions=[Session.LONDON],
        base_currency="EUR",
        quote_currency="CHF",
        description="European safe haven"
    ),
    "EURGBP": SymbolInfo(
        symbol="EURGBP",
        symbol_class=SymbolClass.CROSS,
        primary_driver="EUR",
        volatility=VolatilityLevel.LOW,
        risk_profile=RiskProfile.NEUTRAL,
        sessions=[Session.LONDON],
        base_currency="EUR",
        quote_currency="GBP",
        description="Euro Sterling"
    ),
    "GBPAUD": SymbolInfo(
        symbol="GBPAUD",
        symbol_class=SymbolClass.CROSS,
        primary_driver="GBP",
        volatility=VolatilityLevel.VERY_HIGH,
        risk_profile=RiskProfile.NEUTRAL,
        sessions=[Session.LONDON],
        base_currency="GBP",
        quote_currency="AUD",
        description="GBP vs commodity"
    ),

    # ==================== METALS ====================
    "XAUUSD": SymbolInfo(
        symbol="XAUUSD",
        symbol_class=SymbolClass.METAL,
        primary_driver="Risk-Off",
        volatility=VolatilityLevel.VERY_HIGH,
        risk_profile=RiskProfile.RISK_OFF,
        sessions=[Session.LONDON, Session.NY],
        base_currency="XAU",
        quote_currency="USD",
        description="Gold - Ultimate safe haven"
    ),
    "XAGUSD": SymbolInfo(
        symbol="XAGUSD",
        symbol_class=SymbolClass.METAL,
        primary_driver="Risk-Off",
        volatility=VolatilityLevel.VERY_HIGH,
        risk_profile=RiskProfile.RISK_OFF,
        sessions=[Session.LONDON, Session.NY],
        base_currency="XAG",
        quote_currency="USD",
        description="Silver - Industrial metal"
    ),

    # ==================== INDICES ====================
    "US30": SymbolInfo(
        symbol="US30",
        symbol_class=SymbolClass.INDEX,
        primary_driver="Risk-On",
        volatility=VolatilityLevel.HIGH,
        risk_profile=RiskProfile.RISK_ON,
        sessions=[Session.NY],
        base_currency="US30",
        quote_currency="USD",
        description="Dow Jones Industrial Average"
    ),
}


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def get_all_symbols() -> List[str]:
    """Return list of all 20 symbols."""
    return list(SYMBOL_METADATA.keys())


def get_symbols_by_class(symbol_class: SymbolClass) -> List[str]:
    """Get all symbols of a specific class."""
    return [
        symbol for symbol, info in SYMBOL_METADATA.items()
        if info.symbol_class == symbol_class
    ]


def get_symbols_by_risk_profile(risk_profile: RiskProfile) -> List[str]:
    """Get all symbols with a specific risk profile."""
    return [
        symbol for symbol, info in SYMBOL_METADATA.items()
        if info.risk_profile == risk_profile
    ]


def get_symbols_by_session(session: Session) -> List[str]:
    """Get all symbols active in a specific session."""
    return [
        symbol for symbol, info in SYMBOL_METADATA.items()
        if session in info.sessions
    ]


def get_currency_exposure(symbol: str) -> Dict[str, float]:
    """
    Get currency exposure for a symbol.
    Returns dict with currency: exposure_factor.
    Long position: base +1, quote -1
    """
    info = SYMBOL_METADATA.get(symbol)
    if not info:
        return {}
    
    return {
        info.base_currency: 1.0,
        info.quote_currency: -1.0
    }


def get_primary_driver(symbol: str) -> str:
    """Get the primary driver for symbol selection."""
    info = SYMBOL_METADATA.get(symbol)
    return info.primary_driver if info else ""
