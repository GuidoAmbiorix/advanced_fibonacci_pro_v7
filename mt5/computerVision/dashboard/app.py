"""
Computer Vision Trading Agent - Streamlit Dashboard

Main dashboard for monitoring ML predictions, trading activity, and system status.
"""

import streamlit as st
import sys
from pathlib import Path
import pandas as pd
import plotly.graph_objects as go
from datetime import datetime, timedelta

# Add parent directory to path
sys.path.append(str(Path(__file__).parent.parent))
from src.database import DatabaseManager

# Page config
st.set_page_config(
    page_title="CV Trading Agent",
    page_icon="🤖",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Initialize database
@st.cache_resource
def get_db():
    return DatabaseManager()

db = get_db()

# Sidebar
st.sidebar.title("🤖 CV Trading Agent")
st.sidebar.markdown("---")

page = st.sidebar.radio(
    "Navigation",
    ["Dashboard", "Live Predictions", "Trading Control", "Live Trades", "Training", "System Logs"]
)

st.sidebar.markdown("---")
st.sidebar.markdown("### System Status")

# Get system status (not cached - check every time)
import os
import requests

bridge_url = os.getenv('BRIDGE_URL', 'http://host.docker.internal:5000')

# Debug: Show what URL we're using
st.sidebar.caption(f"Bridge: {bridge_url}")

try:
    response = requests.get(f"{bridge_url}/status", timeout=5)
    st.sidebar.caption(f"HTTP {response.status_code}")
    if response.status_code == 200:
        status_data = response.json()
        if status_data.get('connected'):
            st.sidebar.success("✅ MT5 Connected")
            if status_data.get('account_info'):
                acc = status_data['account_info']
                st.sidebar.metric("Balance", f"${acc['balance']:.2f}")
                st.sidebar.metric("Equity", f"${acc['equity']:.2f}")
        else:
            st.sidebar.error("❌ MT5 Disconnected")
    else:
        st.sidebar.warning(f"⚠️ Bridge Offline (HTTP {response.status_code})")
except requests.exceptions.Timeout:
    st.sidebar.error("⚠️ Bridge Timeout")
except requests.exceptions.ConnectionError as e:
    st.sidebar.error("⚠️ Connection Error")
    st.sidebar.caption(str(e)[:100])
except Exception as e:
    st.sidebar.error("⚠️ Bridge Error")
    st.sidebar.caption(f"{type(e).__name__}: {str(e)[:100]}")

# Auto-trading status
auto_trading_enabled = db.get_config('auto_trading_enabled') == 'true'
if auto_trading_enabled:
    st.sidebar.success("🟢 Auto-Trading: ON")
else:
    st.sidebar.info("⚪ Auto-Trading: OFF")

# ==================== Dashboard Page ====================
if page == "Dashboard":
    st.title("📊 Dashboard")
    
    col1, col2, col3, col4 = st.columns(4)
    
    # Metrics
    with col1:
        open_positions = db.get_open_positions()
        st.metric("Open Positions", len(open_positions))
    
    with col2:
        daily_pnl = db.get_daily_pnl()
        st.metric("Today's P&L", f"${daily_pnl:.2f}", 
                 delta=f"{daily_pnl:.2f}", delta_color="normal")
    
    with col3:
        recent_trades = db.get_trades(limit=10)
        st.metric("Trades Today", len([t for t in recent_trades if t['close_time'][:10] == str(datetime.now().date())]))
    
    with col4:
        active_model = db.get_active_model()
        if active_model:
            st.metric("Active Model", active_model['name'])
        else:
            st.metric("Active Model", "None")
    
    st.markdown("---")
    
    # Recent predictions
    st.subheader("Recent Predictions")
    predictions_query = """
        SELECT p.*, m.name as model_name
        FROM predictions p
        LEFT JOIN models m ON p.model_id = m.id
        ORDER BY p.timestamp DESC
        LIMIT 10
    """
    with db.get_connection() as conn:
        predictions_df = pd.read_sql_query(predictions_query, conn)
    
    if not predictions_df.empty:
        st.dataframe(predictions_df[['timestamp', 'symbol', 'prediction_direction', 'confidence', 'model_name']], 
                    use_container_width=True)
    else:
        st.info("No predictions yet")

# ==================== Live Predictions Page ====================
elif page == "Live Predictions":
    st.title("🔮 Live Predictions")
    
    col1, col2 = st.columns([3, 1])
    
    with col1:
        symbol = st.selectbox("Symbol", ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "AUDUSD", "USDCAD", "USDCHF", "NZDUSD", "EURJPY"])
    
    with col2:
        st.write("")  # Spacing
        st.write("")  # Spacing
        if st.button("🎯 Generate Prediction", type="primary"):
            with st.spinner(f"Generating prediction for {symbol}..."):
                try:
                    # Load active model
                    active_model = db.get_active_model()
                    if not active_model:
                        st.error("No active model! Train a model first.")
                    else:
                        import pickle
                        from pathlib import Path
                        from datetime import datetime, timedelta
                        from src.features import prepare_training_data, create_talib_features, create_basic_features
                        
                        # Load model
                        model_path = Path(active_model['file_path'])
                        with open(model_path, 'rb') as f:
                            model_data = pickle.load(f)
                        
                        model = model_data['model']
                        scaler = model_data['scaler']
                        features = model_data['features']
                        use_talib = model_data.get('use_talib', False)
                        
                        # Get latest market data (need more for TA-Lib indicators)
                        query = """
                            SELECT * FROM market_data 
                            WHERE symbol = ?
                            ORDER BY timestamp DESC
                            LIMIT 100
                        """
                        with db.get_connection() as conn:
                            df = pd.read_sql_query(query, conn, params=(symbol,))
                        
                        if len(df) < 50:
                            st.error(f"Not enough data for {symbol}. Need at least 50 bars. Fetch data first.")
                        else:
                            # Create features using the same method as training
                            df = df.sort_values('timestamp')
                            
                            if use_talib:
                                df = create_talib_features(df)
                            else:
                                df = create_basic_features(df)
                            
                            df = df.dropna()
                            
                            if len(df) > 0:
                                # Get latest features
                                latest = df.iloc[-1]
                                
                                # Debug: Check which features are available
                                missing_features = [f for f in features if f not in df.columns]
                                if missing_features:
                                    st.error(f"Missing features: {missing_features[:5]}...")
                                    st.info(f"Model expects: {len(features)} features")
                                    st.info(f"DataFrame has: {len(df.columns)} columns")
                                    st.info(f"Model uses TA-Lib: {use_talib}")
                                else:
                                    X = [[latest[f] for f in features]]
                                    X_scaled = scaler.transform(X)
                                    
                                    # Make prediction
                                    prediction = model.predict(X_scaled)[0]
                                    confidence = model.predict_proba(X_scaled)[0].max()
                                    
                                    direction = "BUY" if prediction == 1 else "SELL"
                                    
                                    # Save to database
                                    window_start = pd.to_datetime(latest['timestamp'])
                                    window_end = window_start + timedelta(hours=1)
                                    
                                    db.insert_prediction(
                                        model_id=active_model['id'],
                                        symbol=symbol,
                                        prediction_direction=direction,
                                        confidence=confidence,
                                        window_start=window_start,
                                    window_end=window_end,
                                    prediction_horizon=1
                                )
                                
                                st.success(f"✅ Prediction generated: {direction} with {confidence:.1%} confidence")
                                st.rerun()
                            else:
                                st.error("Not enough data after feature creation")
                                
                except Exception as e:
                    st.error(f"Prediction failed: {str(e)}")
                    import traceback
                    st.code(traceback.format_exc())
    
    st.markdown("---")
    
    # Show recent predictions
    predictions = db.get_latest_prediction(symbol)
    if predictions:
        st.subheader(f"Recent Predictions for {symbol}")
        
        # Convert to DataFrame for display
        df = pd.DataFrame([predictions])
        
        # Display prediction card
        col1, col2, col3 = st.columns(3)
        with col1:
            direction_color = "🟢" if predictions['prediction_direction'] == 'BUY' else "🔴"
            st.metric("Direction", f"{direction_color} {predictions['prediction_direction']}")
        with col2:
            st.metric("Confidence", f"{predictions['confidence']:.1%}")
        with col3:
            st.metric("Time", predictions['created_at'][:16])
        
        # Chart placeholder
        st.info("Prediction chart will be displayed here")
        
        # Simple chart
        fig = go.Figure()
        fig.add_trace(go.Indicator(
            mode = "gauge+number",
            value = predictions['confidence'] * 100,
            title = {'text': "Confidence"},
            gauge = {'axis': {'range': [None, 100]},
                    'bar': {'color': "darkblue"},
                    'steps': [
                        {'range': [0, 50], 'color': "lightgray"},
                        {'range': [50, 75], 'color': "gray"},
                        {'range': [75, 100], 'color': "darkgray"}],
                    'threshold': {'line': {'color': "red", 'width': 4}, 'thickness': 0.75, 'value': 90}}
        ))
        st.plotly_chart(fig)
    else:
        st.info(f"No predictions for {symbol}")

