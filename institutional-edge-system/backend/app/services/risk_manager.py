from app.models.database import BotConfig, RiskProfile
from app.services.market_regime import MarketRegimeDetector
from typing import Optional

class AdaptiveRiskManager:
    """
    Dynamic Risk Management Engine.
    Adjusts risk based on:
    - Market Volatility (ATR)
    - Account Drawdown
    - Consecutive Losses
    - Prop Firm Rules
    """

    def __init__(self, bot_config: BotConfig, account_info: dict):
        self.config = bot_config
        self.account = account_info
        self.base_risk_percent = bot_config.risk_percent

    def calculate_risk_percent(self, market_regime: dict, consecutive_losses: int = 0) -> float:
        """
        Calculate the actual risk percentage for the next trade.
        """
        risk = self.base_risk_percent

        # 1. Volatility Adjustment
        if market_regime['volatility'] == 'HIGH':
            risk *= 0.5  # Halve risk in high volatility
        elif market_regime['volatility'] == 'EXTREME':
            risk *= 0.25 # Quarter risk in extreme volatility
        
        # 2. Drawdown Adjustment
        # Calculate current drawdown
        balance = self.account.get('balance', 0)
        equity = self.account.get('equity', 0)
        
        # Simple DD calculation based on equity vs balance (or high water mark if we tracked it)
        # Assuming balance is the reference for now.
        if balance > 0:
            current_dd_percent = ((balance - equity) / balance) * 100
            
            # If in significant DD, reduce risk
            if current_dd_percent > 5.0:
                risk *= 0.5
        
        # 3. Streak Adjustment (Martingale/Anti-Martingale logic could go here)
        # For safety, reduce risk after 2 consecutive losses
        if consecutive_losses >= 2:
            risk *= 0.5

        # 4. Hard Limits
        risk = min(risk, self.config.max_risk_percent or 5.0)
        risk = max(risk, 0.1) # Minimum 0.1% risk

        return round(risk, 2)

    def calculate_lot_size(self, risk_percent: float, stop_loss_price: float, entry_price: float, symbol_type: str = "forex") -> float:
        """
        Calculate position size based on risk amount and SL distance.
        """
        balance = self.account.get('balance', 0)
        risk_amount = balance * (risk_percent / 100)
        
        if entry_price == stop_loss_price:
            return 0.0
            
        sl_distance = abs(entry_price - stop_loss_price)
        
        # Standard Lot Value calculation
        # Forex: 1 Lot = 100,000 units. Pip value depends on pair.
        # This is a simplified calculation. Ideally, use MT5 symbol info.
        
        # Approximation for Forex (USD quote currency)
        if symbol_type == "forex":
            # Assuming standard lot size 100000
            # Risk = Lots * 100000 * SL_Distance
            # Lots = Risk / (100000 * SL_Distance)
            lots = risk_amount / (100000 * sl_distance)
        
        elif symbol_type == "crypto":
            # Crypto: 1 Lot = 1 Coin usually
            # Risk = Lots * SL_Distance
            lots = risk_amount / sl_distance
            
        elif symbol_type == "indices":
             # Indices: Contract size varies (e.g. 10, 20, 50)
             # Assuming 1 for simplicity, needs symbol info
             lots = risk_amount / sl_distance

        else:
            lots = 0.01

        return round(lots, 2)

    def check_prop_firm_rules(self, daily_loss: float, total_loss: float) -> dict:
        """
        Check if trading should be halted due to Prop Firm rules.
        """
        balance = self.account.get('balance', 0)
        if balance == 0:
             return {"allowed": False, "reason": "Zero Balance"}

        # Daily Loss Limit
        daily_loss_percent = (daily_loss / balance) * 100
        if daily_loss_percent >= self.config.daily_loss_limit_percent:
            return {
                "allowed": False, 
                "reason": f"Daily Loss Limit Reached ({daily_loss_percent:.2f}% >= {self.config.daily_loss_limit_percent}%)"
            }
            
        # Total Drawdown Limit (e.g. 10%)
        # Assuming total_loss is passed correctly
        total_dd_percent = (total_loss / balance) * 100
        if total_dd_percent >= 10.0: # Hardcoded 10% for now, should be in config
             return {
                "allowed": False, 
                "reason": f"Max Total Drawdown Reached ({total_dd_percent:.2f}%)"
            }
            
        return {"allowed": True, "reason": "OK"}
