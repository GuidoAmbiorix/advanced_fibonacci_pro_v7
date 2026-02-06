import streamlit as st
import pandas as pd
import time
from database_manager import DatabaseManager

# Page Config
st.set_page_config(
    page_title="Portfolio Governor Brain",
    page_icon="🧠",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Initialize DB Manager
@st.cache_resource
def get_db_manager():
    return DatabaseManager()

db = get_db_manager()

# Sidebar
st.sidebar.title("🧠 Governor v3.0")
st.sidebar.markdown(f"**DB Status:** {'🟢 Connected' if db.get_connection() else '🔴 Not Found'}")
if st.sidebar.button("🔄 Refresh Data"):
    st.cache_data.clear()

st.sidebar.markdown("---")
page = st.sidebar.radio("Navigation", ["Dashboard", "Configuration", "Optimization", "Trade Logs", "System Health"])

# Main Layout
if page == "Dashboard":
    st.title("📊 Portfolio Overview")
    
    # 1. High Level Metrics from Configs
    df_configs = db.load_configs()
    
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

elif page == "Optimization":
    st.title("🧠 AI Optimization Engine")
    st.markdown("Use **Optuna** to find the optimal parameters for your portfolio based on recent market data.")
    
    from optimizer import PortfolioOptimizer
    optimizer = PortfolioOptimizer(db)
    
    df_configs = db.load_configs()
    if not df_configs.empty:
        symbols = df_configs['symbol'].tolist()
        
        col1, col2 = st.columns([3, 1])
        selected_symbol = col1.selectbox("Select Symbol to Optimize", symbols)
        
        if col2.button("🚀 Run Optimization"):
            with st.spinner(f"Optimizing {selected_symbol}..."):
                best_params = optimizer.run_optimization(selected_symbol)
                
                if best_params:
                    # Store in session state
                    st.session_state['opt_results'] = {
                        'symbol': selected_symbol,
                        'params': best_params,
                        'time': time.time()
                    }
                    st.success(f"✅ Optimization Complete! Best Params: {best_params}")
                else:
                    st.error("Optimization failed. Check if Market Data is synced (Recompile EA).")

        # Display results and Apply button from Session State
        if 'opt_results' in st.session_state and st.session_state['opt_results']['symbol'] == selected_symbol:
            res = st.session_state['opt_results']
            st.info(f"Last Optimization for {res['symbol']}: {res['params']}")
            
            if st.button("💾 Apply Parameters to DB"):
                success, msg = optimizer.update_db(res['symbol'], res['params'])
                if success:
                    st.success(msg)
                    # creating a clear state so the user can run optimization again if needed
                    del st.session_state['opt_results']
                    time.sleep(1)
                    st.rerun()
                else:
                    st.error(msg)
                    st.warning("Ensure the Database Schema matches the Optimizer Config. You may need to delete the SQLite file to force a schema update.")
                    
        st.info("💡 Note: The Optimizer uses recent history stored in 'MarketData'. Ensure you have run the EA to populate this data.")
    else:
        st.warning("No symbols found.")
        
elif page == "Configuration":
    st.title("⚙️ Symbol Configuration")
    st.markdown("View and Edit Symbol Parameters stored in SQLite.")
    
    df = db.load_configs()
    if not df.empty:
        edited_df = st.data_editor(
            df, 
            num_rows="dynamic", 
            use_container_width=True,
            key="symbol_config_editor"
        )
        
        if st.button("💾 Save Configurations"):
            success_count = 0
            for index, row in edited_df.iterrows():
                # Convert row keys to dict
                config_dict = row.to_dict()
                if db.save_config(config_dict):
                    success_count += 1
            
            st.success(f"✅ Successfully saved {success_count} configurations to Database!")
            time.sleep(1)
            st.rerun()
    else:
        st.info("No configurations available.")

elif page == "Trade Logs":
    st.title("📜 Trade History")
    
    # Reusing direct connection for custom query flexibility here for now, 
    # or extend DB Manager. Let's keep it simple.
    conn = db.get_connection()
    if conn:
        tables = pd.read_sql("SELECT name FROM sqlite_master WHERE type='table';", conn)
        st.write("Available Tables:", tables)
        
        selected_table = st.selectbox("Select Table to Inspect", tables['name'].tolist())
        if selected_table:
            try:
                df_table = pd.read_sql(f"SELECT * FROM {selected_table} ORDER BY rowid DESC LIMIT 100", conn)
                st.dataframe(df_table, use_container_width=True)
            except:
                st.error("Could not read table.")
        conn.close()

elif page == "System Health":
    st.title("💓 System Heartbeat")

    # Get current timestamp
    current_time = int(time.time())

    # Get Governor State
    conn = db.get_connection()
    df_state = pd.read_sql("SELECT * FROM GovernorState", conn) if conn else pd.DataFrame()

    # Get trade statistics
    df_stats = pd.DataFrame()
    if conn:
        try:
             df_stats = pd.read_sql("""
                SELECT
                    COUNT(*) as total_trades,
                    SUM(CASE WHEN profit > 0 THEN 1 ELSE 0 END) as winning_trades,
                    SUM(CASE WHEN profit < 0 THEN 1 ELSE 0 END) as losing_trades,
                    SUM(profit) as total_profit,
                    AVG(profit) as avg_profit,
                    MAX(close_time) as last_trade_time
                FROM Trades
            """, conn)
        except:
             pass

    # System Status Indicators
    st.subheader("🔍 System Status")

    if not df_stats.empty and df_stats.iloc[0]['last_trade_time']:
        last_trade_time = int(df_stats.iloc[0]['last_trade_time'])
        time_since_last_trade = current_time - last_trade_time
        
        # Status logic
        if time_since_last_trade < 3600:
            status_text = "Active 🟢"
        elif time_since_last_trade < 86400:
            status_text = "Idle 🟡"
        else:
            status_text = "Inactive 🔴"
            
        st.metric("System Status", status_text)
        
    # Governor State
    if not df_state.empty:
        st.subheader("⚙️ Governor State")
        st.dataframe(df_state, use_container_width=True)

    # System Logs (Using Manager)
    st.subheader("📝 System Logs")
    
    # Auto-refresh mechanism
    if st.checkbox("Auto-refresh Logs (5s)", value=False):
        time.sleep(5)
        st.rerun()
    
    df_logs = db.get_logs(limit=200)
    
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
        
    if conn: conn.close()
