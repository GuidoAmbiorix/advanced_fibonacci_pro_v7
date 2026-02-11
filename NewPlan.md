Optuna Optimization Upgrade Plan
Goal
Transform the current basic "Optuna Optimization" placeholder in the dashboard into a full-featured, interactive hyperparameter optimization suite. This will allow the user to maximize model performance using advanced Optuna features, visualizations, and control mechanisms directly from the UI.

User Review Required
IMPORTANT

Database Requirement: To support advanced features like pausing/resuming studies and the Optuna Dashboard, we will use a local SQLite database file (optuna_studies.db) in the models directory. This is standard practice for Optuna.

NOTE

Performance: Running optimization inside the Streamlit app can block the UI if not handled carefully. We will implement the optimization loop to be responsive or run in short bursts/threads if possible, but for deep learning models, it might still freeze the UI briefly between updates.

Proposed Changes
1. Prediction Engine Core (The Foundation) [PRIORITY 1]
Goal: Fix the underlying signal quality before optimizing hyperparameters.

Triple Barrier Labeling:
Concept: Label 1 only if price hits Take Profit (2x Volatility) before Stop Loss (1x Volatility) within N bars.
Implementation: Pure NumPy for speed.
Impact: maximizing this metric translates directly to Profit Factor/Sharpe.
Feature Selection Strategy:
Avoid: Optimizing 150+ features directly with Optuna (Combinatorial explosion).
Adopt:
Pre-screen features using Feature Importance (Random Forest / SHAP).
Select top 30-40 features.
Then let Optuna fine-tune or select subsets from this smaller pool.
Fast Vectorized Backtester:
Must be 100% Vectorized (Pandas/NumPy) to run thousands of trials in minutes.
Calculates: Net Profit, Profit Factor, Max Drawdown, Sharpe Ratio.
Walk-Forward Validation:
Prevent overfitting by training on Period A, optimizing on Period B, and testing on Period C (rolling window).
2. Enhanced Optuna Backend (src/training/optuna_service.py) [PRIORITY 2]
Architecture:
Async Execution: Optimization loops MUST run in a separate process/thread. The Dashboard will poll the database for updates (no blocking calls).
Persistence: PostgreSQL Only. Use DATABASE_URL from environment with optuna.storages.RDBStorage.
NO SQLite: Ensure no local .db files are created to maintain stateless container compatibility.
Unified Optimization:
Support MLP, LSTM, CNN-LSTM.
Objective Functions: Maximize Profit Factor or Sharpe Ratio (using the Vectorized Backtester), not just Accuracy.
Advanced Configuration:
Samplers: Add UI options for TPESampler (default), RandomSampler, and CmaEsSampler.
Pruners: HyperbandPruner (better for deep learning) and MedianPruner.
Callback System: Implement OptunaStreamlitCallback to update Streamlit progress bars and charts in real-time during the loop.
2. Streamlit Dashboard Integration (
dashboard/app.py
)
Enhance the existing "2️⃣ Optuna Optimization" tab.

Configuration Panel:
Study Management: New "Resume Study" option to load past experiments.
Model Select: Dropdown to choose between MLP (Standard), LSTM, or CNN-LSTM for optimization.
Optimization Target: Dropdown for "Accuracy", "Net Profit", "Profit Factor", "Sharpe Ratio", "Sortino Ratio", "Max Drawdown".
Storage: Show list of past studies with their best scores.
Real-time Visualization:
Replace the static spinner with dynamic st.plot_optimization_history and st.plot_intermediate_values updating live.
Use optuna_dashboard helper features if possible, or standard optuna.visualization with Plotly.
Analysis Section (Post-Optimization):
Parallel Coordinate Plot: To see high-dimensional interactions.
Param Importance: plot_param_importances to guide user on what to tune.
Contour Plots: For deep dives into specific parameter pairs.
Model Deployment ("Promote to Registry"):
Crucial: Must save the Full Reproducibility Context:
Model Weights & Architecture
Hyperparameters
Feature List (Top N used)
Label Config (Triple Barrier parameters)
Scaler object
Threshold (Decision boundary)
Backtest Metrics
Time Range used for training
3. Refactoring Roadmap
Extract: Move MLP optimization logic from 
app.py
 (lines 946-968) to 
src/training/optimize_model.py
 or new service.
Integrate: Modify 
app.py
 to instantiate OptunaService.
UI Upgrade: Add the visualization tabs and "Resume" functionality.