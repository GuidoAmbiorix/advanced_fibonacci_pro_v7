from typing import Dict, Any, Optional
from loguru import logger

# Import Engines
from app.engines.golden.core import GoldenEngine
from app.engines.silver.core import SilverEngine
from app.engines.bronze.core import BronzeEngine

class EngineFactory:
    """
    Factory to instantiate the correct Trading Engine based on configuration.
    Types:
    - GOLDEN: Trend Retracement (Fibonacci)
    - SILVER: Momentum Scalp (MACD/RSI)
    - BRONZE: Mean Reversion (Bollinger)
    """
    
    @staticmethod
    def create_engine(engine_type: str, config: Dict[str, Any]):
        engine_type = engine_type.lower()
        
        logger.info(f"🏭 EngineFactory: Requesting engine type '{engine_type}'")
        
        if engine_type == 'golden':
            return GoldenEngine(config)
            
        elif engine_type == 'silver':
            return SilverEngine(config)
            
        elif engine_type == 'bronze':
            return BronzeEngine(config)
            
        else:
            logger.warning(f"Unknown engine type '{engine_type}', defaulting to GoldenEngine")
            return GoldenEngine(config)
