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
    ["Dashboard", "Live Predictions", "Portfolios", "Trading Control", "Live Trades", "Killzone Settings", "Exit Strategies", "Training", "System Logs"]
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
    
    # Portfolio Selection
    st.subheader("Active Portfolio")
    portfolios = db.get_portfolios()
    
    if not portfolios:
        st.warning("No portfolios available. Create one in the 'Portfolios' page.")
        active_portfolio_id = None
    else:
        current_portfolio_id = db.get_config('active_portfolio_id')
        
        # Find index of current portfolio
        current_index = 0
        if current_portfolio_id:
            for i, p in enumerate(portfolios):
                if str(p['id']) == current_portfolio_id:
                    current_index = i
                    break
        
        selected_portfolio_id = st.selectbox(
            "Select Portfolio using for Auto-Trading",
            options=[p['id'] for p in portfolios],
            format_func=lambda x: next((p['name'] for p in portfolios if p['id'] == x), str(x)),
            index=current_index
        )
        
        if str(selected_portfolio_id) != str(current_portfolio_id):
            db.set_config('active_portfolio_id', str(selected_portfolio_id))
            st.success(f"Active portfolio updated to: {next((p['name'] for p in portfolios if p['id'] == selected_portfolio_id), '')}")
            # Log the change
            db.log('INFO', 'DASHBOARD', f"Active portfolio changed to ID {selected_portfolio_id}")

    st.markdown("---")
    
    # Risk parameters
    st.subheader("Risk Parameters")
    
    config = db.get_all_config()
    
    # Account & Risk Settings
    st.markdown("#### 💰 Account & Risk Settings")
    
    # Fetch account balance from MT5 Bridge
    account_balance = 0.0
    try:
        bridge_url = os.getenv('BRIDGE_URL', 'http://host.docker.internal:5000')
        response = requests.get(f"{bridge_url}/status", timeout=2)
        if response.status_code == 200:
            status_data = response.json()
            if status_data.get('account_info'):
                account_balance = status_data['account_info']['balance']
    except:
        pass
    
    # Display account balance (read-only from MT5)
    col1, col2, col3 = st.columns(3)
    
    with col1:
        if account_balance > 0:
            st.metric("Account Balance (MT5)", f"${account_balance:,.2f}", help="Fetched automatically from MT5")
        else:
            st.warning("⚠️ MT5 Bridge offline - cannot fetch balance")
            account_balance = float(config.get('account_size_fallback', 5000.0))
            st.caption(f"Using fallback: ${account_balance:,.2f}")
    
    with col2:
        risk_per_trade_pct = st.slider("Risk Per Trade (%)", 0.1, 5.0, float(config.get('risk_per_trade_pct', 1.0)), 0.1)
    
    with col3:
        position_sizing_method = st.selectbox(
            "Position Sizing Method", 
            ["risk_based", "fixed_lot"],
            index=0 if config.get('position_sizing_method', 'risk_based') == 'risk_based' else 1
        )
    
    # Display calculated risk amount
    risk_amount = account_balance * (risk_per_trade_pct / 100)
    st.info(f"💵 **Risk per trade:** ${risk_amount:.2f} ({risk_per_trade_pct}% of ${account_balance:,.2f})")
    
    st.markdown("---")
    
    # Trading Limits
    st.markdown("#### 🛡️ Trading Limits")
    col1, col2 = st.columns(2)
    
    with col1:
        max_positions = st.number_input("Max Positions", value=int(config.get('max_positions', 3)), min_value=1, max_value=10)
        min_confidence = st.slider("Min Confidence", 0.0, 1.0, float(config.get('min_confidence', 0.70)), 0.01)
    
    with col2:
        max_daily_loss = st.number_input("Max Daily Loss %", value=float(config.get('max_daily_loss_pct', 5.0)), min_value=1.0, max_value=20.0)
        default_lot = st.number_input("Default Lot Size (Fallback)", value=float(config.get('default_lot_size', 0.01)), min_value=0.01, step=0.01)
    
    if st.button("💾 Save Configuration"):
        # Save risk settings (account balance is auto-fetched, no need to save)
        db.set_config('risk_per_trade_pct', str(risk_per_trade_pct))
        db.set_config('position_sizing_method', position_sizing_method)
        
        # Save trading limits
        db.set_config('max_positions', str(max_positions))
        db.set_config('min_confidence', str(min_confidence))
        db.set_config('max_daily_loss_pct', str(max_daily_loss))
        db.set_config('default_lot_size', str(default_lot))
        
        db.log('INFO', 'DASHBOARD', f'Configuration updated: Balance=${account_balance}, Risk={risk_per_trade_pct}%, Method={position_sizing_method}')
        st.success("✅ Configuration saved!")

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
        st.header("Step 3: Advanced Deep Learning Models")
        st.info("🚀 **TensorFlow/Keras models** with LSTM, CNN-LSTM, and Hybrid Ensemble for improved accuracy")
        
        # Create sub-tabs
        subtab1, subtab2, subtab3, subtab4 = st.tabs([
            "3.1 LSTM Model",
            "3.2 CNN-LSTM Model",
            "3.3 Hybrid Ensemble",
            "3.4 Model Comparison"
        ])
        
        # ========== Sub-tab 3.1: LSTM Model ==========
        with subtab1:
            st.subheader("🔷 LSTM Model Training")
            st.caption("Long Short-Term Memory networks capture temporal patterns in price sequences")
            
            col1, col2, col3 = st.columns(3)
            with col1:
                lstm_sequence_length = st.slider("Sequence Length", 10, 100, 20, step=5, key="lstm_seq_len")
                st.caption("Number of bars to look back")
            with col2:
                lstm_units_1 = st.select_slider("LSTM Layer 1 Units", options=[32, 64, 128, 256], value=128, key="lstm_units_1")
                lstm_units_2 = st.select_slider("LSTM Layer 2 Units", options=[16, 32, 64, 128], value=64, key="lstm_units_2")
            with col3:
                lstm_dropout = st.slider("Dropout Rate", 0.1, 0.5, 0.3, 0.05, key="lstm_dropout")
                lstm_use_attention = st.checkbox("Use Attention Mechanism", value=True, key="lstm_attention")
            
            col1, col2 = st.columns(2)
            with col1:
                lstm_epochs = st.number_input("Epochs", 10, 200, 50, step=10, key="lstm_epochs")
            with col2:
                lstm_batch_size = st.select_slider("Batch Size", options=[16, 32, 64, 128], value=32, key="lstm_batch")
            
            if st.button("🚀 Train LSTM Model", type="primary", disabled=(data_count < 500)):
                with st.spinner("Training LSTM model... This may take 10-20 minutes"):
                    try:
                        from src.training.tf_trainer import TensorFlowTrainer
                        from pathlib import Path
                        
                        # Initialize trainer
                        trainer = TensorFlowTrainer(db)
                        
                        # Prepare data
                        progress_bar = st.progress(0, text="Preparing data...")
                        X_train, X_val, X_test, y_train, y_val, y_test, scaler, features, info = trainer.prepare_data(
                            symbol=train_symbol,
                            timeframe=train_timeframe,
                            sequence_length=lstm_sequence_length
                        )
                        progress_bar.progress(20, text="Data prepared. Training model...")
                        
                        # Train LSTM
                        model, history = trainer.train_lstm(
                            X_train, y_train, X_val, y_val,
                            lstm_units=[lstm_units_1, lstm_units_2],
                            dense_units=[32, 16],
                            dropout_rate=lstm_dropout,
                            use_attention=lstm_use_attention,
                            epochs=lstm_epochs,
                            batch_size=lstm_batch_size
                        )
                        progress_bar.progress(80, text="Evaluating model...")
                        
                        # Evaluate
                        test_metrics = trainer.evaluate(X_test, y_test)
                        progress_bar.progress(90, text="Saving model...")
                        
                        # Save
                        train_metrics = {
                            'accuracy': history.history['accuracy'][-1],
                            'loss': history.history['loss'][-1]
                        }
                        
                        model_id = trainer.save_model(
                            symbol=train_symbol,
                            timeframe=train_timeframe,
                            model_type='LSTM',
                            train_metrics=train_metrics,
                            test_metrics=test_metrics,
                            hyperparameters={
                                'sequence_length': lstm_sequence_length,
                                'lstm_units': [lstm_units_1, lstm_units_2],
                                'dropout_rate': lstm_dropout,
                                'use_attention': lstm_use_attention,
                                'epochs': lstm_epochs,
                                'batch_size': lstm_batch_size
                            }
                        )
                        
                        progress_bar.progress(100, text="Complete!")
                        
                        # Display results
                        st.success(f"✅ LSTM model trained successfully! Model ID: {model_id}")
                        
                        col1, col2, col3 = st.columns(3)
                        with col1:
                            st.metric("Test Accuracy", f"{test_metrics['accuracy']:.2%}")
                        with col2:
                            st.metric("Test AUC", f"{test_metrics.get('auc', 0):.4f}")
                        with col3:
                            st.metric("Sequences Used", info['total_sequences'])
                        
                        # Plot training history
                        st.subheader("Training History")
                        history_df = pd.DataFrame({
                            'Epoch': range(1, len(history.history['accuracy']) + 1),
                            'Train Accuracy': history.history['accuracy'],
                            'Val Accuracy': history.history['val_accuracy'],
                            'Train Loss': history.history['loss'],
                            'Val Loss': history.history['val_loss']
                        })
                        
                        col1, col2 = st.columns(2)
                        with col1:
                            st.line_chart(history_df.set_index('Epoch')[['Train Accuracy', 'Val Accuracy']])
                        with col2:
                            st.line_chart(history_df.set_index('Epoch')[['Train Loss', 'Val Loss']])
                        
                    except Exception as e:
                        st.error(f"Training failed: {str(e)}")
                        import traceback
                        st.code(traceback.format_exc())
        
        # ========== Sub-tab 3.2: CNN-LSTM Model ==========
        with subtab2:
            st.subheader("🔶 CNN-LSTM Hybrid Model Training")
            st.caption("CNN extracts patterns, LSTM captures temporal dependencies")
            
            col1, col2, col3 = st.columns(3)
            with col1:
                cnn_sequence_length = st.slider("Sequence Length", 10, 100, 20, step=5, key="cnn_seq_len")
                cnn_filters_1 = st.select_slider("CNN Filters 1", options=[32, 64, 128], value=64, key="cnn_filters_1")
                cnn_filters_2 = st.select_slider("CNN Filters 2", options=[16, 32, 64], value=32, key="cnn_filters_2")
            with col2:
                cnn_kernel_size = st.slider("Kernel Size", 2, 5, 3, key="cnn_kernel")
                cnn_lstm_units_1 = st.select_slider("LSTM Units 1", options=[64, 128, 256], value=128, key="cnn_lstm_1")
                cnn_lstm_units_2 = st.select_slider("LSTM Units 2", options=[32, 64, 128], value=64, key="cnn_lstm_2")
            with col3:
                cnn_dropout = st.slider("Dropout Rate", 0.1, 0.5, 0.3, 0.05, key="cnn_dropout")
                cnn_use_attention = st.checkbox("Use Attention", value=True, key="cnn_attention")
            
            col1, col2 = st.columns(2)
            with col1:
                cnn_epochs = st.number_input("Epochs", 10, 200, 50, step=10, key="cnn_epochs")
            with col2:
                cnn_batch_size = st.select_slider("Batch Size", options=[16, 32, 64], value=32, key="cnn_batch")
            
            if st.button("🚀 Train CNN-LSTM Model", type="primary", disabled=(data_count < 500)):
                with st.spinner("Training CNN-LSTM model... This may take 15-30 minutes"):
                    try:
                        from src.training.tf_trainer import TensorFlowTrainer
                        
                        trainer = TensorFlowTrainer(db)
                        
                        progress_bar = st.progress(0, text="Preparing data...")
                        X_train, X_val, X_test, y_train, y_val, y_test, scaler, features, info = trainer.prepare_data(
                            symbol=train_symbol,
                            timeframe=train_timeframe,
                            sequence_length=cnn_sequence_length
                        )
                        progress_bar.progress(20, text="Training CNN-LSTM...")
                        
                        model, history = trainer.train_cnn_lstm(
                            X_train, y_train, X_val, y_val,
                            cnn_filters=[cnn_filters_1, cnn_filters_2],
                            kernel_size=cnn_kernel_size,
                            lstm_units=[cnn_lstm_units_1, cnn_lstm_units_2],
                            dense_units=[32],
                            dropout_rate=cnn_dropout,
                            use_attention=cnn_use_attention,
                            epochs=cnn_epochs,
                            batch_size=cnn_batch_size
                        )
                        progress_bar.progress(80, text="Evaluating...")
                        
                        test_metrics = trainer.evaluate(X_test, y_test)
                        progress_bar.progress(90, text="Saving...")
                        
                        train_metrics = {
                            'accuracy': history.history['accuracy'][-1],
                            'loss': history.history['loss'][-1]
                        }
                        
                        model_id = trainer.save_model(
                            symbol=train_symbol,
                            timeframe=train_timeframe,
                            model_type='CNN-LSTM',
                            train_metrics=train_metrics,
                            test_metrics=test_metrics,
                            hyperparameters={
                                'sequence_length': cnn_sequence_length,
                                'cnn_filters': [cnn_filters_1, cnn_filters_2],
                                'kernel_size': cnn_kernel_size,
                                'lstm_units': [cnn_lstm_units_1, cnn_lstm_units_2],
                                'dropout_rate': cnn_dropout,
                                'use_attention': cnn_use_attention
                            }
                        )
                        
                        progress_bar.progress(100, text="Complete!")
                        
                        st.success(f"✅ CNN-LSTM model trained! Model ID: {model_id}")
                        
                        col1, col2 = st.columns(2)
                        with col1:
                            st.metric("Test Accuracy", f"{test_metrics['accuracy']:.2%}")
                        with col2:
                            st.metric("Test AUC", f"{test_metrics.get('auc', 0):.4f}")
                        
                        # Plot history
                        history_df = pd.DataFrame({
                            'Epoch': range(1, len(history.history['accuracy']) + 1),
                            'Train Accuracy': history.history['accuracy'],
                            'Val Accuracy': history.history['val_accuracy']
                        })
                        st.line_chart(history_df.set_index('Epoch'))
                        
                    except Exception as e:
                        st.error(f"Training failed: {str(e)}")
                        import traceback
                        st.code(traceback.format_exc())
        
        # ========== Sub-tab 3.3: Hybrid Ensemble ==========
        with subtab3:
            st.subheader("🎯 Hybrid Ensemble Training")
            st.caption("Combines TensorFlow (LSTM, CNN-LSTM) with Scikit-Learn (XGBoost, RF, MLP) for best accuracy")
            
            st.markdown("#### Select Models to Include")
            col1, col2 = st.columns(2)
            with col1:
                st.markdown("**TensorFlow Models:**")
                include_lstm = st.checkbox("LSTM", value=True, key="ens_lstm")
                include_cnn_lstm = st.checkbox("CNN-LSTM", value=True, key="ens_cnn_lstm")
            with col2:
                st.markdown("**Scikit-Learn Models:**")
                include_xgb = st.checkbox("XGBoost", value=True, key="ens_xgb")
                include_rf = st.checkbox("Random Forest", value=True, key="ens_rf")
                include_mlp = st.checkbox("MLP", value=True, key="ens_mlp")
            
            col1, col2 = st.columns(2)
            with col1:
                ens_sequence_length = st.slider("Sequence Length (for LSTM)", 10, 50, 20, key="ens_seq")
            with col2:
                ens_voting = st.selectbox("Voting Method", ["soft", "hard"], key="ens_voting")
                st.caption("Soft = probability averaging, Hard = majority vote")
            
            n_models_selected = sum([include_lstm, include_cnn_lstm, include_xgb, include_rf, include_mlp])
            st.info(f"📊 Selected {n_models_selected} models for ensemble")
            
            if st.button("🎯 Train Hybrid Ensemble", type="primary", disabled=(data_count < 500 or n_models_selected < 2)):
                with st.spinner("Training hybrid ensemble... This may take 30-60 minutes"):
                    try:
                        from src.training.ensemble_trainer import HybridEnsembleTrainer
                        
                        trainer = HybridEnsembleTrainer(db)
                        
                        progress_bar = st.progress(0, text="Training ensemble models...")
                        
                        ensemble, metrics = trainer.train_ensemble(
                            symbol=train_symbol,
                            timeframe=train_timeframe,
                            include_lstm=include_lstm,
                            include_cnn_lstm=include_cnn_lstm,
                            include_xgboost=include_xgb,
                            include_rf=include_rf,
                            include_mlp=include_mlp,
                            sequence_length=ens_sequence_length,
                            voting=ens_voting
                        )
                        
                        progress_bar.progress(90, text="Saving ensemble...")
                        
                        model_id = trainer.save_ensemble(train_symbol, train_timeframe, metrics)
                        
                        progress_bar.progress(100, text="Complete!")
                        
                        st.success(f"✅ Hybrid ensemble trained! Model ID: {model_id}")
                        
                        # Display metrics
                        col1, col2, col3 = st.columns(3)
                        with col1:
                            st.metric("Ensemble Test Accuracy", f"{metrics['ensemble_test_accuracy']:.2%}")
                        with col2:
                            st.metric("Number of Models", metrics['n_models'])
                        with col3:
                            improvement = (metrics['ensemble_test_accuracy'] - max(metrics['individual_scores'].values())) * 100
                            st.metric("Improvement", f"+{improvement:.1f}%", delta="vs best individual")
                        
                        # Individual model scores
                        st.subheader("Individual Model Performance")
                        scores_df = pd.DataFrame({
                            'Model': list(metrics['individual_scores'].keys()),
                            'Accuracy': list(metrics['individual_scores'].values())
                        }).sort_values('Accuracy', ascending=False)
                        
                        st.dataframe(
                            scores_df,
                            column_config={
                                "Accuracy": st.column_config.ProgressColumn(
                                    "Accuracy",
                                    format="%.2f%%",
                                    min_value=0,
                                    max_value=1,
                                )
                            },
                            hide_index=True,
                            use_container_width=True
                        )
                        
                    except Exception as e:
                        st.error(f"Ensemble training failed: {str(e)}")
                        import traceback
                        st.code(traceback.format_exc())
        
        # ========== Sub-tab 3.4: Model Comparison ==========
        with subtab4:
            st.subheader("📊 Model Comparison")
            st.caption("Compare all trained models and select the best one")
            
            # Get all models from database
            query = "SELECT * FROM models ORDER BY created_at DESC LIMIT 20"
            with db.get_connection() as conn:
                models_df = pd.read_sql_query(query, conn)
            
            if len(models_df) > 0:
                # Display comparison table
                comparison_df = models_df[['id', 'name', 'model_type', 'validation_accuracy', 'training_accuracy', 'created_at']].copy()
                comparison_df['validation_accuracy'] = comparison_df['validation_accuracy'] * 100
                comparison_df['training_accuracy'] = comparison_df['training_accuracy'] * 100
                
                st.dataframe(
                    comparison_df,
                    column_config={
                        "id": "ID",
                        "name": "Model Name",
                        "model_type": "Type",
                        "validation_accuracy": st.column_config.ProgressColumn(
                            "Val Accuracy (%)",
                            format="%.2f%%",
                            min_value=0,
                            max_value=100,
                        ),
                        "training_accuracy": st.column_config.ProgressColumn(
                            "Train Accuracy (%)",
                            format="%.2f%%",
                            min_value=0,
                            max_value=100,
                        ),
                        "created_at": "Created"
                    },
                    hide_index=True,
                    use_container_width=True
                )
                
                # Select best model
                st.markdown("---")
                st.subheader("Set Active Model")
                
                col1, col2 = st.columns([3, 1])
                with col1:
                    selected_model_id = st.selectbox(
                        "Select model to activate",
                        options=models_df['id'].tolist(),
                        format_func=lambda x: f"ID {x}: {models_df[models_df['id']==x]['name'].values[0]} ({models_df[models_df['id']==x]['validation_accuracy'].values[0]:.2%})"
                    )
                with col2:
                    st.write("")
                    st.write("")
                    if st.button("✅ Set as Active", type="primary"):
                        db.set_active_model(selected_model_id)
                        st.success(f"Model {selected_model_id} is now active!")
                        st.rerun()
                
                # Show active model
                active_model_id = db.get_config('active_model_id')
                if active_model_id:
                    active_model = models_df[models_df['id'] == int(active_model_id)]
                    if len(active_model) > 0:
                        st.info(f"🟢 **Currently Active:** {active_model['name'].values[0]} (ID: {active_model_id})")
            else:
                st.warning("No models trained yet. Train a model in Tab 1, 2, or 3 first.")

    
    # ==================== TAB 4: Backtesting ====================
    with tab4:
        st.header("Step 4: Backtest Strategy")
        st.warning("🚧 Coming soon: Backtrader integration for strategy validation")
        st.info("You'll be able to test your models on historical data with realistic trading conditions")


