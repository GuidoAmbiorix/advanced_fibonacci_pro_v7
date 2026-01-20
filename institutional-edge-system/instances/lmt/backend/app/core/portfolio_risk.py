"""
Portfolio Risk Manager

Calculates combined risk metrics across all trading slots.
Enforces portfolio-level risk limits.
"""

from typing import Dict, List, Optional
from loguru import logger
from datetime import datetime


class PortfolioRiskManager:
    """Manage risk across the entire portfolio of trading slots"""
    
    def __init__(
        self, 
        max_portfolio_risk: float = 4.0,  # Max 4% total risk across all slots
        max_correlation_risk: float = 0.7,  # Warn if correlation > 0.7
        max_positions_per_symbol: int = 2
    ):
        self.max_portfolio_risk = max_portfolio_risk
        self.max_correlation_risk = max_correlation_risk
        self.max_positions_per_symbol = max_positions_per_symbol
    
    def get_portfolio_summary(
        self, 
        mt5_connector,
        slots_config: List[Dict]
    ) -> Dict:
        """
        Get comprehensive portfolio risk summary.
        
        Returns:
            Dict with equity, drawdown, positions, and risk metrics
        """
        # Get account info
        account = mt5_connector.get_account_info() or {}
        balance = account.get('balance', 0)
        equity = account.get('equity', 0)
        
        # Get all open positions
        positions = mt5_connector.get_open_positions() or []
        
        # Calculate metrics
        total_profit = sum(p.get('profit', 0) for p in positions)
        total_volume = sum(p.get('volume', 0) for p in positions)
        
        # Group positions by symbol
        positions_by_symbol = {}
        for pos in positions:
            sym = pos.get('symbol', 'Unknown')
            if sym not in positions_by_symbol:
                positions_by_symbol[sym] = []
            positions_by_symbol[sym].append(pos)
        
        # Calculate risk per slot
        slot_risks = []
        for slot in slots_config:
            symbol = slot.get('symbol', '')
            risk_pct = slot.get('risk_percent', 1.0)
            enabled = slot.get('enabled', False)
            
            # Check if position open for this symbol
            has_position = symbol in positions_by_symbol
            
            slot_risks.append({
                'symbol': symbol,
                'risk_percent': risk_pct,
                'enabled': enabled,
                'has_open_position': has_position,
                'position_count': len(positions_by_symbol.get(symbol, []))
            })
        
        # Calculate total active risk
        total_active_risk = sum(
            s['risk_percent'] for s in slot_risks 
            if s['enabled'] and s['has_open_position']
        )
        
        # Calculate potential total risk (if all slots trade)
        total_potential_risk = sum(
            s['risk_percent'] for s in slot_risks if s['enabled']
        )
        
        # Drawdown calculations
        drawdown = balance - equity if balance > 0 else 0
        drawdown_percent = (drawdown / balance * 100) if balance > 0 else 0
        
        return {
            'account': {
                'balance': round(balance, 2),
                'equity': round(equity, 2),
                'profit': round(total_profit, 2),
                'margin_level': account.get('margin_level', 0)
            },
            'positions': {
                'total': len(positions),
                'total_volume': round(total_volume, 2),
                'by_symbol': {k: len(v) for k, v in positions_by_symbol.items()}
            },
            'risk': {
                'active_risk_percent': round(total_active_risk, 2),
                'potential_risk_percent': round(total_potential_risk, 2),
                'max_portfolio_risk': self.max_portfolio_risk,
                'risk_utilization': round((total_active_risk / self.max_portfolio_risk * 100) if self.max_portfolio_risk > 0 else 0, 1)
            },
            'drawdown': {
                'amount': round(drawdown, 2),
                'percent': round(drawdown_percent, 2)
            },
            'slots': slot_risks,
            'timestamp': datetime.utcnow().isoformat()
        }
    
    def can_open_trade(
        self, 
        slot_config: Dict,
        current_positions: List[Dict],
        current_total_risk: float
    ) -> tuple:
        """
        Check if a new trade can be opened based on portfolio limits.
        
        Returns:
            (bool, str) - (can_trade, reason)
        """
        symbol = slot_config.get('symbol', '')
        slot_risk = slot_config.get('risk_percent', 1.0)
        
        # Check portfolio risk limit
        if current_total_risk + slot_risk > self.max_portfolio_risk:
            return False, f"Portfolio risk limit ({self.max_portfolio_risk}%) would be exceeded"
        
        # Check positions per symbol
        symbol_positions = [p for p in current_positions if p.get('symbol') == symbol]
        if len(symbol_positions) >= self.max_positions_per_symbol:
            return False, f"Max positions ({self.max_positions_per_symbol}) reached for {symbol}"
        
        return True, "OK"
    
    def calculate_adjusted_risk(
        self,
        base_risk: float,
        num_active_slots: int,
        correlation_factor: float = 1.0
    ) -> float:
        """
        Calculate adjusted risk per slot based on portfolio context.
        
        Args:
            base_risk: The slot's configured risk %
            num_active_slots: Number of slots currently trading
            correlation_factor: 1.0 = uncorrelated, higher = reduce risk
            
        Returns:
            Adjusted risk percentage
        """
        if num_active_slots <= 1:
            return base_risk
        
        # Reduce risk when multiple correlated slots are active
        reduction_factor = 1.0 / (1 + (num_active_slots - 1) * 0.2 * correlation_factor)
        
        adjusted_risk = base_risk * reduction_factor
        
        return round(adjusted_risk, 2)
