from datetime import datetime
from typing import Dict, List, Optional
import pandas as pd
from ..database.db_manager import DatabaseManager

class PortfolioManager:
    """
    Manages trading portfolios, strategies, and capital allocation.
    """
    
    def __init__(self, db_manager: DatabaseManager):
        self.db = db_manager
        
    def create_portfolio(self, name: str, initial_capital: float, description: str = None) -> int:
        """Create a new portfolio."""
        return self.db.create_portfolio(name, initial_capital, description)
        
    def get_portfolio_summary(self, portfolio_id: int, total_account_balance: float = 0.0) -> Dict:
        """Get comprehensive portfolio summary."""
        portfolio = self.db.get_portfolio(portfolio_id)
        if not portfolio:
            return None
            
        allocations = self.db.get_allocations(portfolio_id)
        performance = self.db.get_portfolio_performance(portfolio_id, days=30)
        
        # If total balance is provided, update current capital display
        # In a real system, we might have multiple portfolios splitting the balance.
        # For now, we'll assume the portfolio tracks its own P&L, but we can also
        # view it as: Current Capital = Initial Capital + Realized P&L
        # OR if we want to sync with MT5: 
        # Portfolio Equity = (Portfolio Initial / Total Initial) * Total Equity
        
        # Let's trust the database's current_capital for P&L tracking, 
        # but we could return the account balance context too.
        
        return {
            'info': portfolio,
            'allocations': allocations,
            'performance': performance,
            'total_allocated_weight': sum(a['weight'] for a in allocations),
            'account_balance': total_account_balance
        }
        
    def add_strategy_to_portfolio(self, portfolio_id: int, strategy_name: str, 
                                model_id: int, symbol: str, weight: float, 
                                config: Dict = None) -> bool:
        """
        Add a strategy to a portfolio and allocate capital.
        
        Args:
            portfolio_id: Target portfolio ID
            strategy_name: Name for the strategy instance
            model_id: ID of the ML model to use
            symbol: Trading symbol
            weight: Allocation weight (0.0 - 1.0)
            config: Optional strategy configuration
            
        Returns:
            bool: Success status
        """
        # Check if total weight would exceed 1.0
        current_allocations = self.db.get_allocations(portfolio_id)
        current_total = sum(a['weight'] for a in current_allocations)
        
        if current_total + weight > 1.0:
            raise ValueError(f"allocation exceeds 100%. Current: {current_total:.1%}, Requested: {weight:.1%}")
            
        # Create strategy
        strategy_id = self.db.create_strategy(
            name=strategy_name,
            type='ML_MODEL' if model_id else 'RULE_BASED',
            model_id=model_id,
            config=config
        )
        
        # Set allocation
        self.db.set_allocation(portfolio_id, strategy_id, symbol, weight)
        return True
        
    def calculate_position_size(self, portfolio_id: int, symbol: str, strategy_id: int) -> float:
        """
        Calculate position size (lots) based on portfolio allocation and risk settings.
        
        Args:
            portfolio_id: Portfolio ID
            symbol: Trading symbol
            strategy_id: Strategy ID
            
        Returns:
            float: Position size in lots
        """
        portfolio = self.db.get_portfolio(portfolio_id)
        allocations = self.db.get_allocations(portfolio_id)
        
        # Find specific allocation
        allocation = next((a for a in allocations 
                         if a['strategy_id'] == strategy_id and a['symbol'] == symbol), None)
                         
        if not allocation or not portfolio:
            return 0.0
            
        # Calculate allocated capital
        allocated_capital = portfolio['current_capital'] * allocation['weight']
        
        # Get risk per trade from config (default 1% of allocated capital)
        risk_per_trade_pct = 0.01 
        risk_amount = allocated_capital * risk_per_trade_pct
        
        # Estimate lot size (simplified: 1 lot = $100k roughly, needs bridge for exact value)
        # This is a placeholder. In real implementation, we'd query the bridge for tick value.
        # Assuming standard FOREX lot: 1 pip = $10, 50 pip SL = $500 risk per lot
        stop_loss_pips = 50
        risk_per_lot = stop_loss_pips * 10 
        
        lot_size = risk_amount / risk_per_lot
        return round(max(0.01, lot_size), 2)
        
    def update_equity(self, portfolio_id: int, current_equity: float):
        """Update portfolio equity and calculate drawdown."""
        portfolio = self.db.get_portfolio(portfolio_id)
        if not portfolio:
            return
            
        # Update current capital
        with self.db.get_connection() as conn:
            conn.execute("UPDATE portfolios SET current_capital = ? WHERE id = ?", 
                       (current_equity, portfolio_id))
            conn.commit()
            
        # Calculate daily performance metrics
        initial = portfolio['initial_capital']
        daily_pnl = current_equity - initial # Simplified, ideally needs daily snapshot comparison
        
        # Calculate drawdown (simplified)
        # A real implementation would track high water mark
        peak_equity = max(current_equity, initial) 
        drawdown = (peak_equity - current_equity) / peak_equity if peak_equity > 0 else 0
        
        self.db.update_portfolio_performance(portfolio_id, current_equity, daily_pnl, drawdown)
