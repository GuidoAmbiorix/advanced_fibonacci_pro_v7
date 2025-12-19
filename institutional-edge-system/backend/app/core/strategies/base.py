from abc import ABC, abstractmethod
import pandas as pd
from typing import Optional, Dict, Any

class BaseStrategy(ABC):
    """
    Abstract Base Class for all trading strategies.
    Ensures a consistent interface for the Strategy Factory and Engines.
    """

    def __init__(self, config: Dict[str, Any]):
        """
        Initialize the strategy with configuration parameters.
        
        Args:
            config: Dictionary containing strategy-specific parameters (e.g., periods, thresholds).
        """
        self.config = config
        self.symbol = config.get('symbol', 'UNKNOWN')
        self.timeframe = config.get('timeframe', 'UNKNOWN')

    @abstractmethod
    def analyze(self, df: pd.DataFrame, df_higher_tf: Optional[pd.DataFrame] = None) -> Dict[str, Any]:
        """
        Analyze market data and generate signals.

        Args:
            df: DataFrame containing OHLCV data for the current timeframe.
            df_higher_tf: Optional DataFrame for higher timeframe data (for trend confirmation).

        Returns:
            Dict containing:
            - 'signals': List of Signal objects (or dicts).
            - 'metadata': Any additional info (e.g., indicators values).
            - 'regime': Detected market regime (optional).
        """
        pass
