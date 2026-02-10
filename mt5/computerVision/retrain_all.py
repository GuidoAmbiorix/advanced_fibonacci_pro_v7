import sys
from pathlib import Path

# Add project root to path
root_dir = Path(__file__).parent
sys.path.append(str(root_dir))
sys.path.append(str(root_dir / "mt5" / "computerVision"))

from mt5.computerVision.src.database.db_manager import DatabaseManager
from mt5.computerVision.src.training.ensemble_trainer import HybridEnsembleTrainer

def retrain_active_symbols():
    db = DatabaseManager()
    trainer = HybridEnsembleTrainer(db=db)
    
    # 1. Get active portfolio
    portfolio_id = db.get_config('active_portfolio_id')
    if not portfolio_id:
        print("No active portfolio set in database.")
        # Check if there are any portfolios at all
        portfolios = db.get_portfolios()
        if not portfolios:
            print("Creating default portfolio...")
            portfolio_id = db.create_portfolio("Default Portfolio", 1000.0)
            db.set_config('active_portfolio_id', str(portfolio_id))
        else:
            portfolio_id = portfolios[0]['id']
            db.set_config('active_portfolio_id', str(portfolio_id))
            print(f"Using portfolio ID: {portfolio_id}")

    # 2. Add default allocations if none exist (EURUSD, USDJPY)
    allocations = db.get_allocations(int(portfolio_id))
    if not allocations:
        print("No allocations found. Adding EURUSD and USDJPY...")
        # Need to create strategies first if none exist
        strategies = db.get_strategies()
        if not strategies:
            strat_id = db.create_strategy("Hybrid Ensemble Standard", "ML_MODEL")
        else:
            strat_id = strategies[0]['id']
            
        db.set_allocation(int(portfolio_id), strat_id, "EURUSD", 0.5)
        db.set_allocation(int(portfolio_id), strat_id, "USDJPY", 0.5)
        allocations = db.get_allocations(int(portfolio_id))

    # 3. Retrain for each allocated symbol
    for alloc in allocations:
        symbol = alloc['symbol']
        timeframe = db.get_config('trading_timeframe') or 'H1'
        print(f"\n--- Retraining {symbol} ({timeframe}) ---")
        
        try:
            ensemble, metrics = trainer.train_ensemble(
                symbol=symbol,
                timeframe=timeframe,
                include_lstm=True,
                include_cnn_lstm=True,
                include_xgboost=True,
                include_rf=True,
                include_mlp=True
            )
            
            model_id = trainer.save_ensemble(symbol, timeframe, metrics)
            
            # Update allocation with new model ID if it was missing or different
            db.set_allocation(int(portfolio_id), alloc['strategy_id'], symbol, alloc['weight'])
            # Since my set_allocation doesn't update model_id directly in that table 
            # (wait, portfolio_allocations usually joins with strategies which has model_id)
            # Actually, let's update the strategy's model_id
            cursor = db.get_connection().cursor()
            cursor.execute("UPDATE strategies SET model_id = ? WHERE id = ?", (model_id, alloc['strategy_id']))
            db.get_connection().commit()
            
            print(f"Successfully retrained and updated {symbol} with Model ID {model_id}")
            
        except Exception as e:
            print(f"Error retraining {symbol}: {e}")

if __name__ == "__main__":
    retrain_active_symbols()
    print("\nAll retrained. You can now start the Auto-Trader.")