# ==================== Trading Control Page ====================
elif page == "Trading Control":
    st.title("⚙️ Trading Control")
    
    st.warning("⚠️ Use with caution! Auto-trading involves real money.")
    
    # Auto-trading toggle
    current_status = db.get_config('auto_trading_enabled') == 'true'
    
    col1, col2 = st.columns(2)
    
    with col1:
        if st.button("🟢 Enable Auto-Trading" if not current_status else "🔴 Disable Auto-Trading", 
                    type="primary" if not current_status else "secondary"):
            new_status = 'true' if not current_status else 'false'
            db.set_config('auto_trading_enabled', new_status)
            db.log('INFO', 'DASHBOARD', f'Auto-trading {"enabled" if new_status == "true" else "disabled"}')
            st.rerun()
    
    with col2:
        if st.button("🛑 EMERGENCY STOP", type="secondary"):
            db.set_config('auto_trading_enabled', 'false')
            db.log('WARNING', 'DASHBOARD', 'Emergency stop activated')
            st.success("Auto-trading disabled!")
            st.rerun()
    
    st.markdown("---")
    
    # Risk parameters
    st.subheader("Risk Parameters")
    
    config = db.get_all_config()
    
    col1, col2 = st.columns(2)
    
    with col1:
        max_positions = st.number_input("Max Positions", value=int(config.get('max_positions', 3)), min_value=1, max_value=10)
        min_confidence = st.slider("Min Confidence", 0.0, 1.0, float(config.get('min_confidence', 0.70)), 0.01)
    
    with col2:
        max_daily_loss = st.number_input("Max Daily Loss %", value=float(config.get('max_daily_loss_pct', 5.0)), min_value=1.0, max_value=20.0)
        default_lot = st.number_input("Default Lot Size", value=float(config.get('default_lot_size', 0.01)), min_value=0.01, step=0.01)
    
    if st.button("💾 Save Configuration"):
        db.set_config('max_positions', str(max_positions))
        db.set_config('min_confidence', str(min_confidence))
        db.set_config('max_daily_loss_pct', str(max_daily_loss))
        db.set_config('default_lot_size', str(default_lot))
        db.log('INFO', 'DASHBOARD', 'Configuration updated')
        st.success("Configuration saved!")

