"""
MT5 Portfolio Manager - Streamlit Monitoring Dashboard
Main application file
"""

import streamlit as st
from streamlit_autorefresh import st_autorefresh
from datetime import datetime
import sys
import os

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))

from utils.db_reader import DatabaseReader
from components import (account_overview, positions, trade_history, symbol_metrics,
                        risk_metrics, performance_analytics, signal_monitor,
                        system_health, pl_calendar, time_analysis)

# Page configuration
st.set_page_config(
    layout="wide",
    page_title="MT5 Portfolio Monitor",
    page_icon="📊",
    initial_sidebar_state="expanded"
)

# Theme management
if 'theme' not in st.session_state:
    st.session_state.theme = 'light'

# Custom CSS for better styling with theme support
if st.session_state.theme == 'dark':
    st.markdown("""
    <style>
        .main > div {
            padding-top: 2rem;
            background-color: #0e1117;
            color: #fafafa;
        }
        .stMetric {
            background-color: #262730;
            padding: 10px;
            border-radius: 5px;
        }
        h1 {
            color: #4da6ff;
        }
        h2 {
            color: #5dade2;
            margin-top: 1rem;
        }
        .stAlert {
            margin-top: 0.5rem;
            margin-bottom: 0.5rem;
        }
        [data-testid="stSidebar"] {
            background-color: #262730;
        }
    </style>
    """, unsafe_allow_html=True)
else:
    st.markdown("""
    <style>
        .main > div {
            padding-top: 2rem;
        }
        .stMetric {
            background-color: #f0f2f6;
            padding: 10px;
            border-radius: 5px;
        }
        h1 {
            color: #1f77b4;
        }
        h2 {
            color: #2E86AB;
            margin-top: 1rem;
        }
        .stAlert {
            margin-top: 0.5rem;
            margin-bottom: 0.5rem;
        }
    </style>
    """, unsafe_allow_html=True)

# Initialize session state for auto-refresh
if 'last_refresh' not in st.session_state:
    st.session_state.last_refresh = datetime.now()

# Sidebar
with st.sidebar:
    st.title("📊 MT5 Portfolio Monitor")
    st.write("Real-time trading dashboard")

    st.divider()

    # Theme toggle
    st.subheader("⚙️ Settings")

    theme_options = {"Light": "light", "Dark": "dark"}
    current_theme_label = "Dark" if st.session_state.theme == "dark" else "Light"

    selected_theme = st.selectbox(
        "Theme",
        options=list(theme_options.keys()),
        index=list(theme_options.values()).index(st.session_state.theme),
        key="theme_selector"
    )

    if theme_options[selected_theme] != st.session_state.theme:
        st.session_state.theme = theme_options[selected_theme]
        st.rerun()

    st.divider()

    # Refresh controls
    st.subheader("Refresh Settings")

    auto_refresh = st.checkbox("Auto-refresh", value=True, help="Automatically refresh data every 5 seconds")

    if st.button("🔄 Refresh Now", use_container_width=True):
        st.session_state.last_refresh = datetime.now()
        st.rerun()

    st.caption(f"Last updated: {st.session_state.last_refresh.strftime('%Y-%m-%d %H:%M:%S')}")

    st.divider()

    # Date range selector
    st.subheader("Time Range")
    date_range = st.selectbox(
        "Select period",
        ["1D", "7D", "30D", "90D", "All"],
        index=1,
        help="Time range for trade history"
    )

    st.divider()

    # Database info
    st.subheader("Database Info")
    db_path = os.environ.get('DB_PATH', 'Using default path')
    st.caption(f"Path: {db_path}")

    st.divider()

    # Info
    st.markdown("""
    ### Features
    - 📊 Real-time account overview
    - 📈 Open positions monitoring
    - 📜 Trade history & analysis
    - 🎯 Symbol performance metrics
    - ⚠️ Risk & exposure tracking

    ### About
    MT5 Portfolio Governor monitoring dashboard built with Streamlit.
    Reads data from MT5 SQLite database.
    """)

# Auto-refresh logic
if auto_refresh:
    # Refresh every 5 seconds (5000 milliseconds)
    count = st_autorefresh(interval=5000, key="datarefresh")
    st.session_state.last_refresh = datetime.now()

# Main content
st.title("MT5 Portfolio Manager Dashboard")

# Initialize database reader
try:
    db = DatabaseReader()

    # Check if we can connect
    account_summary = db.get_account_summary()

    if account_summary.get('balance', 0) == 0 and account_summary.get('equity', 0) == 0:
        st.warning("⚠️ Dashboard is running but no data found in database. Make sure MT5 is running and writing to the database.")

except Exception as e:
    st.error(f"❌ Could not connect to database: {e}")
    st.info("""
    ### Troubleshooting
    1. Make sure MT5 container is running
    2. Check that database path is correctly mounted
    3. Verify MT5 is writing to PortfolioGovernor.sqlite
    4. Check DB_PATH environment variable
    """)
    st.stop()

# Row 0: System Health Monitor
try:
    system_health.render(db)
except Exception as e:
    st.error(f"Error rendering system health: {e}")

# Row 1: Account Overview
try:
    account_overview.render(db)
except Exception as e:
    st.error(f"Error rendering account overview: {e}")

# Row 2: Live Signal Monitor
try:
    signal_monitor.render(db, hours=2)
except Exception as e:
    st.error(f"Error rendering signal monitor: {e}")

# Row 3: Open Positions
try:
    positions.render(db)
except Exception as e:
    st.error(f"Error rendering positions: {e}")

# Row 4: P/L Calendar
try:
    pl_calendar.render(db)
except Exception as e:
    st.error(f"Error rendering P/L calendar: {e}")

# Row 5: Symbol Metrics
try:
    symbol_metrics.render(db)
except Exception as e:
    st.error(f"Error rendering symbol metrics: {e}")

# Row 6: Performance Analytics
try:
    performance_analytics.render(db)
except Exception as e:
    st.error(f"Error rendering performance analytics: {e}")

# Row 7: Time Analysis
try:
    time_analysis.render(db)
except Exception as e:
    st.error(f"Error rendering time analysis: {e}")

# Row 8: Risk Metrics
try:
    risk_metrics.render(db)
except Exception as e:
    st.error(f"Error rendering risk metrics: {e}")

# Row 9: Trade History
try:
    trade_history.render(db, date_range)
except Exception as e:
    st.error(f"Error rendering trade history: {e}")

# Footer
st.divider()
st.caption("MT5 Portfolio Manager Dashboard | Built with Streamlit | Data from PortfolioGovernor.sqlite")
