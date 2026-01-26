"""
MT5 Import Compatibility Layer
Automatically uses mt5linux (Wine/Linux) or MetaTrader5 (Windows)
"""

# Try mt5linux first (for Wine/Linux environment)
try:
    import mt5linux as mt5
    MT5_AVAILABLE = True
    MT5_MODE = "mt5linux"
except ImportError:
    # Fallback to MetaTrader5 (Windows only)
    try:
        import MetaTrader5 as mt5
        MT5_AVAILABLE = True
        MT5_MODE = "MetaTrader5"
    except ImportError:
        # Neither available
        mt5 = None
        MT5_AVAILABLE = False
        MT5_MODE = "none"

# Export for easy importing
__all__ = ['mt5', 'MT5_AVAILABLE', 'MT5_MODE']