# ==================== Live Trades Page ====================
elif page == "Live Trades":
    st.title("💹 Live Trades")
    
    tab1, tab2 = st.tabs(["Open Positions", "Trade History"])
    
    with tab1:
        open_positions = db.get_open_positions()
        if open_positions:
            df = pd.DataFrame(open_positions)
            st.dataframe(df[['mt5_ticket', 'symbol', 'position_type', 'volume', 'open_price', 'open_time']], 
                        use_container_width=True)
        else:
            st.info("No open positions")
    
    with tab2:
        trades = db.get_trades(limit=50)
        if trades:
            df = pd.DataFrame(trades)
            st.dataframe(df[['mt5_ticket', 'symbol', 'trade_type', 'volume', 'open_price', 'close_price', 'profit', 'close_time']], 
                        use_container_width=True)
            
            # Performance metrics
            st.subheader("Performance Metrics")
            col1, col2, col3 = st.columns(3)
            
            with col1:
                total_profit = sum(t['profit'] for t in trades)
                st.metric("Total Profit", f"${total_profit:.2f}")
            
            with col2:
                winning_trades = len([t for t in trades if t['profit'] > 0])
                win_rate = (winning_trades / len(trades)) * 100 if trades else 0
                st.metric("Win Rate", f"{win_rate:.1f}%")
            
            with col3:
                st.metric("Total Trades", len(trades))
        else:
            st.info("No trade history")

