"""
Computer Vision Trading Agent - Streamlit Dashboard

Main dashboard for monitoring ML predictions, trading activity, and system status.
"""

import streamlit as st
import sys
from pathlib import Path
import pandas as pd
import plotly.graph_objects as go
import plotly.express as px
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
    ["Dashboard", "Live Predictions", "Portfolios", "Trading Control", "Signal Monitor", "Live Trades", "Killzone Settings", "Exit Strategies", "Training", "System Logs"]
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
        today = datetime.now().date()
        trades_today = []
        for t in recent_trades:
            close_time = t['close_time']
            if hasattr(close_time, 'date'):
                # datetime object
                if close_time.date() == today:
                    trades_today.append(t)
            else:
                # string
                if str(close_time)[:10] == str(today):
                    trades_today.append(t)
        st.metric("Trades Today", len(trades_today))
    
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
        cursor = conn.execute(predictions_query)
        rows = cursor.fetchall()
        predictions_df = pd.DataFrame(rows)
    
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
                            WHERE symbol = %s
                            ORDER BY timestamp DESC
                            LIMIT 100
                        """
                        with db.get_connection() as conn:
                            cursor = conn.execute(query, (symbol,))
                            rows = cursor.fetchall()
                            df = pd.DataFrame(rows)
                        
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
            # Format datetime object
            created_at = predictions['created_at']
            time_str = created_at.strftime('%Y-%m-%d %H:%M') if hasattr(created_at, 'strftime') else str(created_at)[:16]
            st.metric("Time", time_str)
        
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
    
    st.markdown("---")
    
    # Exit Strategy Settings
    st.markdown("#### 🎯 Exit Strategy & Timeframe Settings")
    
    col1, col2, col3 = st.columns(3)
    
    with col1:
        trading_timeframe = st.selectbox(
            "Trading Timeframe",
            ["M5", "M15", "M30", "H1", "H4", "D1"],
            index=["M5", "M15", "M30", "H1", "H4", "D1"].index(config.get('trading_timeframe', 'H1')),
            help="Timeframe for SL/TP calculation and ATR"
        )
    
    with col2:
        atr_multiplier = st.slider(
            "ATR Multiplier (SL Distance)", 
            0.5, 3.0, 
            float(config.get('atr_multiplier', '1.0')), 
            0.1,
            help="H1: 1.0 | M5: 1.5 | H4: 0.8"
        )
        st.caption(f"SL = ATR × {atr_multiplier}")
    
    with col3:
        max_hold_hours = st.number_input(
            "Max Hold Time (hours)", 
            1, 72, 
            int(config.get('max_hold_minutes', '1440')) // 60,
            help="H1: 24h | M5: 4h | H4: 48h"
        )
        st.caption(f"= {max_hold_hours * 60} minutes")
    
    # Show estimated SL/TP for selected timeframe
    atr_estimates = {
        'M5': 0.0010, 'M15': 0.0020, 'M30': 0.0030,
        'H1': 0.0050, 'H4': 0.0100, 'D1': 0.0200
    }
    estimated_atr = atr_estimates.get(trading_timeframe, 0.0050)
    estimated_sl_pips = (estimated_atr * atr_multiplier) * 10000  # Convert to pips
    estimated_tp_pips = estimated_sl_pips * 2  # 1:2 R:R
    
    st.info(f"📊 **Estimated for {trading_timeframe}:** SL ≈ {estimated_sl_pips:.0f} pips | TP ≈ {estimated_tp_pips:.0f} pips (1:2 R:R)")
    
    if st.button("💾 Save Configuration"):
        # Save risk settings (account balance is auto-fetched, no need to save)
        db.set_config('risk_per_trade_pct', str(risk_per_trade_pct))
        db.set_config('position_sizing_method', position_sizing_method)
        
        # Save trading limits
        db.set_config('max_positions', str(max_positions))
        db.set_config('min_confidence', str(min_confidence))
        db.set_config('max_daily_loss_pct', str(max_daily_loss))
        db.set_config('default_lot_size', str(default_lot))
        
        # Save exit strategy settings
        db.set_config('trading_timeframe', trading_timeframe)
        db.set_config('atr_multiplier', str(atr_multiplier))
        db.set_config('max_hold_minutes', str(max_hold_hours * 60))
        
        db.log('INFO', 'DASHBOARD', f'Configuration updated: Balance=${account_balance}, Risk={risk_per_trade_pct}%, Method={position_sizing_method}, Timeframe={trading_timeframe}, ATR={atr_multiplier}x')
        st.success(f"✅ Configuration saved! Trading on {trading_timeframe} with {atr_multiplier}x ATR multiplier")

# ==================== Signal Monitor Page ====================
elif page == "Signal Monitor":
    st.title("🔍 Signal Monitor - Confirmation System")

    st.markdown("""
    **Signal Flow:** Predictions → Validation → Confirmation → Execution
    - **Pending**: Awaiting validation
    - **Confirmed**: Passed validation, ready to trade
    - **Rejected**: Failed validation
    - **Executed**: Trade placed
    - **Expired**: Confirmation window elapsed
    """)

    # Get signal statistics
    stats = db.get_signal_stats_summary(hours=24)

    # Show stats overview
    st.subheader("📊 24-Hour Statistics")
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        total = stats.get('total', 0)
        st.metric("Total Signals", total)

    with col2:
        confirmed = stats.get('CONFIRMED', {}).get('count', 0)
        executed = stats.get('EXECUTED', {}).get('count', 0)
        confirmation_rate = round((confirmed + executed) / total * 100, 1) if total > 0 else 0
        st.metric("Confirmation Rate", f"{confirmation_rate}%")

    with col3:
        rejected = stats.get('REJECTED', {}).get('count', 0)
        expired = stats.get('EXPIRED', {}).get('count', 0)
        failed = rejected + expired
        st.metric("Failed (Rejected/Expired)", failed, delta=None, delta_color="inverse")

    with col4:
        executed_count = stats.get('EXECUTED', {}).get('count', 0)
        st.metric("Executed", executed_count)

    st.markdown("---")

    # Tabs for different views
    tab1, tab2, tab3, tab4 = st.tabs(["🕐 Pending Signals", "✅ Confirmed Signals", "❌ Rejected & Expired", "🛡️ Active Cooldowns"])

    # Tab 1: Pending Signals
    with tab1:
        st.subheader("Pending Signals (Awaiting Validation)")

        pending = db.get_pending_signals(limit=50)

        if pending:
            df = pd.DataFrame(pending)
            df['time_remaining'] = (pd.to_datetime(df['confirmation_window_end']) - pd.Timestamp.now()).dt.total_seconds() / 60

            display_df = df[['symbol', 'direction', 'initial_confidence', 'time_remaining', 'signal_generated_at']]
            display_df['initial_confidence'] = display_df['initial_confidence'].apply(lambda x: f"{x*100:.1f}%")
            display_df['time_remaining'] = display_df['time_remaining'].apply(lambda x: f"{x:.1f} min")

            st.dataframe(display_df, use_container_width=True)
        else:
            st.info("No pending signals")

    # Tab 2: Confirmed Signals
    with tab2:
        st.subheader("Confirmed Signals (Ready to Execute)")

        confirmed_signals = db.get_confirmed_signals_ready_to_trade(limit=50)

        if confirmed_signals:
            df = pd.DataFrame(confirmed_signals)

            display_df = df[['symbol', 'prediction_direction', 'confirmation_score', 'mtf_score', 'momentum_score', 'volume_score', 'trend_score', 'fibonacci_score', 'smc_score', 'confirmed_at']]
            display_df.columns = ['Symbol', 'Direction', 'Total Score', 'MTF', 'Momentum', 'Volume', 'Trend', 'Fibonacci', 'SMC', 'Confirmed At']

            # Format scores
            for col in ['Total Score', 'MTF', 'Momentum', 'Volume', 'Trend', 'Fibonacci', 'SMC']:
                display_df[col] = display_df[col].apply(lambda x: f"{x:.1f}" if pd.notna(x) else "N/A")

            st.dataframe(display_df, use_container_width=True)

            # Show validation breakdown for selected signal
            if len(confirmed_signals) > 0:
                st.markdown("---")
                st.subheader("Validation Breakdown")

                selected_idx = st.selectbox("Select signal to view details:", range(len(confirmed_signals)),
                                           format_func=lambda i: f"{confirmed_signals[i]['symbol']} {confirmed_signals[i]['prediction_direction']} ({confirmed_signals[i]['confirmation_score']:.1f})")

                signal = confirmed_signals[selected_idx]

                col1, col2, col3 = st.columns(3)

                with col1:
                    st.markdown("**Core Validation:**")
                    st.progress(signal['confirmation_score'] / 100, text=f"Overall: {signal['confirmation_score']:.1f}/100")
                    st.progress(signal['mtf_score'] / 100, text=f"MTF Alignment: {signal['mtf_score']:.1f}/100")
                    st.progress(signal['momentum_score'] / 100, text=f"Momentum: {signal['momentum_score']:.1f}/100")

                with col2:
                    st.markdown("**Technical Analysis:**")
                    st.progress(signal['volume_score'] / 100, text=f"Volume: {signal['volume_score']:.1f}/100")
                    st.progress(signal['trend_score'] / 100, text=f"Trend Strength: {signal['trend_score']:.1f}/100")

                    # Show MTF alignment
                    mtf_status = "✅ Aligned" if signal['mtf_alignment'] == 1 else ("❌ Against" if signal['mtf_alignment'] == -1 else "⚪ Neutral")
                    st.caption(f"**MTF:** {mtf_status}")

                with col3:
                    st.markdown("**Institutional Analysis:**")
                    fibonacci_score = signal.get('fibonacci_score', 50)
                    smc_score = signal.get('smc_score', 50)
                    st.progress(fibonacci_score / 100, text=f"Fibonacci: {fibonacci_score:.1f}/100")
                    st.progress(smc_score / 100, text=f"Smart Money: {smc_score:.1f}/100")

                    # Show if in OTE zone or near Order Block
                    if fibonacci_score >= 60:
                        st.caption("✨ Strong Fibonacci setup")
                    if smc_score >= 60:
                        st.caption("✨ Strong SMC setup")

        else:
            st.info("No confirmed signals ready to execute")

    # Tab 3: Rejected & Expired Signals
    with tab3:
        st.subheader("Recently Rejected & Expired Signals")

        # Get both rejected and expired signals
        rejected = db.get_recent_signals(hours=24, status='REJECTED')
        expired = db.get_recent_signals(hours=24, status='EXPIRED')

        # Combine them
        all_failed = rejected + expired

        if all_failed:
            df = pd.DataFrame(all_failed)

            display_df = df[['symbol', 'direction', 'status', 'initial_confidence', 'confirmation_score', 'rejection_reason', 'signal_generated_at']]
            display_df['initial_confidence'] = display_df['initial_confidence'].apply(lambda x: f"{x*100:.1f}%")
            display_df['confirmation_score'] = display_df['confirmation_score'].apply(lambda x: f"{x:.1f}" if pd.notna(x) else "N/A")

            st.dataframe(display_df, use_container_width=True)

            # Show common rejection reasons
            st.markdown("---")
            st.subheader("Failure Reasons Distribution")

            reasons = df['rejection_reason'].value_counts()
            if not reasons.empty:
                fig = px.bar(x=reasons.index, y=reasons.values,
                            labels={'x': 'Reason', 'y': 'Count'},
                            title="Rejection Reasons Distribution")
                st.plotly_chart(fig, use_container_width=True)

        else:
            st.info("No rejected or expired signals in the last 24 hours")

    # Tab 4: Active Cooldowns
    with tab4:
        st.subheader("Active Cooldowns")

        cooldowns = db.get_active_cooldowns()

        if cooldowns:
            data = []
            for cd in cooldowns:
                from datetime import datetime
                cooldown_end = cd['cooldown_end_time']
                if isinstance(cooldown_end, str):
                    cooldown_end = datetime.fromisoformat(cooldown_end)
                remaining = (cooldown_end - datetime.now()).total_seconds() / 60

                data.append({
                    'Symbol': cd['symbol'],
                    'Reason': cd['reason'],
                    'Last Direction': cd['trade_direction'] or 'N/A',
                    'Remaining (min)': f"{remaining:.1f}",
                    'Cooldown Ends': cd['cooldown_end_time']
                })

            df = pd.DataFrame(data)
            st.dataframe(df, use_container_width=True)

            # Show cooldown distribution
            st.markdown("---")
            st.subheader("Cooldown Reasons")

            reason_counts = pd.Series([cd['reason'] for cd in cooldowns]).value_counts()
            fig = px.pie(values=reason_counts.values, names=reason_counts.index,
                        title="Cooldown Distribution")
            st.plotly_chart(fig, use_container_width=True)

        else:
            st.success("✅ No active cooldowns - all symbols available for trading")

    # Show confirmation system settings
    st.markdown("---")
    st.subheader("⚙️ Confirmation System Settings")

    with st.expander("View Current Settings"):
        import yaml
        try:
            with open('src/trading/config.yaml', 'r') as f:
                config = yaml.safe_load(f)

            conf_settings = config.get('signal_confirmation', {})
            cooldown_settings = config.get('cooldowns', {})
            weights = conf_settings.get('weights', {})
            fib_settings = conf_settings.get('fibonacci_validation', {})
            smc_settings = conf_settings.get('smc_validation', {})

            col1, col2, col3 = st.columns(3)

            with col1:
                st.markdown("**Signal Confirmation:**")
                st.text(f"Enabled: {conf_settings.get('enabled', False)}")
                st.text(f"Confirmation Window: {conf_settings.get('confirmation_window_seconds', 0)}s")
                st.text(f"Min Score: {conf_settings.get('min_confirmation_score', 0)}")

                st.markdown("**Scoring Weights:**")
                st.text(f"MTF: {weights.get('mtf_alignment', 0)}%")
                st.text(f"Momentum: {weights.get('momentum_confluence', 0)}%")
                st.text(f"Volume: {weights.get('volume_confirmation', 0)}%")
                st.text(f"Trend: {weights.get('trend_strength', 0)}%")
                st.text(f"Fibonacci: {weights.get('fibonacci_alignment', 0)}%")
                st.text(f"SMC: {weights.get('smc_confluence', 0)}%")
                st.text(f"Model: {weights.get('model_confidence', 0)}%")

            with col2:
                st.markdown("**Fibonacci Validation:**")
                st.text(f"Enabled: {fib_settings.get('enabled', False)}")
                st.text(f"Swing Lookback: {fib_settings.get('swing_lookback', 50)} bars")
                st.text(f"Min Score: {fib_settings.get('min_fib_score', 40)}")
                st.text(f"Require OTE: {fib_settings.get('require_ote_zone', False)}")

                st.markdown("**SMC Validation:**")
                st.text(f"Enabled: {smc_settings.get('enabled', False)}")
                st.text(f"OB Lookback: {smc_settings.get('order_block_lookback', 50)} bars")
                st.text(f"Min Score: {smc_settings.get('min_smc_score', 40)}")

            with col3:
                st.markdown("**Cooldowns:**")
                st.text(f"Enabled: {cooldown_settings.get('enabled', False)}")
                st.text(f"Symbol Cooldown: {cooldown_settings.get('symbol_cooldown_minutes', 0)} min")
                st.text(f"Loss Cooldown: {cooldown_settings.get('loss_cooldown_minutes', 0)} min")
                st.text(f"Global Cooldown: {cooldown_settings.get('global_cooldown_minutes', 0)} min")

        except Exception as e:
            st.error(f"Error loading config: {e}")

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
    st.title("🚀 End-to-End Strategy Factory")
    st.caption("One Process: Data Fetch ➡ Hyper-Opt Training ➡ Backtest Validation")

    # --- Section 1: Data Setup ---
    st.header("1️⃣ Data Setup")
    
    col1, col2, col3, col4 = st.columns(4)
    with col1:
        train_symbol = st.text_input("Symbol", value="EURUSD", key="train_sym")
    with col2:
        train_timeframe = st.selectbox("Timeframe", ["M1", "M5", "M15", "M30", "H1", "H4", "D1"], index=4, key="train_tf")
    with col3:
        fetch_bars = st.number_input("Bars to Fetch", min_value=1000, max_value=50000, value=5000, step=1000)
    with col4:
        st.markdown("###") # Spacer
        if st.button("📥 Fetch & Prepare Data", type="primary", use_container_width=True):
            with st.spinner(f"Fetching {fetch_bars} bars for {train_symbol} {train_timeframe}..."):
                try:
                    # Check DB first
                    query = "SELECT COUNT(*) FROM market_data WHERE symbol = %s AND timeframe = %s"
                    with db.get_connection() as conn:
                        count = conn.execute(query, (train_symbol, train_timeframe)).fetchone()[0]
                    
                    if count < fetch_bars:
                         st.warning(f"DB has only {count} bars. Requesting MT5 (if active)...")
                         # Send command to MT5 via ZMQ/Bridge
                         bridge_url = os.getenv('BRIDGE_URL', 'http://host.docker.internal:5000')
                         try:
                             requests.post(
                                 f"{bridge_url}/data/fetch",
                                 json={"symbol": train_symbol, "timeframe": train_timeframe, "num_bars": fetch_bars},
                                 timeout=5
                             )
                             st.success(f"Signal sent to Fetch: {fetch_bars} bars.")
                         except:
                             st.success("Simulated Fetch Signal (Bridge not reachable).")
                    else:
                        st.success(f"✅ Data Ready: {count} bars available.")
                        
                except Exception as e:
                    st.error(f"Data Check Failed: {e}")

    # Check Data Count for context
    try:
        query = "SELECT COUNT(*) FROM market_data WHERE symbol = %s AND timeframe = %s"
        with db.get_connection() as conn:
            data_count = conn.execute(query, (train_symbol, train_timeframe)).fetchone()[0]
    except:
        data_count = 0
        
    st.metric("Total Data Available", f"{data_count} bars")
    
    st.markdown("---")

    # --- Section 2: One-Click Factory ---
    st.header("2️⃣ Construction & Optimization")
    
    st.info("This process will automatically:\n"
            "1. Train multiple model architectures (LSTM, CNN, RF, XGB)\n"
            "2. Optimize hyperparameters (Sequences, Voting, Thresholds) using **Optuna**\n"
            "3. Validate strategy profitability using **VectorBT**")
    
    c1, c2 = st.columns([1, 3])
    with c1:
        trials = st.slider("Optimization Trials", 5, 50, 10)
        voting_mode = st.radio("Voting Preference", ["Soft (Probability)", "Hard (Majority)"], index=0)
        
    with c2:
        st.markdown("###")
        start_process = st.button("🚀 RUN END-TO-END PROCESS", type="primary", use_container_width=True, disabled=(data_count < 500))

    if start_process:
        status_area = st.container()
        
        with status_area:
            st.write("---")
            st.subheader("⚙️ Execution Log")
            
            # 1. Initialize
            prog_bar = st.progress(0, "Starting Engine...")
            
            try:
                from src.training.ensemble_optimizer import EnsembleOptimizer
                optimizer = EnsembleOptimizer(db)
                
                # 2. Run Optimization
                prog_bar.progress(10, "Running Hyper-Ensemble Optimization (Optuna + VectorBT)...")
                
                # Real-time output container
                with st.status("🏗️ Building Strategy...", expanded=True) as status:
                    st.write(f"Objective: Maximize Profit Factor | Trials: {trials}")
                    
                    ensemble, metrics = optimizer.optimize(
                        symbol=train_symbol,
                        timeframe=train_timeframe,
                        n_trials=trials
                    )
                    
                    st.write("✅ Optimization Complete!")
                    st.write(f"Best Profit Factor: {metrics.get('optimization', {}).get('best_score', 0):.2f}")
                    status.update(label="Strategy Built ✅", state="complete", expanded=False)

                # 3. Save
                prog_bar.progress(90, "Saving Strategy to Database...")
                model_id = optimizer.trainer.save_ensemble(train_symbol, train_timeframe, metrics)
                prog_bar.progress(100, "Done!")
                
                # --- Section 3: Results ---
                st.markdown("---")
                st.header("3️⃣ Validation Results")
                st.success(f"Strategy Saved ID: `{model_id}`")
                
                best_opt = metrics.get('optimization', {})
                best_params = best_opt.get('best_params', {})
                
                # Metrics Grid
                m1, m2, m3, m4 = st.columns(4)
                with m1:
                    st.metric("Profit Factor", f"{best_opt.get('best_score', 0):.2f}")
                with m2:
                    st.metric("Test Accuracy", f"{metrics.get('ensemble_test_accuracy', 0):.2%}")
                with m3:
                    st.metric("Total Trades (Test)", "?") # We could extract this if we saved it
                with m4:
                    st.metric("Model Type", "Hybrid Ensemble")
                
                # Architecture Display
                st.subheader("🧠 Winning Architecture")
                active_models = []
                if best_params.get('include_lstm'): active_models.append("LSTM")
                if best_params.get('include_cnn_lstm'): active_models.append("CNN-LSTM")
                if best_params.get('include_xgb'): active_models.append("XGBoost")
                if best_params.get('include_rf'): active_models.append("Random Forest")
                
                st.success(f"**Composition:** {' + '.join(active_models)}")
                st.json(best_params)
                
            except Exception as e:
                st.error(f"❌ Process Failed: {e}")
                st.exception(e)



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
    
    st.markdown("---")
    
    # Pair-Killzone Compatibility Matrix
    st.subheader("📊 Pair-Killzone Compatibility Matrix")
    st.caption("Shows which currency pairs are optimal for each trading session")
    
    # Define all supported pairs
    all_pairs = ["EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD", "USDCAD", "NZDUSD", 
                 "EURJPY", "GBPJPY", "EURGBP", "AUDJPY", "XAUUSD"]
    
    # Get active killzones
    active_killzones = db.get_killzone_windows(active_only=True)
    
    if active_killzones:
        # Load config to get optimal_pairs
        killzone_config = config.get('killzones', {})
        config_windows = killzone_config.get('windows', [])
        
        # Create compatibility matrix
        matrix_data = []
        for pair in all_pairs:
            row = {"Pair": pair}
            for kz in active_killzones:
                # Find matching config window to get optimal_pairs
                optimal_pairs = []
                for cw in config_windows:
                    if cw.get('name') == kz['name']:
                        optimal_pairs = cw.get('optimal_pairs', [])
                        break
                
                # Check if pair is optimal for this killzone
                if optimal_pairs and pair in optimal_pairs:
                    row[kz['name']] = "✅"
                elif not optimal_pairs:
                    # If no optimal_pairs specified, all pairs are allowed
                    row[kz['name']] = "⚪"
                else:
                    row[kz['name']] = "❌"
            matrix_data.append(row)
        
        matrix_df = pd.DataFrame(matrix_data)
        st.dataframe(matrix_df, use_container_width=True, hide_index=True)
        
        st.caption("✅ = Optimal for this session | ⚪ = Allowed | ❌ = Not optimal")
    else:
        st.info("No active killzones to display matrix.")
    
    st.markdown("---")
    
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
# ==================== System Logs Page (Super Plan 🚀) ====================
elif page == "System Logs":
    st.title("📋 System Logs & Observability")
    
    # Imports
    from src.utils.log_reader import LogReader, DockerLogManager
    import time

    # Create Tabs
    log_tab1, log_tab2, log_tab3 = st.tabs(["🐳 Docker Logs (Live)", "📄 File Logs", "🗄️ Database Events"])
    
    # ------------------ TAB 1: Docker Logs ------------------
    with log_tab1:
        st.subheader("Live Container Logs")
        
        # Helper to manage docker connection
        if 'docker_mgr' not in st.session_state:
            st.session_state.docker_mgr = DockerLogManager()
            
        mgr = st.session_state.docker_mgr
        
        if not mgr.connected:
            st.error(f"Docker Daemon not connected. Ensure /var/run/docker.sock is mounted. Error: {getattr(mgr, 'error', 'Unknown')}")
        else:
            # Controls
            col1, col2, col3 = st.columns([1, 1, 2])
            
            with col1:
                # LIST CONTAINERS
                containers = mgr.list_containers()
                container_names = [c['name'] for c in containers] if containers else []
                
                # Default to a known interesting container if available
                default_idx = 0
                for i, name in enumerate(container_names):
                    if 'trader' in name or 'cv_agent' in name:
                        default_idx = i
                        break
                        
                selected_container = st.selectbox("Select Container", container_names, index=default_idx if container_names else 0)
            
            with col2:
                tail_lines = st.slider("Tail Lines", 50, 2000, 200, step=50, key="docker_tail")
                
            with col3:
                # MASTER TOGGLE FOR PERFORMANCE
                live_logging = st.toggle("🔴/🟢 ENABLE LIVE LOGGING", value=False, help="Enable to stream logs. Disable to save resources.")
                
            if selected_container:
                # Find status
                status = next((c['status'] for c in containers if c['name'] == selected_container), "Unknown")
                status_color = "green" if status == "running" else "red"
                st.caption(f"Status: :{status_color}[{status.upper()}] | ID: {next((c['id'] for c in containers if c['name'] == selected_container), '')}")
                
                if live_logging:
                    # Auto-refresh loop
                    # We use st.empty() to update just the log block
                    log_placeholder = st.empty()
                    
                    try:
                        # Fetch logs
                        logs = mgr.get_logs(selected_container, tail=tail_lines)
                        
                        # Display
                        with log_placeholder.container():
                            st.code(logs, language="text", line_numbers=True)
                            st.caption(f"Last updated: {datetime.now().strftime('%H:%M:%S')}")
                        
                        # Add a manual refresh button below if user wants to force update without loop
                        if st.button("Refresh Now"):
                            st.rerun()
                            
                    except Exception as e:
                        st.error(f"Error fetching logs: {e}")
                else:
                    st.info("⏸️ Live logging is PAUSED to save resources. Toggle the switch above to enable.")

    # ------------------ TAB 2: File Logs ------------------
    with log_tab2:
        st.subheader("Application Log Files")
        
        # List log files
        log_dir = "logs" # Relative to CWD
        try:
            log_files = [f for f in os.listdir(log_dir) if f.endswith('.log')] if os.path.exists(log_dir) else []
        except:
            log_files = []
            
        if not log_files:
            st.warning(f"No log files found in {os.path.abspath(log_dir)}")
        else:
            col1, col2, col3 = st.columns([1, 1, 2])
            with col1:
                selected_file = st.selectbox("Select Log File", log_files, index=0)
            with col2:
                file_tail_lines = st.number_input("Lines to Read", 100, 5000, 500, step=100)
            with col3:
                enable_file_read = st.toggle("Enable File Reading", value=False, key="file_read_toggle")
                
            if selected_file and enable_file_read:
                file_path = os.path.join(log_dir, selected_file)
                
                if st.button("🔄 Reload File"):
                    st.rerun()
                
                lines = LogReader.read_file_tail(file_path, n_lines=file_tail_lines)
                log_content = "\n".join(lines)
                
                st.text_area("Log Content", log_content, height=600)
                
                # Download button
                st.download_button(
                    label="📥 Download Full Log",
                    data=open(file_path, "rb").read(),
                    file_name=selected_file,
                    mime="text/plain"
                )
            elif not enable_file_read:
                st.info("Reading disabled by user.")

    # ------------------ TAB 3: Database Logs ------------------
    with log_tab3:
        st.subheader("Structured Database Events")
        
        level_filter = st.selectbox("Level", ["All", "INFO", "WARNING", "ERROR"], key="db_log_level")
        component_filter = st.selectbox("Component", ["All", "BRIDGE", "TRADER", "ML_ENGINE", "DASHBOARD"], key="db_log_comp")
        
        if st.button("Search Database Logs"):
            logs = db.get_logs(
                level=None if level_filter == "All" else level_filter,
                component=None if component_filter == "All" else component_filter,
                limit=100
            )
            
            if logs:
                df = pd.DataFrame(logs)
                st.dataframe(df[['created_at', 'level', 'component', 'message']], use_container_width=True)
                
                # Visualization of errors
                if not df.empty:
                    st.markdown("#### Log Level Distribution")
                    st.bar_chart(df['level'].value_counts())
            else:
                st.info("No logs found matching criteria")

# Footer
st.sidebar.markdown("---")
st.sidebar.caption("CV Trading Agent v1.0")
