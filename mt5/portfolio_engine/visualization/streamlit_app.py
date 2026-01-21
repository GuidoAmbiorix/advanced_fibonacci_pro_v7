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

# --- MAIN UI ---
st.title("Institutional Dashboard")

# Top Level Tabs
tab_live, tab_backtest, tab_settings = st.tabs(["📈 Live Dashboard", "🧪 strategy Tester", "⚙️ Settings"])

with tab_live:
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
        col1.info("Connecting to MT5...")

    # Governor Status (MQL5 Integration)
    st.divider()
    st.subheader("🧠 Portfolio Governor Status")
    gov = bridge.get_governor_status()

    g1, g2, g3, g4 = st.columns(4)
    g1.metric("Risk Multiplier", f"{gov.get('risk_mult', 0)*100:.0f}%")
    g2.metric("Drawdown", f"{gov.get('drawdown', 0):.2f}%")
    g3.metric("Total Exposure", f"{gov.get('exposure', 0):.2f}%")
    g4.metric("Rolling PF", f"{gov.get('rolling_pf', 0):.2f}")

    if gov.get('active', 0) == 0:
        st.warning("⚠️ Governor Offline (Run 'Portfolio_Governor.mq5' in MT5)")
    
    st.divider()

    # 2. Charts
    st.subheader("Live Market Data")
    symbols_to_show = ['XAUUSD', 'EURUSD']
    chart_tabs = st.tabs(symbols_to_show)

    try:
        from streamlit_lightweight_charts_ntf import renderLightweightCharts
    except ImportError:
        renderLightweightCharts = None

    for i, sym in enumerate(symbols_to_show):
        with chart_tabs[i]:
            df = bridge.get_ohlcv(sym, timeframe='M15', count=100)
            if df is not None and not df.empty and renderLightweightCharts:
                chart_data = []
                for t, row in df.iterrows():
                    chart_data.append({
                        "time": int(t.timestamp()),
                        "open": row['open'],
                        "high": row['high'],
                        "low": row['low'],
                        "close": row['close']
                    })

                chartOptions = {
                    "height": 400,
                    "layout": {"textColor": 'white', "background": {"type": 'solid', "color": '#0E1117'}},
                    "grid": {"vertLines": {"color": "#333"}, "horzLines": {"color": "#333"}}
                }
                
                series = [{
                    "seriesType": "Candlestick",
                    "data": chart_data,
                    "options": {"upColor": '#26a69a', "downColor": '#ef5350'}
                }]

                renderLightweightCharts([{"chart": chartOptions, "series": series}], key=f"chart_{sym}")
            else:
                st.info(f"Waiting for {sym} data...")
                if df is not None and not df.empty:
                    st.line_chart(df[['close']])

    # 3. Active Positions
    st.subheader("Active Positions")
    positions = bridge.get_positions()
    if positions:
        st.dataframe(pd.DataFrame(positions), use_container_width=True)
    else:
        st.info("No active positions found with Magic Number " + str(bridge.magic_number))

with tab_backtest:
    st.header("🧪 Strategy Tester (Remote)")
    st.markdown("""
    Run backtests on the remote MT5 server. This will generate a report and show you the results here.
    """)
    
    with st.form("backtest_form_v2"):
        c1, c2, c3 = st.columns(3)
        bt_symbol = c1.selectbox("Symbol", ["XAUUSD", "EURUSD", "GBPUSD"])
        bt_period = c2.selectbox("Period", ["M15", "H1", "H4"])
        bt_model = c3.selectbox("Model", ["Every Tick (Precise)", "OHLC (Fast)"], index=1)
        
        c4, c5, c6 = st.columns(3)
        bt_start = c4.date_input("Start Date", datetime(2024, 1, 1))
        bt_end = c5.date_input("End Date", datetime(2024, 1, 31))
        bt_deposit = c6.number_input("Initial Deposit", 1000, 100000, 10000)
        
        run_bt = st.form_submit_button("🚀 Start Backtest")
        
    if run_bt:
        from execution.automation_manager import AutomationManager
        am = AutomationManager()
        
        model_int = 1 if "OHLC" in bt_model else 0
        ini_content = am.generate_ini(
            expert="PortfolioManager\\\\Symbol_Engine.mq5",
            symbol=bt_symbol,
            period=bt_period,
            deposit=bt_deposit,
            date_from=bt_start.strftime("%Y.%m.%d"),
            date_to=bt_end.strftime("%Y.%m.%d"),
            model=model_int
        )
        
        with st.status("🛠️ Running Backtest...") as status:
            st.write("Generating config...")
            logs = bridge.run_backtest(ini_content)
            st.write("Parsing results...")
            df_res = am.parse_report()
            status.update(label="Backtest Finished!", state="complete")
            
        if not df_res.empty:
            st.success(f"Backtest completed! Found {len(df_res)} deals.")
            st.dataframe(df_res)
        else:
            st.warning("Backtest finished but no trades were found. Check logs below.")
            with st.expander("Show Server Logs"):
                st.text(logs)

with tab_settings:
    st.header("⚙️ Configuration")
    st.write("Shared Magic Number Range:")
    st.number_input("Base Magic", value=bridge.magic_number, key="magic_base")
    st.divider()
    st.write("Auto-Refresh Settings:")
    if st.button("Manually Sync Data"):
        bridge.connect()
        st.rerun()

# --- SIDEBAR UPDATES ---
with st.sidebar:
    st.divider()
    st.header("🚀 Bot Quick Launch")
    st.info("Attaches Symbol_Engine.mq5 to a new chart")
    symbol_quick = st.selectbox("Symbol", ["XAUUSD", "EURUSD"], key="quick_sym")
    if st.button("🚀 Launch Symbol Engine", use_container_width=True):
         with st.spinner(f"Launching {symbol_quick}..."):
            res = bridge.launch_bot(symbol_quick)
            st.toast(res)
    
    st.divider()
    if st.button("🔴 Emergency Stop (Pause Governor)", type="primary", use_container_width=True):
        bridge.set_governor_status(False)
        st.error("GOVERNOR PAUSED")

# Auto-Refresh Logic (Last line)
if auto_refresh:
    time.sleep(refresh_rate)
    st.rerun()

