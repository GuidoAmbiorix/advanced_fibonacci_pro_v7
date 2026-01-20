"""
============================================================================
Phase 1 Enhancement Configuration
============================================================================
Configuration for BOS/CHoCH, Dynamic SL, Time Filters, and Partial Profits
"""

# ============================================================================
# BOS/CHoCH Settings
# ============================================================================
BOS_LOOKBACK_BARS = 50  # How far back to look for structure breaks
BOS_CONFLUENCE_POINTS = 2  # Confluence points for BOS confirmation
CHOCH_CONFLUENCE_POINTS = 3  # Higher points for high-quality reversals
BOS_RECENT_BARS = 10  # BOS must occur within last N bars to be valid

# ============================================================================
# Dynamic Stop Loss Settings
# ============================================================================
BREATHER_PIPS = 10  # Pips beyond structure for stop placement
MAX_SL_ATR_MULTIPLE = 2.5  # Max SL distance in ATR units
MIN_SL_PIPS = 15  # Minimum stop distance in pips
USE_STRUCTURE_SL = True  # Enable structure-based SL (vs fixed ATR)

# ============================================================================
# Time Filter Settings
# ============================================================================
NEWS_BLACKOUT_HOURS = 0.5  # Hours before/after major news
AVOID_ASIAN_SESSION = True  # Reduce signals during Asian session
LONDON_NY_OVERLAP_BOOST = True  # Boost signals during overlap
REDUCE_ASIAN_SCORE_BY = 1  # Points to subtract during Asian session

# Market Session Times (UTC)
ASIAN_SESSION_START = 0
ASIAN_SESSION_END = 7
LONDON_SESSION_START = 7
LONDON_SESSION_END = 16
OVERLAP_SESSION_START = 12
OVERLAP_SESSION_END = 16
NY_SESSION_START = 12
NY_SESSION_END = 21

# ============================================================================
# Partial Profit Settings
# ============================================================================
TP1_PERCENTAGE = 0.50  # Close 50% at TP1
TP2_PERCENTAGE = 0.30  # Close 30% at TP2
TRAIL_PERCENTAGE = 0.20  # Trail remaining 20%
MOVE_SL_TO_BE_AT_TP1 = True  # Move SL to breakeven after TP1
ENABLE_PARTIAL_PROFITS = True  # Master switch for partial profit taking
PARTIAL_PROFIT_CHECK_INTERVAL = 30  # Seconds between checks

# ============================================================================
# High-Impact News Events (for time filtering)
# ============================================================================
HIGH_IMPACT_KEYWORDS = [
    "NFP", "Non-Farm Payrolls", "Non Farm Payrolls",
    "FOMC", "Federal Reserve", "Fed Rate",
    "CPI", "Consumer Price", "Inflation",
    "GDP", "Gross Domestic",
    "Employment", "Unemployment",
    "Retail Sales",
    "Interest Rate Decision"
]

# Currency-specific news sources
CURRENCY_NEWS_MAP = {
    "USD": ["United States", "US", "USA"],
    "EUR": ["Eurozone", "Euro Area", "ECB"],
    "GBP": ["United Kingdom", "UK", "BOE"],
    "JPY": ["Japan", "BOJ"],
    "AUD": ["Australia", "RBA"],
    "NZD": ["New Zealand", "RBNZ"],
    "CAD": ["Canada", "BOC"],
    "CHF": ["Switzerland", "SNB"]
}
