import lab_core
import MetaTrader5 as mt5
import pandas as pd
import os

def run_miner(symbol="XAUUSD", timeframe_str="H1", bars=10000):
    print(f"⛏️ Starting Data Miner for {symbol} ({timeframe_str})...")
    
    # Map timeframe string to MT5 constant
    tf_map = {
        "M1": mt5.TIMEFRAME_M1, "M5": mt5.TIMEFRAME_M5, "M15": mt5.TIMEFRAME_M15,
        "H1": mt5.TIMEFRAME_H1, "H4": mt5.TIMEFRAME_H4, "D1": mt5.TIMEFRAME_D1
    }
    tf = tf_map.get(timeframe_str, mt5.TIMEFRAME_H1)
    
    if not lab_core.connect_mt5():
        return
    
    df = lab_core.fetch_data(symbol, tf, bars)
    lab_core.shutdown_mt5()
    
    if df is not None:
        print(f"📉 Downloaded {len(df)} bars. Engineering features...")
        df_processed = lab_core.prepare_features(df)
        
        # Save to CSV
        save_path = os.path.join(os.path.dirname(__file__), "data", f"{symbol}_{timeframe_str}_training.csv")
        df_processed.to_csv(save_path, index=False)
        
        print(f"✅ Data saved to: {save_path}")
        print(f"📊 Features available: {list(df_processed.columns)}")
        print(f"🎯 Target distribution:\n{df_processed['Target_Class'].value_counts()}")
        
    else:
        print("❌ Data download failed.")

if __name__ == "__main__":
    run_miner("XAUUSD", "H1", 20000)
