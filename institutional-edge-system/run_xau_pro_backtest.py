
import sys
from pathlib import Path
from datetime import datetime

# Add app to path
sys.path.insert(0, str(Path(__file__).parent))

from app.backtesting.engine import BacktestEngine
from app.backtesting.models import BacktestConfig
from loguru import logger

def main():
    logger.add("logs/backtest_xau_pro.log", rotation="1 day", level="INFO")
    
    logger.info("="*70)
    logger.info("INSTITUTIONAL EDGE - XAU_PRO ENGINE TEST")
    logger.info("="*70)

    # Configure backtest for XAU_PRO
    config = BacktestConfig(
        initial_balance=10000.0,
        symbol="XAUUSD", 
        timeframe="M30", # Using M30 to ensure data availability (avoiding M5 1-year limit)
        start_date=datetime(2024, 1, 1),
        end_date=datetime(2024, 4, 1), # 3 months
        
        # KEY CHANGE: Specify Engine
        engine_type="XAU_PRO",
        
        # Risk
        risk_percent=1.0, 
        
        # Strategy Params (SMC)
        enable_order_blocks=True,
        ob_lookback=20,
        enable_liquidity_sweep=True,
        sweep_lookback=10,
        enable_fvg=True,
        fvg_min_size_atr=0.5,
        session_mode="ny_kz", # NY Killzone
        
        # Execution
        slippage_pips=1.0,
        commission_per_lot=7.0
    )

    engine = BacktestEngine(config)
    
    logger.info(f"Running backtest with engine: {config.engine_type}")
    try:
        results = engine.run()
        
        # Summary
        m = results.metrics
        print(f"\nTrades: {m.total_trades} | WR: {m.win_rate:.1f}% | PF: {m.profit_factor:.2f} | Net: ${m.net_profit:.2f}")
        
    except Exception as e:
        logger.error(f"Backtest failed: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()
