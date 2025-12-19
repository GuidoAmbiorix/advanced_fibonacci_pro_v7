from typing import Dict, Any
from app.core.strategies.base import BaseStrategy
from app.core.adaptive_multi_strategy_engine import AdaptiveMultiStrategyEngine
from app.core.strategies.sq_3_29_162 import SQStrategy_3_29_162

class StrategyFactory:
    """
    Factory class to instantiate the appropriate trading strategy engine.
    """
    
    @staticmethod
    def create_strategy(config: Dict[str, Any]) -> Any:
        """
        Create and return a strategy instance.
        
        Args:
            config: Configuration dictionary.
            
        Returns:
            An instance of a strategy engine (BaseStrategy compliant usually).
        """
        # Logic to decide which strategy to return
        # Currently, AdaptiveMultiStrategyEngine is the main orchestrator which can internally
        # use other strategies (Composition).
        # However, if we wanted to run *solely* the SQ strategy without the overhead of the 
        # Adaptive Engine (which includes Grid, Risk Manager logic etc), we could return it directly.
        # But TradingBot expects an interface that matches AdaptiveMultiStrategyEngine (analyze returning dict with signals etc).
        
        # For now, we return AdaptiveMultiStrategyEngine as it supports the SQ strategy via composition.
        # Future expansion:
        # if config.get('strategy_mode') == 'SQ_ONLY':
        #     return SQStrategy_3_29_162(config)
        
        return AdaptiveMultiStrategyEngine(config)
