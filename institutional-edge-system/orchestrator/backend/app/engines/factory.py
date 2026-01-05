from typing import Dict, Any, Optional
from loguru import logger

# Import Engines
from app.engines.golden.core import GoldenEngine
from app.engines.xau_pro.core import InstitutionalGoldEngine

class EngineFactory:
    """
    Factory to instantiate the Trading Engine.
    
    Pivot Update:
    - XAU_PRO: The new Institutional Gold Engine (Default).
    - GOLDEN: Kept for legacy compatibility / Reference.
    """
    
    @staticmethod
    def create_engine(engine_type: str, config: Dict[str, Any]):
        engine_type = engine_type.upper()
        
        logger.info(f"🏭 EngineFactory: Requesting engine type '{engine_type}'")
        
        if engine_type == 'XAU_PRO':
            return InstitutionalGoldEngine(config)
            
        elif engine_type == 'GOLDEN':
            return GoldenEngine(config)
            
        # Map Legacy/Deleted engines to the new Gold Standard (or Golden)
        elif engine_type in ['SILVER', 'BRONZE', 'PLATINUM', 'ADAPTIVE']:
             logger.warning(f"⚠️ Legacy engine '{engine_type}' requested. Mapping to XAU_PRO.")
             return InstitutionalGoldEngine(config)
            
        else:
            logger.warning(f"Unknown engine type '{engine_type}', defaulting to XAU_PRO")
            return InstitutionalGoldEngine(config)
