
from app.services.portfolio_manager import PortfolioManager

def test_correlation_blocking():
    # Initialize PM with 2 max positions per symbol, but default correlation threshold (0.7)
    pm = PortfolioManager(max_portfolio_risk=10.0, max_positions_per_symbol=2, correlation_threshold=0.7)
    
    # Add first position on XAUUSD
    print("Adding first XAUUSD position...")
    pm.add_position("XAUUSD", 1.0, 1.0)
    
    # Try to add second position on XAUUSD (should be allowed by max_positions=2, but blocked by correlation)
    print("Attempting to add second XAUUSD position...")
    can_open, reason = pm.can_open_position("XAUUSD", 1.0, 10000)
    
    if can_open:
        print("✅ SUCCESS: Second position ALLOWED")
    else:
        print(f"❌ BLOCKED: {reason}")
        if "High correlation" in reason and "1.00" in reason:
            print("   -> CONFIRMED: Blocked due to self-correlation")

if __name__ == "__main__":
    test_correlation_blocking()
