import pandas as pd
import numpy as np

def test_df_creation():
    # Simulate MT5 rates structure (numpy structured array)
    dtype = [('time', '<i8'), ('open', '<f8'), ('high', '<f8'), ('low', '<f8'), ('close', '<f8'), ('tick_volume', '<u8'), ('spread', '<i4'), ('real_volume', '<u8')]
    rates = np.array([
        (1672531200, 1.0700, 1.0750, 1.0650, 1.0720, 100, 10, 0),
        (1672534800, 1.0720, 1.0780, 1.0710, 1.0750, 150, 12, 0)
    ], dtype=dtype)
    
    print("Original Rates Array:")
    print(rates)
    print("Dtype names:", rates.dtype.names)
    
    # Simulate chunking: list of records
    all_rates = []
    all_rates.extend(rates)
    
    print("\nall_rates (list) first element:")
    print(all_rates[0])
    print("Type of element:", type(all_rates[0]))
    
    # Create DataFrame
    print("\nCreating DataFrame from list...")
    df = pd.DataFrame(all_rates)
    
    print("\nDataFrame Columns:")
    print(df.columns)
    
    print("\nDataFrame Head:")
    print(df.head())
    
    # Check for 'time' column
    if 'time' in df.columns:
        print("\n✅ 'time' column found.")
    else:
        print("\n❌ 'time' column NOT found.")
        # Try to fix
        print("Attempting fix with explicit columns...")
        df_fixed = pd.DataFrame(all_rates, columns=rates.dtype.names)
        print("Fixed DataFrame Columns:", df_fixed.columns)

if __name__ == "__main__":
    test_df_creation()
