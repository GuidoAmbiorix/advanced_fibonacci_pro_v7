from typing import Dict, Any, Optional
from loguru import logger

# Import Engines
from app.engines.golden.core import GoldenEngine
from app.engines.xau_pro.core import InstitutionalProEngine

class EngineFactory:
    """
    Factory to instantiate the Trading Engine.
    
    Pivot Update:
    - INSTITUTIONAL / XAU_PRO: The new Institutional Pro Engine (Multi-Asset).
    - GOLDEN: Kept for legacy compatibility / Reference.
    """
    
    @staticmethod
    def create_engine(engine_type: str, config: Dict[str, Any]):
        engine_type = engine_type.upper()
        
        logger.info(f"🏭 EngineFactory: Requesting engine type '{engine_type}'")
        
        if engine_type in ['INSTITUTIONAL', 'XAU_PRO', 'PRO']:
            return InstitutionalProEngine(config)
            
        elif engine_type == 'GOLDEN':
            return GoldenEngine(config)
            
        # Map Legacy/Deleted engines to the new Gold Standard (or Golden)
        elif engine_type in ['SILVER', 'BRONZE', 'PLATINUM', 'ADAPTIVE']:
             logger.warning(f"R Legacy engine '{engine_type}' requested. Mapping to INSTITUTIONAL PRO.")
             return InstitutionalProEngine(config)
             
        else:
            logger.warning(f"Unknown engine type '{engine_type}', defaulting to INSTITUTIONAL PRO")
            return InstitutionalProEngine(config)