# ==================== Portfolio Management Page ====================
elif page == "Portfolios":
    st.title("💼 Portfolio Management")
    
    from src.trading.portfolio_manager import PortfolioManager
    pm = PortfolioManager(db)
    
    tab1, tab2, tab3 = st.tabs(["Dashboard", "Create Portfolio", "Manage Allocations"])
    
    # === Tab 1: Portfolio Dashboard ===
    with tab1:
        portfolios = pm.db.get_portfolios()
        
        if not portfolios:
            st.info("No portfolios created yet. Go to 'Create Portfolio' tab to get started.")
        else:
            selected_portfolio_id = st.selectbox(
                "Select Portfolio", 
                options=[p['id'] for p in portfolios],
                format_func=lambda x: next((p['name'] for p in portfolios if p['id'] == x), str(x))
            )
            
            # Get live balance from session state (if available) or default to 0
            # We already fetch account info in the sidebar loop
            current_balance = 0.0
            try:
                # Re-fetch for latest balance
                bridge_url = os.getenv('BRIDGE_URL', 'http://host.docker.internal:5000')
                response = requests.get(f"{bridge_url}/status", timeout=2)
                if response.status_code == 200:
                    status_data = response.json()
                    if status_data.get('account_info'):
                        current_balance = status_data['account_info']['balance']
            except:
                pass
            
            summary = pm.get_portfolio_summary(selected_portfolio_id, total_account_balance=current_balance)
            
            if summary:
                p_info = summary['info']
                
                # Metric Cards
                col1, col2, col3, col4 = st.columns(4)
                with col1:
                   st.metric("Portfolio Initial", f"${p_info['initial_capital']:,.2f}")
                with col2:
                    current_cap = p_info['current_capital']
                    initial_cap = p_info['initial_capital']
                    delta = current_cap - initial_cap
                    st.metric("Portfolio Equity", f"${current_cap:,.2f}", delta=f"${delta:,.2f}")
                with col3:
                    if current_balance > 0:
                        # Calculate portfolio weight based on initial capital vs current balance
                        # This is a bit simplistic but shows relative size
                        weight = (p_info['current_capital'] / current_balance) if current_balance else 0
                        st.metric("Weight of Account", f"{weight:.1%}", help=f"Based on Account Balance: ${current_balance:,.2f}")
                    else:
                        st.metric("Weight of Account", "N/A")
                with col4:
                    allocated_pct = summary['total_allocated_weight']
                    st.metric("Active Allocation", f"{allocated_pct:.1%}")
                
                st.markdown("---")
                
                # Allocation Table
                st.subheader("Asset Allocation")
                allocations = summary.get('allocations', [])
                if allocations:
                    alloc_df = pd.DataFrame(allocations)
                    st.dataframe(
                        alloc_df[['symbol', 'strategy_name', 'weight', 'strategy_type']],
                        column_config={
                            "weight": st.column_config.ProgressColumn(
                                "Allocation %",
                                format="%.1f%%",
                                min_value=0,
                                max_value=1,
                            )
                        },
                        use_container_width=True
                    )
                else:
                    st.info("No strategies allocated. Go to 'Manage Allocations' tab.")
                
                # Performance Chart (Placeholder for now)
                st.subheader("Performance History")
                perf_data = summary['performance']
                if perf_data:
                    perf_df = pd.DataFrame(perf_data)
                    st.line_chart(perf_df.set_index('date')['total_equity'])
                else:
                    st.caption("No performance data available yet.")

    # === Tab 2: Create Portfolio ===
    with tab2:
        st.header("Create New Portfolio")
        
        with st.form("create_portfolio_form"):
            p_name = st.text_input("Portfolio Name", placeholder="e.g., Aggressive Scalper")
            p_desc = st.text_area("Description", placeholder="Strategy details...")
            
            # Use current live balance as initial capital
            current_balance = 0.0
            try:
                bridge_url = os.getenv('BRIDGE_URL', 'http://10.0.0.4:5000')
                response = requests.get(f"{bridge_url}/status", timeout=2)
                if response.status_code == 200:
                    status_data = response.json()
                    if status_data.get('account_info'):
                        current_balance = status_data['account_info']['balance']
            except:
                pass
            
            if st.form_submit_button("Create Portfolio"):
                if p_name:
                    try:
                        # If bridge is offline or balance is 0, default to 0.0 or a placeholder
                        initial_cap = current_balance if current_balance > 0 else 0.0
                        pm.create_portfolio(p_name, initial_cap, p_desc)
                        st.success(f"Portfolio '{p_name}' created successfully with Initial Capital: ${initial_cap:,.2f}")
                        st.rerun()
                    except Exception as e:
                        st.error(f"Error creating portfolio: {str(e)}")
                else:
                    st.error("Portfolio name is required.")

    # === Tab 3: Manage Allocations ===
    with tab3:
        st.header("Assign Strategies to Portfolios")
        
        portfolios = pm.db.get_portfolios()
        if not portfolios:
            st.warning("Create a portfolio first.")
        else:
            col1, col2 = st.columns(2)
            
            with col1:
                target_portfolio_id = st.selectbox(
                    "Target Portfolio",
                    options=[p['id'] for p in portfolios],
                    format_func=lambda x: next((p['name'] for p in portfolios if p['id'] == x), str(x)),
                    key="alloc_portfolio_select"
                )
            
            with col2:
                # Get available trained models
                with db.get_connection() as conn:
                    models = conn.execute("SELECT id, name FROM models ORDER BY created_at DESC").fetchall()
                
                selected_model_id = st.selectbox(
                    "Select Strategy/Model",
                    options=[m['id'] for m in models],
                    format_func=lambda x: next((m['name'] for m in models if m['id'] == x), str(x))
                )
            
            col3, col4 = st.columns(2)
            with col3:
                target_symbol = st.selectbox(
                    "Target Symbol", 
                    ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "AUDUSD", "USDCAD", "USDCHF", "NZDUSD", "EURJPY"],
                    key="alloc_symbol"
                )
            with col4:
                alloc_weight = st.slider("Allocation Weight (%)", 1, 100, 20) / 100.0
            
            if st.button("Add Strategy Allocation"):
                try:
                    model_name = next((m['name'] for m in models if m['id'] == selected_model_id), "Unknown Model")
                    pm.add_strategy_to_portfolio(
                        portfolio_id=target_portfolio_id,
                        strategy_name=f"{model_name} - {target_symbol}",
                        model_id=selected_model_id,
                        symbol=target_symbol,
                        weight=alloc_weight
                    )
                    st.success(f"Successfully allocated {alloc_weight:.0%} to {target_symbol}!")
                    st.rerun()
                except ValueError as ve:
                    st.error(str(ve))
                except Exception as e:
                    st.error(f"Allocation failed: {str(e)}")


