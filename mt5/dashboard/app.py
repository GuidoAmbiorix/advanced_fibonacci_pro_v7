import streamlit as st
import sqlite3
import pandas as pd
import os
import time

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
page = st.sidebar.radio("Navigation", ["Dashboard", "Configuration", "Trade Logs", "System Health"])

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
        
elif page == "Configuration":
    st.title("⚙️ Symbol Configuration")
    st.markdown("View and Edit Symbol Parameters stored in SQLite.")
    
    df = load_data("SELECT * FROM SymbolConfigs")
    if not df.empty:
        st.data_editor(df, num_rows="dynamic", use_container_width=True)
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