# ==================== Training Page ====================
elif page == "Training":
    st.title("🎓 ML Training Pipeline")
    
    st.info("📋 **Training Pipeline**: Follow the steps in order for best results")
    
    # Create tabs for each phase
    tab1, tab2, tab3, tab4 = st.tabs([
        "1️⃣ Data & Basic Training",
        "2️⃣ Optuna Optimization", 
        "3️⃣ Advanced Models",
        "4️⃣ Backtesting"
    ])
    
    # ==================== TAB 1: Data & Basic Training ====================
    with tab1:
        st.header("Step 1: Fetch Data & Train Basic Model")
        
        # Symbol and timeframe selection
        col1, col2 = st.columns(2)
        with col1:
            train_symbol = st.selectbox("Symbol", ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "AUDUSD", "USDCAD", "USDCHF", "NZDUSD", "EURJPY"], key="pipeline_symbol")
        with col2:
            train_timeframe = st.selectbox("Timeframe", ["M1", "M5", "M15", "M30", "H1", "H4", "D1"], key="pipeline_timeframe")
        
        st.markdown("---")
        
        # Step 1.1: Fetch Data
        st.subheader("📥 Step 1.1: Fetch Market Data")
        col1, col2 = st.columns([3, 1])
        with col1:
            num_bars = st.slider("Number of bars", 500, 5000, 1000, step=500)
        with col2:
            st.write("")
            st.write("")
            if st.button("📥 Fetch Data", type="secondary", key="fetch_btn"):
                with st.spinner(f"Fetching {train_symbol} {train_timeframe} data..."):
                    try:
                        bridge_url = os.getenv('BRIDGE_URL', 'http://host.docker.internal:5000')
                        response = requests.post(
                            f"{bridge_url}/data/fetch",
                            json={"symbol": train_symbol, "timeframe": train_timeframe, "num_bars": num_bars},
                            timeout=30
                        )
                        if response.status_code == 200:
                            result = response.json()
                            st.success(f"✅ Fetched {result.get('bars_fetched', 0)} bars")
                        else:
                            st.error(f"Failed: HTTP {response.status_code}")
                    except Exception as e:
                        st.error(f"Error: {str(e)}")
        
        # Check data availability
        query = "SELECT COUNT(*) as cnt FROM market_data WHERE symbol = ? AND timeframe = ?"
        with db.get_connection() as conn:
            cursor = conn.execute(query, (train_symbol, train_timeframe))
            data_count = cursor.fetchone()[0]
        
        if data_count > 0:
            st.metric("Available Data", f"{data_count} bars", delta="Ready ✅")
        else:
            st.warning("⚠️ No data available. Fetch data first!")
        
        st.markdown("---")
        
        # Step 1.2: Train Basic Model
        st.subheader("🚀 Step 1.2: Train Basic Model (with TA-Lib)")
        
        col1, col2 = st.columns(2)
        with col1:
            hidden_layers = st.text_input("Hidden Layers", "50,30", key="basic_layers")
        with col2:
            max_iter = st.number_input("Max Iterations", 100, 2000, 500, key="basic_iter")
        
        if st.button("🚀 Train Basic Model", type="primary", disabled=(data_count < 100)):
            with st.spinner("Training with TA-Lib features..."):
                try:
                    from src.features import prepare_training_data, TALIB_AVAILABLE
                    from sklearn.neural_network import MLPClassifier
                    from sklearn.preprocessing import StandardScaler
                    from sklearn.model_selection import train_test_split
                    import pickle
                    from datetime import datetime
                    from pathlib import Path
                    
                    # Get data
                    query = "SELECT * FROM market_data WHERE symbol = ? AND timeframe = ? ORDER BY timestamp DESC LIMIT 1000"
                    with db.get_connection() as conn:
                        df = pd.read_sql_query(query, conn, params=(train_symbol, train_timeframe))
                    
                    # Prepare features
                    X, y, feature_names = prepare_training_data(df, use_talib=True)
                    
                    # Split and scale
                    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
                    scaler = StandardScaler()
                    X_train_scaled = scaler.fit_transform(X_train)
                    X_test_scaled = scaler.transform(X_test)
                    
                    # Train
                    layers = tuple(int(x.strip()) for x in hidden_layers.split(','))
                    model = MLPClassifier(hidden_layer_sizes=layers, max_iter=max_iter, random_state=42, early_stopping=True)
                    model.fit(X_train_scaled, y_train)
                    
                    # Evaluate
                    train_acc = model.score(X_train_scaled, y_train)
                    test_acc = model.score(X_test_scaled, y_test)
                    
                    # Save
                    model_dir = Path('/app/models')
                    model_dir.mkdir(exist_ok=True)
                    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                    model_path = model_dir / f"mlp_{train_symbol}_{train_timeframe}_{timestamp}.pkl"
                    
                    with open(model_path, 'wb') as f:
                        pickle.dump({'model': model, 'scaler': scaler, 'features': feature_names, 'use_talib': TALIB_AVAILABLE}, f)
                    
                    model_id = db.save_model(
                        name=f"MLP_{train_symbol}_{train_timeframe}",
                        version=timestamp,
                        model_type='MLPClassifier',
                        file_path=str(model_path),
                        training_accuracy=train_acc,
                        validation_accuracy=test_acc,
                        parameters={'hidden_layers': list(layers), 'features': feature_names, 'n_features': len(feature_names)}
                    )
                    db.set_active_model(model_id)
                    
                    st.success(f"✅ Model trained! Validation accuracy: {test_acc:.2%}")
                    st.metric("Training Accuracy", f"{train_acc:.2%}")
                    st.metric("Validation Accuracy", f"{test_acc:.2%}")
                    st.info(f"Using {len(feature_names)} TA-Lib features")
                    
                except Exception as e:
                    st.error(f"Training failed: {str(e)}")
                    import traceback
                    st.code(traceback.format_exc())
    
    # ==================== TAB 2: Optuna Optimization ====================
    with tab2:
        st.header("Step 2: Optimize Hyperparameters with Optuna")
        st.info("🔍 Optuna will automatically find the best model architecture, learning rate, and regularization")
        
        col1, col2 = st.columns(2)
        with col1:
            optuna_trials = st.slider("Number of trials", 10, 100, 30, step=10)
            st.caption("More trials = better results but slower (10-30 min)")
        with col2:
            st.metric("Expected Improvement", "+3-9%", delta="Target: 62-68%")
        
        if st.button("🔍 Run Optuna Optimization", type="primary"):
            with st.spinner(f"Running {optuna_trials} optimization trials... This will take 10-30 minutes"):
                try:
                    import optuna
                    from optuna.samplers import TPESampler
                    from optuna.pruners import MedianPruner
                    from src.features import prepare_training_data
                    from sklearn.neural_network import MLPClassifier
                    from sklearn.preprocessing import StandardScaler
                    from sklearn.model_selection import train_test_split
                    import pickle
                    from datetime import datetime
                    from pathlib import Path
                    
                    # Get data
                    query = "SELECT * FROM market_data WHERE symbol = ? AND timeframe = ? ORDER BY timestamp DESC LIMIT 1000"
                    with db.get_connection() as conn:
                        df = pd.read_sql_query(query, conn, params=(train_symbol, train_timeframe))
                    
                    X, y, feature_names = prepare_training_data(df, use_talib=True)
                    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
                    
                    # Optuna objective
                    def objective(trial):
                        n_layers = trial.suggest_int('n_layers', 1, 4)
                        hidden_layers = tuple([trial.suggest_int(f'layer_{i}', 16, 256, log=True) for i in range(n_layers)])
                        activation = trial.suggest_categorical('activation', ['relu', 'tanh'])
                        learning_rate = trial.suggest_float('learning_rate', 1e-5, 1e-2, log=True)
                        alpha = trial.suggest_float('alpha', 1e-5, 1e-1, log=True)
                        
                        model = MLPClassifier(
                            hidden_layer_sizes=hidden_layers,
                            activation=activation,
                            learning_rate_init=learning_rate,
                            alpha=alpha,
                            max_iter=500,
                            random_state=42,
                            early_stopping=True,
                            verbose=False
                        )
                        
                        scaler = StandardScaler()
                        X_train_scaled = scaler.fit_transform(X_train)
                        X_test_scaled = scaler.transform(X_test)
                        model.fit(X_train_scaled, y_train)
                        return model.score(X_test_scaled, y_test)
                    
                    # Run optimization
                    study = optuna.create_study(direction='maximize', sampler=TPESampler(seed=42), pruner=MedianPruner())
                    study.optimize(objective, n_trials=optuna_trials, show_progress_bar=False)
                    
                    # Train final model
                    best_params = study.best_params
                    n_layers = best_params['n_layers']
                    hidden_layers = tuple([best_params[f'layer_{i}'] for i in range(n_layers)])
                    
                    final_model = MLPClassifier(
                        hidden_layer_sizes=hidden_layers,
                        activation=best_params['activation'],
                        learning_rate_init=best_params['learning_rate'],
                        alpha=best_params['alpha'],
                        max_iter=1000,
                        random_state=42,
                        early_stopping=True
                    )
                    
                    scaler = StandardScaler()
                    X_train_scaled = scaler.fit_transform(X_train)
                    X_test_scaled = scaler.transform(X_test)
                    final_model.fit(X_train_scaled, y_train)
                    
                    train_acc = final_model.score(X_train_scaled, y_train)
                    test_acc = final_model.score(X_test_scaled, y_test)
                    
                    # Save
                    model_dir = Path('/app/models')
                    model_dir.mkdir(exist_ok=True)
                    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                    model_path = model_dir / f"mlp_optuna_{train_symbol}_{train_timeframe}_{timestamp}.pkl"
                    
                    with open(model_path, 'wb') as f:
                        pickle.dump({
                            'model': final_model, 
                            'scaler': scaler, 
                            'features': feature_names, 
                            'use_talib': True,  # Optuna models always use TA-Lib
                            'optuna_params': best_params
                        }, f)
                    
                    model_id = db.save_model(
                        name=f"MLP_Optuna_{train_symbol}_{train_timeframe}",
                        version=timestamp,
                        model_type='MLPClassifier_Optimized',
                        file_path=str(model_path),
                        training_accuracy=train_acc,
                        validation_accuracy=test_acc,
                        parameters={'hidden_layers': list(hidden_layers), 'optuna_params': best_params, 'n_trials': optuna_trials}
                    )
                    db.set_active_model(model_id)
                    
                    st.success(f"✅ Optimization complete! Best accuracy: {study.best_value:.2%}")
                    st.metric("Best Trial Accuracy", f"{study.best_value:.2%}")
                    st.metric("Final Model Accuracy", f"{test_acc:.2%}")
                    st.json(best_params)
                    
                except Exception as e:
                    st.error(f"Optimization failed: {str(e)}")
                    import traceback
                    st.code(traceback.format_exc())
    
    # ==================== TAB 3: Advanced Models ====================
    with tab3:
        st.header("Step 3: Advanced Models (LSTM, Ensemble)")
        st.warning("🚧 Coming soon: LSTM, Transformer, and Ensemble models")
        st.info("These models will be available in the next update")
    
    # ==================== TAB 4: Backtesting ====================
    with tab4:
        st.header("Step 4: Backtest Strategy")
        st.warning("🚧 Coming soon: Backtrader integration for strategy validation")
        st.info("You'll be able to test your models on historical data with realistic trading conditions")


# ==================== System Logs Page ====================
elif page == "System Logs":
    st.title("📋 System Logs")
    
    level_filter = st.selectbox("Level", ["All", "INFO", "WARNING", "ERROR"])
    component_filter = st.selectbox("Component", ["All", "BRIDGE", "TRADER", "ML_ENGINE", "DASHBOARD"])
    
    logs = db.get_logs(
        level=None if level_filter == "All" else level_filter,
        component=None if component_filter == "All" else component_filter,
        limit=100
    )
    
    if logs:
        df = pd.DataFrame(logs)
        st.dataframe(df[['created_at', 'level', 'component', 'message']], use_container_width=True)
    else:
        st.info("No logs found")

# Footer
st.sidebar.markdown("---")
st.sidebar.caption("CV Trading Agent v1.0")