# ==================== Killzone Settings Page ====================
elif page == "Killzone Settings":
    st.title("🕒 Killzone Settings")
    
    st.markdown("""
    Configure time-based trading windows to restrict trading to high-liquidity periods.
    Killzones help avoid low-liquidity periods and improve trade quality.
    """)
    
    # Load current config
    import yaml
    config_path = Path(__file__).parent.parent / "src" / "trading" / "config.yaml"
    with open(config_path, 'r') as f:
        config = yaml.safe_load(f)
    
    killzone_config = config.get('killzones', {})
    
    # Global Settings
    st.subheader("⚙️ Global Settings")
    col1, col2 = st.columns(2)
    
    with col1:
        enabled = st.checkbox("Enable Killzone Filtering", value=killzone_config.get('enabled', False))
    
    with col2:
        timezone_options = ["America/New_York", "Europe/London", "Europe/Athens", "Asia/Tokyo", "UTC"]
        current_tz = killzone_config.get('timezone', 'America/New_York')
        # Handle unknown timezones gracefully
        if current_tz not in timezone_options:
            timezone_options.append(current_tz)
        timezone = st.selectbox("Timezone", 
                               timezone_options,
                               index=timezone_options.index(current_tz))
    
    st.markdown("---")
    
    # Existing Killzones
    st.subheader("📋 Active Killzones")
    
    killzones = db.get_killzone_windows(active_only=False)
    
    if killzones:
        for kz in killzones:
            with st.expander(f"{'🟢' if kz['is_active'] else '🔴'} {kz['name']}", expanded=False):
                col1, col2, col3 = st.columns(3)
                
                with col1:
                    st.text_input("Name", value=kz['name'], key=f"name_{kz['id']}", disabled=True)
                    st.text_input("Start Time", value=kz['start_time'], key=f"start_{kz['id']}", disabled=True)
                
                with col2:
                    st.text_input("End Time", value=kz['end_time'], key=f"end_{kz['id']}", disabled=True)
                    st.text_input("Days", value=kz['days_of_week'], key=f"days_{kz['id']}", disabled=True)
                
                with col3:
                    st.text_input("Priority", value=kz['priority'], key=f"priority_{kz['id']}", disabled=True)
                    is_active = st.checkbox("Active", value=bool(kz['is_active']), key=f"active_{kz['id']}")
                
                col_a, col_b = st.columns(2)
                with col_a:
                    if st.button("🗑️ Delete", key=f"delete_{kz['id']}"):
                        db.delete_killzone_window(kz['id'])
                        st.success(f"Deleted {kz['name']}")
                        st.rerun()
                
                with col_b:
                    if st.button("💾 Update Status", key=f"update_{kz['id']}"):
                        db.update_killzone_window(kz['id'], is_active=is_active)
                        st.success(f"Updated {kz['name']}")
                        st.rerun()
    else:
        st.info("No killzones configured. Add one below.")
    
    st.markdown("---")
    
    # Add New Killzone
    st.subheader("➕ Add New Killzone")
    
    with st.form("add_killzone"):
        col1, col2 = st.columns(2)
        
        with col1:
            new_name = st.text_input("Name", placeholder="e.g., Asian Session")
            new_start = st.time_input("Start Time", value=datetime.strptime("08:00", "%H:%M").time())
            new_priority = st.selectbox("Priority", ["high", "medium", "low"])
        
        with col2:
            new_end = st.time_input("End Time", value=datetime.strptime("12:00", "%H:%M").time())
            days_options = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
            new_days = st.multiselect("Active Days", days_options, default=days_options[:5])
        
        submitted = st.form_submit_button("Add Killzone")
        
        if submitted:
            if new_name and new_days:
                # Convert day names to numbers (0=Monday, 6=Sunday)
                day_map = {day: str(i) for i, day in enumerate(days_options)}
                days_str = ",".join([day_map[day] for day in new_days])
                
                db.add_killzone_window(
                    name=new_name,
                    start_time=new_start.strftime("%H:%M"),
                    end_time=new_end.strftime("%H:%M"),
                    days_of_week=days_str,
                    timezone=timezone,
                    priority=new_priority
                )
                st.success(f"Added killzone: {new_name}")
                st.rerun()
            else:
                st.error("Please fill in all fields")
    
    # Save Global Settings
    if st.button("💾 Save Global Settings"):
        config['killzones']['enabled'] = enabled
        config['killzones']['timezone'] = timezone
        
        with open(config_path, 'w') as f:
            yaml.dump(config, f, default_flow_style=False)
        
        st.success("Global settings saved! Restart trader for changes to take effect.")


