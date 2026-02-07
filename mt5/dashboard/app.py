import streamlit as st
import sqlite3
import pandas as pd
import os
import time
from optimizer import PortfolioOptimizer
from database_manager import DatabaseManager
from optimizer_config import OPTIMIZATION_SETTINGS

# Page Config
st.set_page_config(
    page_title="Portfolio Governor Brain",
    page_icon="🧠",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Constants
DB_PATH = os.getenv("DB_PATH", "PortfolioGovernor.sqlite")

# Database Connection
@st.cache_resource
def get_connection():
    # Helper to check if file exists
    if not os.path.exists(DB_PATH):
        return None
    return sqlite3.connect(DB_PATH, check_same_thread=False)

def load_data(query):
    conn = get_connection()
    if conn:
        try:
            return pd.read_sql(query, conn)
        except Exception as e:
            st.error(f"Error reading DB: {e}")
            return pd.DataFrame()
    return pd.DataFrame()

# Sidebar
st.sidebar.title("🧠 Governor v3.0")
st.sidebar.markdown(f"**DB Status:** {'🟢 Connected' if os.path.exists(DB_PATH) else '🔴 Not Found'}")
if st.sidebar.button("🔄 Refresh Data"):
    st.cache_data.clear()

st.sidebar.markdown("---")
page = st.sidebar.radio("Navigation", ["Dashboard", "AI Optimization", "Configuration", "Trade Logs", "System Health"])

# Main Layout
if page == "Dashboard":
    st.title("📊 Portfolio Overview")
    
    # 1. High Level Metrics from Configs
    df_configs = load_data("SELECT * FROM SymbolConfigs")
    
    if not df_configs.empty:
        col1, col2, col3, col4 = st.columns(4)
        col1.metric("Active Pairs", len(df_configs))
        col2.metric("Avg Risk Base", f"{df_configs['risk_base'].mean():.2f}%")
        col3.metric("Adaptive Risk", f"{len(df_configs[df_configs['enable_adaptive_risk'] == 1])}")
        col4.metric("Max Positions", df_configs['max_positions'].sum())

        st.subheader("🔥 Active Symbols & Confluence")
        st.dataframe(
            df_configs[['symbol', 'magic_number', 'risk_base', 'fixed_tp_r', 'min_confluence_entry']].style.format({'risk_base': '{:.2f}%', 'fixed_tp_r': '{:.1f}R'}),
            use_container_width=True
        )
    else:
        st.warning("No Symbol Configurations found in Database.")

elif page == "AI Optimization":
    st.title("🧠 AI Optimization Engine")
    st.markdown("Use Optuna to find the optimal parameters for your portfolio based on recent market data.")

    # Initialize database manager
    db_manager = DatabaseManager(DB_PATH)

    # Load available symbols
    df_configs = load_data("SELECT symbol FROM SymbolConfigs")

    if df_configs.empty:
        st.error("❌ No symbols configured in database. Please add symbols first.")
    else:
        available_symbols = df_configs['symbol'].tolist()

        st.subheader("Select Symbol to Optimize")
        selected_symbol = st.selectbox(
            "Symbol",
            available_symbols,
            help="Choose the currency pair to optimize"
        )

        col1, col2, col3 = st.columns(3)
        with col1:
            st.metric("Optimization Trials", OPTIMIZATION_SETTINGS["n_trials"])
        with col2:
            st.metric("Training Days", OPTIMIZATION_SETTINGS["train_days"])
        with col3:
            st.metric("Target Metric", OPTIMIZATION_SETTINGS["target_metric"].upper())

        st.info("💡 Note: The Optimizer uses recent history stored in 'MarketData'. Ensure you have run the EA to populate this data.")

        # Load current configuration for selected symbol
        current_config_df = load_data(f"SELECT * FROM SymbolConfigs WHERE symbol='{selected_symbol}'")

        if not current_config_df.empty:
            st.subheader("📊 Current Configuration")
            current_config = current_config_df.iloc[0].to_dict()

            # Display key parameters
            key_params = ['risk_base', 'fixed_tp_r', 'rsi_period', 'ema_period',
                         'trail_start_r', 'trail_atr_mult', 'min_confluence_entry']

            cols = st.columns(len(key_params))
            for i, param in enumerate(key_params):
                if param in current_config:
                    cols[i].metric(param.replace('_', ' ').title(), f"{current_config[param]}")

        st.markdown("---")

        # Optimization controls
        if 'optimization_running' not in st.session_state:
            st.session_state.optimization_running = False
        if 'optimization_results' not in st.session_state:
            st.session_state.optimization_results = None

        col_btn1, col_btn2 = st.columns([1, 3])

        with col_btn1:
            if st.button("🚀 Start Optimization", disabled=st.session_state.optimization_running, type="primary"):
                st.session_state.optimization_running = True
                st.session_state.optimization_results = None

                # Create progress indicators
                progress_bar = st.progress(0)
                status_text = st.empty()

                try:
                    status_text.text(f"🔍 Loading market data for {selected_symbol}...")
                    progress_bar.progress(10)

                    # Check if market data exists
                    df_market = db_manager.get_market_data(selected_symbol, 5, limit=5000)

                    if df_market.empty or len(df_market) < 100:
                        st.error(f"❌ Insufficient market data for {selected_symbol}. Please run the EA to collect data.")
                        st.session_state.optimization_running = False
                    else:
                        st.success(f"✅ Loaded {len(df_market)} data points")
                        progress_bar.progress(20)

                        status_text.text(f"🧠 Running Optuna optimization ({OPTIMIZATION_SETTINGS['n_trials']} trials)...")

                        # Run optimization
                        optimizer = PortfolioOptimizer(db_manager)
                        best_params = optimizer.run_optimization(selected_symbol)

                        progress_bar.progress(80)

                        if best_params:
                            status_text.text("💾 Saving results to database...")

                            # Update database
                            success, message = optimizer.update_db(selected_symbol, best_params)

                            progress_bar.progress(100)

                            if success:
                                st.session_state.optimization_results = {
                                    'symbol': selected_symbol,
                                    'best_params': best_params,
                                    'message': message,
                                    'timestamp': time.time()
                                }

                                # Log event
                                db_manager.log_event("Optimizer", "INFO",
                                    f"Optimization completed for {selected_symbol}")

                                status_text.text("✅ Optimization complete!")
                                st.success(message)

                                # Clear cache to reload data
                                st.cache_data.clear()

                            else:
                                st.error(f"❌ Failed to save results: {message}")
                        else:
                            st.error("❌ Optimization failed to produce results")

                except Exception as e:
                    st.error(f"❌ Optimization error: {str(e)}")
                    import traceback
                    st.code(traceback.format_exc())

                finally:
                    st.session_state.optimization_running = False

        with col_btn2:
            if st.button("🔄 Refresh Data"):
                st.cache_data.clear()
                st.rerun()

        # Display optimization results
        if st.session_state.optimization_results:
            st.markdown("---")
            st.subheader("✨ Optimization Results")

            results = st.session_state.optimization_results

            st.success(f"✅ {results['message']}")

            # Load updated configuration
            updated_config_df = load_data(f"SELECT * FROM SymbolConfigs WHERE symbol='{results['symbol']}'")

            if not updated_config_df.empty:
                updated_config = updated_config_df.iloc[0].to_dict()

                # Before/After Comparison
                st.subheader("📈 Parameter Changes")

                comparison_data = []
                for param, new_value in results['best_params'].items():
                    old_value = current_config.get(param, 'N/A')

                    if old_value != 'N/A' and old_value != new_value:
                        try:
                            if isinstance(new_value, (int, float)) and isinstance(old_value, (int, float)):
                                delta = ((new_value - old_value) / old_value * 100) if old_value != 0 else 0
                                delta_str = f"{delta:+.1f}%"
                            else:
                                delta_str = "Changed"
                        except:
                            delta_str = "Changed"
                    else:
                        delta_str = "No change"

                    comparison_data.append({
                        'Parameter': param,
                        'Old Value': f"{old_value}",
                        'New Value': f"{new_value}",
                        'Change': delta_str
                    })

                df_comparison = pd.DataFrame(comparison_data)
                st.dataframe(df_comparison, use_container_width=True, hide_index=True)

                st.info(f"⏰ Optimized at: {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(results['timestamp']))}")

elif page == "Configuration":
    st.title("⚙️ Symbol Configuration")
    st.markdown("View and Edit Symbol Parameters stored in SQLite.")

    col1, col2 = st.columns([3, 1])
    with col2:
        if st.button("🔄 Reload from Database"):
            st.cache_data.clear()
            st.rerun()

    df = load_data("SELECT * FROM SymbolConfigs")

    if not df.empty:
        st.subheader(f"📋 {len(df)} Symbol(s) Configured")

        # Add optimization status if available from SystemLogs
        try:
            db_manager = DatabaseManager(DB_PATH)
            recent_logs = db_manager.get_logs(limit=50)

            if not recent_logs.empty:
                # Find recent optimization events
                opt_logs = recent_logs[recent_logs['source'] == 'Optimizer']

                if not opt_logs.empty:
                    st.info(f"🧠 Last optimization activity: {opt_logs.iloc[0]['message']}")
        except:
            pass

        # Display editable configuration
        st.data_editor(df, num_rows="dynamic", use_container_width=True)

        st.markdown("---")
        st.caption("💡 Tip: Use the AI Optimization page to automatically tune parameters based on historical data.")

    else:
        st.info("No configurations available.")

elif page == "Trade Logs":
    st.title("📜 Trade History")
    # Placeholder query - assumes we might have a trades table later
    # For now, show structure of DB
    conn = get_connection()
    if conn:
        tables = pd.read_sql("SELECT name FROM sqlite_master WHERE type='table';", conn)
        st.write("Available Tables:", tables)
        
        selected_table = st.selectbox("Select Table to Inspect", tables['name'].tolist())
        if selected_table:
            df_table = load_data(f"SELECT * FROM {selected_table} ORDER BY rowid DESC LIMIT 100")
            st.dataframe(df_table, use_container_width=True)

elif page == "System Health":
    st.title("💓 System Heartbeat")

    # Get current timestamp
    current_time = int(time.time())

    # Get Governor State
    df_state = load_data("SELECT * FROM GovernorState")

    # Get trade statistics
    df_stats = load_data("""
        SELECT
            COUNT(*) as total_trades,
            SUM(CASE WHEN profit > 0 THEN 1 ELSE 0 END) as winning_trades,
            SUM(CASE WHEN profit < 0 THEN 1 ELSE 0 END) as losing_trades,
            SUM(profit) as total_profit,
            AVG(profit) as avg_profit,
            MAX(close_time) as last_trade_time
        FROM Trades
    """)

    # System Status Indicators
    st.subheader("🔍 System Status")

    if not df_stats.empty and df_stats.iloc[0]['last_trade_time']:
        last_trade_time = int(df_stats.iloc[0]['last_trade_time'])
        time_since_last_trade = current_time - last_trade_time

        # Status indicator based on last activity
        if time_since_last_trade < 3600:  # Less than 1 hour
            status_color = "🟢"
            status_text = "Active"
        elif time_since_last_trade < 86400:  # Less than 1 day
            status_color = "🟡"
            status_text = "Idle"
        else:
            status_color = "🔴"
            status_text = "Inactive"

        col1, col2, col3, col4 = st.columns(4)
        col1.metric("System Status", f"{status_color} {status_text}")
        col2.metric("Last Trade", f"{time_since_last_trade // 60} min ago" if time_since_last_trade < 3600 else f"{time_since_last_trade // 3600} hrs ago")
        col3.metric("DB Status", "🟢 Connected")

        df_symbol_count = load_data("SELECT COUNT(*) as count FROM SymbolConfigs")
        symbol_count = int(df_symbol_count.iloc[0]['count']) if not df_symbol_count.empty else 0
        col4.metric("Total Symbols", symbol_count)

    # Trading Performance Metrics
    st.subheader("📊 Trading Performance")

    if not df_stats.empty:
        total = int(df_stats.iloc[0]['total_trades'])
        wins = int(df_stats.iloc[0]['winning_trades'])
        losses = int(df_stats.iloc[0]['losing_trades'])
        win_rate = (wins / total * 100) if total > 0 else 0

        col1, col2, col3, col4, col5 = st.columns(5)
        col1.metric("Total Trades", total)
        col2.metric("Winning", wins, delta=f"{win_rate:.1f}%")
        col3.metric("Losing", losses, delta=f"{100-win_rate:.1f}%", delta_color="inverse")
        col4.metric("Total P/L", f"${df_stats.iloc[0]['total_profit']:.2f}", delta="Cumulative")
        col5.metric("Avg P/L", f"${df_stats.iloc[0]['avg_profit']:.2f}", delta="Per Trade")

    # Symbol Activity Breakdown
    st.subheader("📈 Symbol Activity")

    df_symbol_stats = load_data("""
        SELECT
            symbol,
            COUNT(*) as trades,
            SUM(CASE WHEN profit > 0 THEN 1 ELSE 0 END) as wins,
            SUM(profit) as total_profit,
            AVG(profit) as avg_profit,
            MAX(close_time) as last_trade
        FROM Trades
        GROUP BY symbol
        ORDER BY total_profit DESC
    """)

    if not df_symbol_stats.empty:
        df_symbol_stats['win_rate'] = (df_symbol_stats['wins'] / df_symbol_stats['trades'] * 100).round(1)
        st.dataframe(
            df_symbol_stats[['symbol', 'trades', 'wins', 'win_rate', 'total_profit', 'avg_profit']].style.format({
                'win_rate': '{:.1f}%',
                'total_profit': '${:.2f}',
                'avg_profit': '${:.2f}'
            }),
            use_container_width=True
        )

    # Recent Activity Log
    st.subheader("📜 Recent Activity")

    df_recent = load_data("""
        SELECT
            ticket,
            symbol,
            DATETIME(entry_time, 'unixepoch') as entry_time,
            DATETIME(close_time, 'unixepoch') as close_time,
            type,
            lots,
            profit,
            magic
        FROM Trades
        ORDER BY close_time DESC
        LIMIT 15
    """)

    if not df_recent.empty:
        st.dataframe(
            df_recent.style.format({'lots': '{:.2f}', 'profit': '${:.2f}'}),
            use_container_width=True
        )
    else:
        st.info("No recent trading activity.")

    # Governor State
    if not df_state.empty:
        st.subheader("⚙️ Governor State")
        st.dataframe(df_state, use_container_width=True)

    # System Logs
    st.subheader("📝 System Logs")
    
    # Auto-refresh mechanism
    if st.checkbox("Auto-refresh Logs (5s)", value=False):
        time.sleep(5)
        st.rerun()
    
    df_logs = load_data("SELECT * FROM SystemLogs ORDER BY time DESC LIMIT 200")
    
    if not df_logs.empty:
        # Convert timestamp
        df_logs['time'] = pd.to_datetime(df_logs['time'], unit='s')
        
        # Color coding
        def color_row(row):
            if row['level'] == 'ERROR':
                return ['background-color: #ffcccc'] * len(row)
            elif row['source'] == 'Heartbeat':
                return ['background-color: #e6f3ff'] * len(row)
            return [''] * len(row)
            
        st.dataframe(
            df_logs[['time', 'source', 'level', 'message']].style.apply(color_row, axis=1),
            use_container_width=True,
            height=400
        )
    else:
        st.info("No system logs found yet. Waiting for Governor startup...")
