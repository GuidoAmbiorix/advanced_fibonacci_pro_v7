import streamlit as st
import pandas as pd
import time
from datetime import datetime
import os
import sys

# Add project root to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from execution.mt5_bridge import MT5Bridge

# Page Config
st.set_page_config(
    page_title="Portfolio Engine",
    page_icon="📈",
    layout="wide",
    initial_sidebar_state="expanded",
)

# Initialize Bridge connection
@st.cache_resource
def get_bridge():
    bridge = MT5Bridge()
    return bridge

bridge = get_bridge()

# --- SIDEBAR ---
with st.sidebar:
    st.header("🔌 Connection")
    if st.button("Connect/Refresh"):
        with st.spinner("Connecting..."):
            if bridge.connect():
                st.success("Connected!")
            else:
                st.error("Connection Failed")
                
    st.caption(f"Status: {'✅ Online' if bridge.connected else '🔴 Offline'}")
    
    # Try auto-connect if offline
    if not bridge.connected:
        if bridge.connect():
            st.rerun()

    st.divider()
    st.header("🤖 Bot Control")
    launch_sym = st.selectbox("Symbol to Launch", ["XAUUSD", "EURUSD"], key="launch_sym")
    
    if st.button("🚀 Launch Portfolio Governor", use_container_width=True):
        with st.spinner(f"Launching on {launch_sym}..."):
            res = bridge.launch_bot(launch_sym)
            if "Success" in res:
                st.success(res)
            else:
                st.error(res)
            time.sleep(2)
            st.rerun()

    c_start, c_stop = st.columns(2)
    if c_start.button("🟢 Resume", help="Turn ON Governor Trading (Live)"):
        if bridge.set_governor_status(True):
            st.success("Governor Resumed")
            time.sleep(1)
            st.rerun()
            
    if c_stop.button("🔴 Pause", type="primary", help="Turn OFF Governor Trading (Live)"):
        if bridge.set_governor_status(False):
            st.error("Governor Paused")
            time.sleep(1)
            st.rerun()

    st.divider()
    st.header("⚙️ Settings")
    auto_refresh = st.toggle("Auto-Refresh Data", value=True)
    refresh_rate = st.slider("Rate (sec)", 1, 10, 2)
    
    st.divider()
    st.header("🛑 Danger Zone")
    if st.button("CLOSE ALL POSITIONS", type="primary"):
        count = 0 
        positions = bridge.get_positions()
        for pos in positions:
            # Implement close logic here or call bridge method
            # bridge.close_position(pos['ticket'])
            count += 1
        st.warning(f"Close signal sent for {count} positions (Demo stub)")

# Main Dashboard
st.title("Institutional Dashboard")

# 1. Metrics Row
col1, col2, col3, col4 = st.columns(4)

acc = bridge.get_account_info()
if acc:
    col1.metric("Equity", f"${acc.get('equity', 0):,.2f}")
    col2.metric("Balance", f"${acc.get('balance', 0):,.2f}")
    col3.metric("Profit", f"${acc.get('profit', 0):,.2f}", 
                delta_color="normal" if acc.get('profit', 0) >= 0 else "inverse")
    col4.metric("Margin Free", f"${acc.get('margin_free', 0):,.2f}")
else:
    col1.metric("Equity", "---")
    col2.metric("Balance", "---")
    col3.metric("Profit", "---")
    col4.metric("Margin Free", "---")

# Governor Status (MQL5 Integration)
st.divider()
st.subheader("🧠 Portfolio Governor")
gov = bridge.get_governor_status()

g1, g2, g3, g4 = st.columns(4)
g1.metric("Risk Multiplier", f"{gov.get('risk_mult', 0)*100:.0f}%", 
          help="Global risk scaling factor controlled by the Brain")
g2.metric("Drawdown", f"{gov.get('drawdown', 0):.2f}%", delta=None)
g3.metric("Total Exposure", f"{gov.get('exposure', 0):.2f}%")
g4.metric("Rolling PF", f"{gov.get('rolling_pf', 0):.2f}")

if gov.get('active', 0) == 0:
    st.caption("⚠️ Governor Offline (Run 'Portfolio_Governor.mq5' in MT5)")
else:
    st.caption("✅ Governor Active - Monitoring Risk")

st.divider()

# 2. Charts
st.subheader("Live Market Data")
symbols = ['XAUUSD', 'EURUSD'] # Could be dynamic
tabs = st.tabs(symbols)