# ==================== Exit Strategies Page ====================
elif page == "Exit Strategies":
    st.title("🎯 Exit Strategies")
    
    st.markdown("""
    Configure advanced exit strategies to optimize trade management.
    These strategies work together to protect capital and maximize profits.
    """)
    
    # Load current config
    import yaml
    config_path = Path(__file__).parent.parent / "src" / "trading" / "config.yaml"
    with open(config_path, 'r') as f:
        config = yaml.safe_load(f)
    
    exit_config = config.get('exit_strategies', {})
    
    # Breakeven Stop
    st.subheader("🛡️ Breakeven Stop")
    st.markdown("Move stop loss to entry price after reaching a specified risk-reward ratio.")
    
    col1, col2 = st.columns(2)
    with col1:
        breakeven_enabled = st.checkbox("Enable Breakeven Stop", value=exit_config.get('breakeven_enabled', True))
    with col2:
        breakeven_ratio = st.number_input("Breakeven Ratio (R:R)", min_value=0.5, max_value=3.0, value=exit_config.get('breakeven_ratio', 1.0), step=0.1)
    
    st.caption("💡 Recommended: 1.0 (move to BE after 1:1 R:R)")
    
    st.markdown("---")
    
    # Partial Profit Taking
    st.subheader("💰 Partial Profit Taking")
    st.markdown("Close a portion of the position at an interim target, let the rest run.")
    
    col1, col2, col3 = st.columns(3)
    with col1:
        partial_enabled = st.checkbox("Enable Partial Profits", value=exit_config.get('partial_profit_enabled', True))
    with col2:
        partial_ratio = st.number_input("Target Ratio", min_value=0.3, max_value=0.9, value=exit_config.get('partial_profit_ratio', 0.5), step=0.1)
    with col3:
        partial_percent = st.number_input("Close %", min_value=0.2, max_value=0.8, value=exit_config.get('partial_close_percent', 0.5), step=0.1)
    
    st.caption("💡 Recommended: Close 50% at 50% of TP")
    
    st.markdown("---")
    
    # ATR Trailing Stop
    st.subheader("📈 ATR Trailing Stop")
    st.markdown("Dynamic stop loss that trails price based on market volatility (ATR).")
    
    col1, col2, col3 = st.columns(3)
    with col1:
        trailing_enabled = st.checkbox("Enable Trailing Stop", value=exit_config.get('trailing_stop_enabled', True))
    with col2:
        atr_multiplier = st.number_input("ATR Multiplier", min_value=1.0, max_value=3.0, value=exit_config.get('atr_multiplier', 1.5), step=0.1)
    with col3:
        atr_period = st.number_input("ATR Period", min_value=7, max_value=21, value=exit_config.get('atr_period', 14), step=1)
    
    st.caption("💡 Recommended: 1.5x ATR with 14-period for M5 scalping")
    
    st.markdown("---")
    
    # Time-Based Exit
    st.subheader("⏱️ Time-Based Exit")
    st.markdown("Close positions held longer than a specified duration to avoid overnight exposure.")
    
    col1, col2 = st.columns(2)
    with col1:
        time_exit_enabled = st.checkbox("Enable Time Exit", value=exit_config.get('time_exit_enabled', True))
    with col2:
        max_hold_minutes = st.number_input("Max Hold Time (minutes)", min_value=30, max_value=1440, value=exit_config.get('max_hold_minutes', 240), step=30)
    
    st.caption("💡 Recommended: 240 minutes (4 hours) for M5 scalping")
    
    st.markdown("---")
    
    # Killzone Exit
    st.subheader("🕒 Killzone Exit")
    st.markdown("Optionally close all positions when a killzone ends.")
    
    close_on_killzone_end = st.checkbox("Close on Killzone End", value=exit_config.get('close_on_killzone_end', False))
    st.caption("⚠️ Not recommended: May cut winning trades short")
    
    st.markdown("---")
    
    # Save Button
    if st.button("💾 Save Exit Strategy Settings"):
        config['exit_strategies'] = {
            'breakeven_enabled': breakeven_enabled,
            'breakeven_ratio': breakeven_ratio,
            'partial_profit_enabled': partial_enabled,
            'partial_profit_ratio': partial_ratio,
            'partial_close_percent': partial_percent,
            'trailing_stop_enabled': trailing_enabled,
            'atr_multiplier': atr_multiplier,
            'atr_period': int(atr_period),
            'time_exit_enabled': time_exit_enabled,
            'max_hold_minutes': int(max_hold_minutes),
            'close_on_killzone_end': close_on_killzone_end
        }
        
        with open(config_path, 'w') as f:
            yaml.dump(config, f, default_flow_style=False)
        
        st.success("✅ Exit strategy settings saved! Restart trader for changes to take effect.")
    
    # Current Status Summary
    st.markdown("---")
    st.subheader("📊 Current Configuration Summary")
    
    col1, col2 = st.columns(2)
    
    with col1:
        st.metric("Breakeven Stop", "✅ Enabled" if breakeven_enabled else "❌ Disabled")
        st.metric("Partial Profits", "✅ Enabled" if partial_enabled else "❌ Disabled")
        st.metric("Trailing Stop", "✅ Enabled" if trailing_enabled else "❌ Disabled")
    
    with col2:
        st.metric("Time Exit", "✅ Enabled" if time_exit_enabled else "❌ Disabled")
        st.metric("Killzone Exit", "✅ Enabled" if close_on_killzone_end else "❌ Disabled")


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
