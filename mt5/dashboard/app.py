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
        col3.metric("Adaptive Risk", f"{len(df_configs[df_configs['enableAdaptiveRisk'] == 1])}")
        col4.metric("Strategies", df_configs['strategy_mode'].nunique())
        
        st.subheader("🔥 Active Symbols & Confluence")
        st.dataframe(
            df_configs[['symbol', 'magic_number', 'risk_base', 'fixed_tp_r', 'strategy_mode']].style.format({'risk_base': '{:.2f}%', 'fixed_tp_r': '{:.1f}R'}),
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
    st.markdown("Monitoring system logs and heartbeat signals.")
    # Assuming we create a Heartbeat table later
    st.info("Heartbeat monitoring module pending integration.")