# Import here to avoid top-level dependency issues during hot-reload
try:
    from streamlit_lightweight_charts_ntf import renderLightweightCharts
except ImportError:
    st.error("Please install streamlit-lightweight-charts-ntf")
    renderLightweightCharts = None

for i, sym in enumerate(symbols):
    with tabs[i]:
        df = bridge.get_ohlcv(sym, timeframe='M15', count=200)
        if df is not None and not df.empty and renderLightweightCharts:
            # Format data for lightweight-charts
            # Needs list of dicts: time (unix), open, high, low, close
            chart_data = []
            for t, row in df.iterrows():
                # t is Timestamp (index)
                chart_data.append({
                    "time": int(t.timestamp()),
                    "open": row['open'],
                    "high": row['high'],
                    "low": row['low'],
                    "close": row['close']
                })

            chartOptions = {
                "layout": {
                    "textColor": 'white',
                    "background": {"type": 'solid', "color": '#0E1117'}
                },
                "grid": {
                    "vertLines": {"color": "#333"},
                    "horzLines": {"color": "#333"},
                }
            }
            
            seriesCandlestickChart = [{
                "seriesType": "Candlestick",
                "data": chart_data,
                "options": {
                    "upColor": '#26a69a', 
                    "downColor": '#ef5350', 
                    "borderVisible": False, 
                    "wickUpColor": '#26a69a', 
                    "wickDownColor": '#ef5350'
                }
            }]

            renderLightweightCharts(
                seriesCandlestickChart, 
                chartOptions, 
                height=500
            )
        else:
            if not renderLightweightCharts:
                st.warning("Library missing.")
            else:
                st.warning(f"No data for {sym}")

# 3. Active Positions
st.subheader("Active Positions")
positions = bridge.get_positions()
if positions:
    df_pos = pd.DataFrame(positions)
    st.dataframe(
        df_pos,
        use_container_width=True,
        column_config={
            "ticket": st.column_config.NumberColumn("Ticket", format="%d"),
            "time": st.column_config.DatetimeColumn("Time", format="D MMM, HH:mm"),
            "profit": st.column_config.NumberColumn("Profit", format="$%.2f"),
        }
    )
else:
    st.info("No active positions")

# Auto-Refresh Logic
if auto_refresh:
    time.sleep(refresh_rate)
    st.rerun()

# --- BACKTESTING PAGE ---
with st.sidebar:
    st.divider()
    st.header("🧪 Strategy Tester")
    show_tester = st.toggle("Show Tester Mode", value=False)

if show_tester:
    st.markdown("## 🧪 Custom Strategy Tester")
    
    with st.form("backtest_form"):
        c1, c2, c3 = st.columns(3)
        bt_symbol = c1.selectbox("Symbol", ["XAUUSD", "EURUSD"])
        bt_period = c2.selectbox("Period", ["M15", "H1", "H4"])
        bt_model = c3.selectbox("Model", ["OHLC (Fast)", "Every Tick (Precise)"], index=0)
        
        c4, c5 = st.columns(2)
        bt_start = c4.date_input("Start Date", datetime(2024, 1, 1))
        bt_end = c5.date_input("End Date", datetime(2024, 1, 31))
        
        run_bt = st.form_submit_button("🚀 Run Backtest")
        
    if run_bt:
        from execution.automation_manager import AutomationManager
        am = AutomationManager()
        
        # 1. Generate INI config
        model_int = 1 if "OHLC" in bt_model else 0
        ini_content = am.generate_ini(
            symbol=bt_symbol,
            period=bt_period,
            date_from=bt_start.strftime("%Y.%m.%d"),
            date_to=bt_end.strftime("%Y.%m.%d"),
            model=model_int
        )
        
        # 2. Run Remote Backtest
        with st.spinner("Running Backtest on Server... (This may take a while)"):
            logs = bridge.run_backtest(ini_content)
            
        st.text_area("Server Logs", logs, height=150)
        
        # 3. Parse Report
        if "Exit Code: 0" in logs or "Exit Code" in logs: # Checking general completion
             st.success("Backtest Completed!")
             df_res = am.parse_report()
             if not df_res.empty:
                 st.dataframe(df_res)
                 # TODO: Add Equity Curve Plot here using df_res
             else:
                 st.warning("No trades found in report or parsing failed.")
