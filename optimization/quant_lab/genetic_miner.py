import pandas as pd
import numpy as np
import os
try:
    from gplearn.genetic import SymbolicRegressor
    from gplearn.functions import make_function
except ImportError:
    print("❌ gplearn not installed. Please run: pip install gplearn")
    exit()

import matplotlib.pyplot as plt

def run_genetic_evolution(data_file):
    print(f"🧬 Starting Genetic Evolution on {data_file}...")
    
    if not os.path.exists(data_file):
        print(f"❌ File not found: {data_file}")
        return

    df = pd.read_csv(data_file)
    
    # 1. Define Features (X) and Target (y)
    # Exclude non-feature columns
    exclude_cols = ['time', 'open', 'high', 'low', 'close', 'tick_volume', 'spread', 'real_volume', 'Target_Return', 'Target_Class']
    feature_cols = [c for c in df.columns if c not in exclude_cols]
    
    X = df[feature_cols]
    y = df['Target_Return'] * 100 # Predict Return in % (Scaling helps regressor)
    
    # Split Train/Test (Last 20% for validation)
    split_idx = int(len(df) * 0.8)
    X_train, X_test = X[:split_idx], X[split_idx:]
    y_train, y_test = y[:split_idx], y[split_idx:]
    
    print(f"Features: {feature_cols}")
    print(f"Training on {len(X_train)} samples...")

    # 2. Configure Genetic Programming
    # We want a formula that predicts returns.
    est = SymbolicRegressor(
        population_size=5000,
        generations=20,
        stopping_criteria=0.01,
        p_crossover=0.7,
        p_subtree_mutation=0.1,
        p_hoist_mutation=0.05,
        p_point_mutation=0.1,
        max_samples=0.9,
        verbose=1,
        parsimony_coefficient=0.001, # Penalty for complexity
        random_state=42,
        function_set=['add', 'sub', 'mul', 'div', 'abs', 'neg', 'max', 'min']
    )
    
    # 3. Evolve!
    est.fit(X_train, y_train)
    
    # 4. Results
    print("\n🏆 Evolution Complete!")
    print(f"Best Program (R2 Score: {est.score(X_test, y_test):.4f}):")
    print(est._program)
    
    return est._program

if __name__ == "__main__":
    # Auto-find latest data
    data_dir = os.path.join(os.path.dirname(__file__), "data")
    files = [f for f in os.listdir(data_dir) if f.endswith("_training.csv")]
    
    if files:
        target_file = os.path.join(data_dir, files[0]) # Pick first
        run_genetic_evolution(target_file)
    else:
        print("❌ No training data found. Run data_miner.py first.")
