import streamlit as st
import sqlite3
import pandas as pd
import os
import time
import json
import numpy as np
from optimizer import PortfolioOptimizer, WalkForwardOptimizer
from database_manager import DatabaseManager
from optimizer_config import OPTIMIZATION_SETTINGS, TIMEFRAMES
from metrics import PerformanceMetrics
from scheduler import get_scheduler

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

# Scheduler Controls
st.sidebar.subheader("⏰ Auto-Optimization")

# Initialize scheduler
scheduler = get_scheduler(DB_PATH)
scheduler_status = scheduler.get_status()

# Initialize session state for scheduler
if 'scheduler_enabled' not in st.session_state:
    st.session_state.scheduler_enabled = scheduler_status['running']

# Display current status
if scheduler_status['running']:
    st.sidebar.success("🟢 Scheduler Active")
    if scheduler_status['next_run']:
        st.sidebar.caption(f"Next run: {scheduler_status['next_run'].strftime('%m-%d %H:%M')}")
else:
    st.sidebar.info("⚪ Scheduler Inactive")

# Scheduler configuration in expander
with st.sidebar.expander("⚙️ Scheduler Settings"):
    schedule_type = st.selectbox(
        "Schedule",
        ["daily", "weekly", "monthly"],
        key="schedule_type"
    )

    col1, col2 = st.columns(2)
    with col1:
        schedule_hour = st.number_input("Hour (UTC)", 0, 23, 2, key="schedule_hour")
    with col2:
        schedule_minute = st.number_input("Minute", 0, 59, 0, key="schedule_minute")

    if schedule_type == "weekly":
        schedule_weekday = st.selectbox(
            "Day",
            ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"],
            key="schedule_weekday"
        )
    else:
        schedule_weekday = "monday"

    if not scheduler_status['running']:
        if st.button("▶️ Start Scheduler", key="start_scheduler"):
            success = scheduler.start_scheduler(
                schedule_type=schedule_type,
                hour=schedule_hour,
                minute=schedule_minute,
                weekday=schedule_weekday
            )
            if success:
                st.session_state.scheduler_enabled = True
                st.success("✅ Scheduler started!")
                st.rerun()
            else:
                st.error("❌ Failed to start scheduler")
    else:
        if st.button("⏸️ Stop Scheduler", key="stop_scheduler"):
            success = scheduler.stop_scheduler()
            if success:
                st.session_state.scheduler_enabled = False
                st.success("✅ Scheduler stopped!")
                st.rerun()

        if st.button("⚡ Run Now", key="run_now"):
            with st.spinner("Running optimization..."):
                scheduler.run_now()
            st.success("✅ Manual optimization triggered!")

st.sidebar.markdown("---")

page = st.sidebar.radio("Navigation", [
    "🔴 Live Control Center",
    "📊 Performance",
    "🧠 Optimization",
    "⚙️ Settings"
])

# Main Layout
if page == "🔴 Live Control Center":
    st.title("🔴 Live Control Center")
    st.caption("Real-time portfolio monitoring and control")

    # Auto-refresh control
    col_ref1, col_ref2 = st.columns([4, 1])
    with col_ref1:
        auto_refresh = st.checkbox("🔄 Auto-refresh (5 sec)", value=False, key="live_auto_refresh")
    with col_ref2:
        if st.button("🔄 Refresh", key="live_refresh_btn"):
            st.rerun()

    if auto_refresh:
        time.sleep(5)
        st.rerun()

    st.markdown("---")

    # ============================================================================
    # TIER 1: PORTFOLIO HEALTH (Top 1/3)
    # ============================================================================
    st.subheader("📊 Portfolio Health")

    # Calculate portfolio metrics
    try:
        # Get recent trades for P&L
        df_trades_today = load_data("""
            SELECT SUM(profit) as daily_pnl, COUNT(*) as trade_count
            FROM Trades
            WHERE close_time > unixepoch('now', '-1 day')
        """)

        # Get current open positions
        df_open_positions = load_data("""
            SELECT COUNT(DISTINCT symbol) as open_count
            FROM Trades
            WHERE close_time IS NULL OR close_time = 0
        """)

        # Get symbol configs for risk calculation
        df_configs = load_data("SELECT * FROM SymbolConfigs")

        # Calculate metrics
        daily_pnl = df_trades_today['daily_pnl'].iloc[0] if not df_trades_today.empty and pd.notna(df_trades_today['daily_pnl'].iloc[0]) else 0
        daily_pnl_pct = (daily_pnl / 10000) * 100 if daily_pnl != 0 else 0  # Assuming 10k account
        open_positions = df_open_positions['open_count'].iloc[0] if not df_open_positions.empty else 0
        total_symbols = len(df_configs) if not df_configs.empty else 10
        avg_risk = df_configs['risk_base'].mean() if not df_configs.empty else 0
        current_risk = open_positions * avg_risk

        # Get latest optimization Sharpe if available
        df_opt_sharpe = load_data("""
            SELECT best_sharpe
            FROM OptimizationRuns
            ORDER BY completed_at DESC
            LIMIT 1
        """)
        portfolio_sharpe = df_opt_sharpe['best_sharpe'].iloc[0] if not df_opt_sharpe.empty else 0

        # Display metrics
        col1, col2, col3, col4, col5 = st.columns(5)

        # Daily P&L
        pnl_delta_color = "normal" if daily_pnl >= 0 else "inverse"
        col1.metric(
            "Daily P&L",
            f"${daily_pnl:.2f}",
            f"{daily_pnl_pct:+.2f}%",
            delta_color=pnl_delta_color
        )

        # Open Positions
        col2.metric(
            "Open Positions",
            f"{open_positions}/{total_symbols}",
            f"{(open_positions/total_symbols*100):.0f}% active" if total_symbols > 0 else "N/A"
        )

        # Current Risk
        risk_status = "🟢" if current_risk < 3 else "🟡" if current_risk < 5 else "🔴"
        col3.metric(
            "Current Risk",
            f"{current_risk:.1f}%",
            f"{risk_status} Max 5%"
        )

        # Portfolio Sharpe
        col4.metric(
            "Portfolio Sharpe",
            f"{portfolio_sharpe:.2f}",
            "From last optimization"
        )

        # Account Status
        status_icon = "🟢 ACTIVE" if open_positions > 0 or df_configs.empty == False else "🟡 IDLE"
        col5.metric(
            "Status",
            status_icon,
            f"{total_symbols} symbols configured"
        )

    except Exception as e:
        st.error(f"Error loading portfolio metrics: {e}")
        # Show empty metrics
        col1, col2, col3, col4, col5 = st.columns(5)
        col1.metric("Daily P&L", "$0.00", "0%")
        col2.metric("Open Positions", "0/10")
        col3.metric("Current Risk", "0%")
        col4.metric("Portfolio Sharpe", "0.00")
        col5.metric("Status", "🔴 ERROR")

    st.markdown("---")

    # ============================================================================
    # TIER 2: SYMBOL ACTIVITY (Middle 1/3)
    # ============================================================================
    st.subheader("📡 Symbol Activity (Real-Time)")

    try:
        # Get latest signals for each symbol
        df_signals = load_data("""
            SELECT
                s1.symbol,
                s1.time,
                datetime(s1.time, 'unixepoch') as signal_time,
                CASE s1.direction
                    WHEN 1 THEN '🟢 BUY'
                    WHEN -1 THEN '🔴 SELL'
                    ELSE '⚪ NONE'
                END as signal,
                printf('%.1f', s1.score) as confluence,
                CASE s1.allowed
                    WHEN 1 THEN '✅ YES'
                    ELSE '❌ NO'
                END as allowed,
                COALESCE(s1.rejection_reason, '-') as reason,
                s1.smc_score,
                s1.fib_score
            FROM Signals s1
            INNER JOIN (
                SELECT symbol, MAX(time) as max_time
                FROM Signals
                WHERE time > unixepoch('now', '-1 hour')
                GROUP BY symbol
            ) s2 ON s1.symbol = s2.symbol AND s1.time = s2.max_time
            ORDER BY s1.score DESC
        """)

        if not df_signals.empty:
            # Add sorting option
            sort_by = st.selectbox(
                "Sort by:",
                ["Confluence Score ▼", "Symbol", "Time", "Status"],
                key="signal_sort"
            )

            # Apply sorting
            if "Confluence" in sort_by:
                df_signals = df_signals.sort_values('confluence', ascending=False)
            elif "Symbol" in sort_by:
                df_signals = df_signals.sort_values('symbol')
            elif "Time" in sort_by:
                df_signals = df_signals.sort_values('time', ascending=False)

            # Display table
            display_cols = ['symbol', 'signal', 'confluence', 'allowed', 'reason', 'signal_time']

            # Color code rows
            def highlight_signals(row):
                if '✅' in str(row['allowed']):
                    return ['background-color: rgba(26, 77, 46, 0.3)'] * len(row)
                elif '❌' in str(row['allowed']):
                    return ['background-color: rgba(77, 26, 26, 0.3)'] * len(row)
                else:
                    return [''] * len(row)

            st.dataframe(
                df_signals[display_cols].style.apply(highlight_signals, axis=1),
                use_container_width=True,
                height=350
            )

            # Quick stats
            col1, col2, col3, col4 = st.columns(4)
            total_signals = len(df_signals)
            allowed_signals = (df_signals['allowed'] == '✅ YES').sum()
            blocked_signals = total_signals - allowed_signals
            avg_confluence = df_signals['confluence'].astype(float).mean()

            col1.metric("Total Signals", total_signals, "Last hour")
            col2.metric("Allowed", allowed_signals, f"{allowed_signals/total_signals*100:.0f}%" if total_signals > 0 else "0%")
            col3.metric("Blocked", blocked_signals, f"{blocked_signals/total_signals*100:.0f}%" if total_signals > 0 else "0%")
            col4.metric("Avg Confluence", f"{avg_confluence:.1f}", "0-30 scale")

        else:
            st.info("💤 No signals in the last hour. Market quiet or EA needs time to initialize.")

            # Show configured symbols as fallback
            df_configs = load_data("SELECT symbol FROM SymbolConfigs ORDER BY symbol")
            if not df_configs.empty:
                st.caption(f"Configured symbols ({len(df_configs)}): {', '.join(df_configs['symbol'].tolist())}")

    except Exception as e:
        st.error(f"Error loading signals: {e}")

    st.markdown("---")

    # ============================================================================
    # TIER 3: RECENT ACTIVITY + ALERTS (Bottom 1/3)
    # ============================================================================

    col_left, col_right = st.columns(2)

    # LEFT: Recent Trades
    with col_left:
        st.subheader("📈 Recent Trades (Last 10)")

        try:
            df_recent_trades = load_data("""
                SELECT
                    datetime(entry_time, 'unixepoch') as entry,
                    symbol,
                    CASE type WHEN 0 THEN '🟢 BUY' ELSE '🔴 SELL' END as type,
                    printf('%.4f', entry_price) as entry_price,
                    CASE
                        WHEN close_time IS NULL OR close_time = 0 THEN '🔄 Running'
                        ELSE printf('%.4f', close_price)
                    END as exit_price,
                    CASE
                        WHEN close_time IS NULL OR close_time = 0 THEN '-'
                        ELSE printf('%+.1fR', profit / (lots * 100))
                    END as result,
                    CASE
                        WHEN close_time IS NULL OR close_time = 0 THEN '🔄'
                        WHEN profit > 0 THEN '✅'
                        ELSE '❌'
                    END as status
                FROM Trades
                ORDER BY entry_time DESC
                LIMIT 10
            """)

            if not df_recent_trades.empty:
                st.dataframe(df_recent_trades, use_container_width=True, height=300)
            else:
                st.info("No trades yet. EA will start trading when conditions are met.")

        except Exception as e:
            st.error(f"Error loading trades: {e}")

    # RIGHT: Live Alerts
    with col_right:
        st.subheader("🔔 Live Alerts")

        try:
            # Get recent system logs and signals
            df_alerts = load_data("""
                SELECT
                    datetime(time, 'unixepoch') as timestamp,
                    CASE
                        WHEN message LIKE '%rejected%' OR allowed = 0 THEN '⚠️'
                        WHEN message LIKE '%success%' OR message LIKE '%complete%' THEN '✅'
                        WHEN message LIKE '%error%' OR message LIKE '%failed%' THEN '🔴'
                        ELSE '📊'
                    END as icon,
                    COALESCE(rejection_reason, message) as alert
                FROM (
                    SELECT time, NULL as message, rejection_reason, allowed
                    FROM Signals
                    WHERE time > unixepoch('now', '-1 hour')
                    AND allowed = 0

                    UNION ALL

                    SELECT time, message, NULL as rejection_reason, NULL as allowed
                    FROM SystemLogs
                    WHERE time > unixepoch('now', '-1 hour')
                    AND level IN ('WARNING', 'ERROR', 'INFO')
                )
                ORDER BY time DESC
                LIMIT 15
            """)

            if not df_alerts.empty:
                # Format as alert feed
                for _, alert in df_alerts.iterrows():
                    st.markdown(f"{alert['icon']} **{alert['timestamp']}** - {alert['alert']}")
            else:
                st.success("✅ No alerts - system running smoothly")

        except Exception as e:
            st.info("Alert system initializing...")

    st.markdown("---")

    # ============================================================================
    # QUICK ACTIONS (Always Visible)
    # ============================================================================
    st.subheader("⚡ Quick Actions")

    col_act1, col_act2, col_act3, col_act4 = st.columns(4)

    with col_act1:
        if st.button("🔄 Restart EA", use_container_width=True, type="secondary"):
            with st.spinner("Restarting MT5 EA..."):
                os.system("docker compose restart mt5")
            st.success("✅ EA restarted! Wait 30 seconds for initialization.")
            time.sleep(2)
            st.rerun()

    with col_act2:
        if st.button("🧠 Run Optimization", use_container_width=True, type="primary"):
            st.session_state['redirect_to_optimization'] = True
            st.rerun()

    with col_act3:
        if st.button("📊 View Performance", use_container_width=True, type="secondary"):
            st.session_state['redirect_to_performance'] = True
            st.rerun()

    with col_act4:
        if st.button("⚙️ Settings", use_container_width=True, type="secondary"):
            st.session_state['redirect_to_settings'] = True
            st.rerun()

    # Handle redirects
    if st.session_state.get('redirect_to_optimization'):
        st.session_state['redirect_to_optimization'] = False
        st.sidebar.success("➡️ Navigate to 🧠 Optimization")

    if st.session_state.get('redirect_to_performance'):
        st.session_state['redirect_to_performance'] = False
        st.sidebar.success("➡️ Navigate to 📊 Performance")

    if st.session_state.get('redirect_to_settings'):
        st.session_state['redirect_to_settings'] = False
        st.sidebar.success("➡️ Navigate to ⚙️ Settings")

elif page == "📊 Performance":
    st.title("📊 Performance Analytics")
    st.caption("Track trading performance, analyze results, and monitor strategy effectiveness")

    # Tabs for different views
    tab1, tab2, tab3 = st.tabs(["📈 Portfolio Analytics", "📋 Trade Journal", "🎯 Optimization Impact"])

    with tab1:
        st.subheader("Performance Summary (Last 30 Days)")

        try:
            # Get trade statistics
            df_stats = load_data("""
                SELECT
                    COUNT(*) as total_trades,
                    SUM(CASE WHEN profit > 0 THEN 1 ELSE 0 END) as wins,
                    SUM(CASE WHEN profit <= 0 THEN 1 ELSE 0 END) as losses,
                    SUM(profit) as total_profit,
                    AVG(profit) as avg_profit,
                    MAX(profit) as best_trade,
                    MIN(profit) as worst_trade
                FROM Trades
                WHERE entry_time > unixepoch('now', '-30 days')
                AND close_time IS NOT NULL AND close_time > 0
            """)

            if not df_stats.empty and df_stats['total_trades'].iloc[0] > 0:
                stats = df_stats.iloc[0]
                total_trades = int(stats['total_trades'])
                wins = int(stats['wins'])
                losses = int(stats['losses'])
                win_rate = (wins / total_trades * 100) if total_trades > 0 else 0
                total_profit = stats['total_profit']
                avg_profit = stats['avg_profit']

                # Display metrics
                col1, col2, col3, col4 = st.columns(4)
                col1.metric("Total Trades", total_trades)
                col2.metric("Win Rate", f"{win_rate:.1f}%", f"{wins}W / {losses}L")
                col3.metric("Total Profit", f"${total_profit:.2f}",
                           delta_color="normal" if total_profit >= 0 else "inverse")
                col4.metric("Avg Trade", f"${avg_profit:.2f}")

                st.markdown("---")

                # Symbol Performance Matrix
                st.subheader("Symbol Performance Breakdown")
                df_by_symbol = load_data("""
                    SELECT
                        symbol,
                        COUNT(*) as trades,
                        CAST(SUM(CASE WHEN profit > 0 THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*) * 100 as win_pct,
                        SUM(profit) as total_profit,
                        AVG(profit) as avg_profit,
                        MAX(profit) as best,
                        MIN(profit) as worst
                    FROM Trades
                    WHERE entry_time > unixepoch('now', '-30 days')
                    AND close_time IS NOT NULL AND close_time > 0
                    GROUP BY symbol
                    ORDER BY total_profit DESC
                """)

                if not df_by_symbol.empty:
                    # Format the dataframe
                    df_display = df_by_symbol.copy()
                    df_display['win_pct'] = df_display['win_pct'].apply(lambda x: f"{x:.1f}%")
                    df_display['total_profit'] = df_display['total_profit'].apply(lambda x: f"${x:.2f}")
                    df_display['avg_profit'] = df_display['avg_profit'].apply(lambda x: f"${x:.2f}")
                    df_display['best'] = df_display['best'].apply(lambda x: f"${x:.2f}")
                    df_display['worst'] = df_display['worst'].apply(lambda x: f"${x:.2f}")

                    st.dataframe(df_display, use_container_width=True, height=350)
                else:
                    st.info("No trades by symbol yet")

            else:
                st.info("📊 No closed trades in the last 30 days. Start trading to see performance analytics!")

        except Exception as e:
            st.error(f"Error loading performance data: {e}")

    with tab2:
        st.subheader("Trade Journal")

        # Filters
        col1, col2, col3, col4 = st.columns(4)
        with col1:
            filter_symbol = st.selectbox("Symbol", ["All"] + load_data("SELECT DISTINCT symbol FROM Trades ORDER BY symbol")['symbol'].tolist() if not load_data("SELECT DISTINCT symbol FROM Trades").empty else ["All"])
        with col2:
            filter_result = st.selectbox("Result", ["All", "Wins Only", "Losses Only"])
        with col3:
            days_back = st.number_input("Days Back", min_value=1, max_value=365, value=30)
        with col4:
            limit = st.number_input("Max Trades", min_value=10, max_value=1000, value=100, step=10)

        # Build query
        query = f"""
            SELECT
                datetime(entry_time, 'unixepoch') as entry,
                datetime(close_time, 'unixepoch') as exit,
                symbol,
                CASE type WHEN 0 THEN 'BUY' ELSE 'SELL' END as type,
                printf('%.4f', entry_price) as entry_price,
                printf('%.4f', close_price) as exit_price,
                printf('$%.2f', profit) as profit,
                CASE WHEN profit > 0 THEN '✅ Win' ELSE '❌ Loss' END as result
            FROM Trades
            WHERE entry_time > unixepoch('now', '-{days_back} days')
            AND close_time IS NOT NULL AND close_time > 0
        """

        if filter_symbol != "All":
            query += f" AND symbol = '{filter_symbol}'"
        if filter_result == "Wins Only":
            query += " AND profit > 0"
        elif filter_result == "Losses Only":
            query += " AND profit <= 0"

        query += f" ORDER BY entry_time DESC LIMIT {limit}"

        try:
            df_trades = load_data(query)
            if not df_trades.empty:
                st.dataframe(df_trades, use_container_width=True, height=500)

                # Export option
                csv = df_trades.to_csv(index=False)
                st.download_button(
                    label="📥 Download CSV",
                    data=csv,
                    file_name=f"trades_{time.strftime('%Y%m%d')}.csv",
                    mime="text/csv"
                )
            else:
                st.info("No trades match the selected filters")
        except Exception as e:
            st.error(f"Error loading trades: {e}")

    with tab3:
        st.subheader("Optimization Impact Analysis")

        try:
            # Get optimization history
            df_opt_history = load_data("""
                SELECT
                    id,
                    datetime(completed_at, 'unixepoch') as completed,
                    mode,
                    best_sharpe,
                    test_sharpe,
                    oos_degradation
                FROM OptimizationRuns
                WHERE status = 'completed'
                ORDER BY completed_at DESC
                LIMIT 10
            """)

            if not df_opt_history.empty:
                st.markdown("### Recent Optimizations")
                st.dataframe(df_opt_history, use_container_width=True)

                # Show impact comparison if we have before/after data
                st.markdown("### Before/After Metrics")
                st.info("💡 Compare live performance before and after each optimization run to track effectiveness")

                # Placeholder for comparison chart
                st.caption("📊 Optimization timeline chart coming in Phase 2")

            else:
                st.info("No optimization runs completed yet. Run your first optimization from the 🧠 Optimization page!")

        except Exception as e:
            st.warning(f"Optimization history not available: {e}")

elif page == "🧠 Optimization":
    st.title("🧠 Optimization Hub")
    st.caption("Portfolio-level optimization with Optuna - All symbols optimized together")

    # Tabs: Run Optimization + History
    tab1, tab2 = st.tabs(["🚀 Run Optimization", "📜 History"])

    with tab1:
        st.subheader("Portfolio-Level Optimization")
        st.info("✅ **Strategy architecture is FROZEN** - Only 12 execution parameters are optimized for portfolio performance")

        # Initialize database manager
        db_manager = DatabaseManager(DB_PATH)

        # Check if portfolio optimizer is available
        try:
            from portfolio_optimizer import PortfolioLevelOptimizer
            portfolio_available = True
        except ImportError:
            portfolio_available = False
            st.error("❌ Portfolio optimizer not found. Check installation.")

        if portfolio_available:
            # Settings
            col1, col2, col3 = st.columns(3)

            with col1:
                timeframe_options = {
                    "M1 (1-Minute)": 1,
                    "M5 (5-Minute)": 5,
                    "M15 (15-Minute) ⭐": 15,
                    "M30 (30-Minute)": 30,
                    "H1 (1-Hour)": 60
                }
                selected_tf_name = st.selectbox("Timeframe", list(timeframe_options.keys()), index=2)
                selected_timeframe = timeframe_options[selected_tf_name]

            with col2:
                n_trials = st.number_input("Number of Trials", min_value=10, max_value=500, value=100, step=10,
                                          help="More trials = better results but slower. 100 is recommended.")

            with col3:
                st.metric("Parameters Optimized", "12", "Fixed architecture")
                st.caption("75 params frozen ✅")

            st.markdown("---")

            # What gets optimized
            with st.expander("📋 What Gets Optimized (12 Parameters)"):
                st.markdown("""
                **Structure (4 params):**
                - `swing_lookback` - Swing detection period
                - `zone_tolerance` - Fibonacci zone width
                - `fib_level_low` - Lower Fib retracement
                - `fib_level_high` - Upper Fib retracement

                **Filters (2 params):**
                - `atr_period` - ATR calculation period
                - `chop_threshold` - Chop filter sensitivity

                **Entry (1 param):**
                - `min_confluence_entry` - Minimum score to enter

                **Risk (1 param):**
                - `risk_base` - Base risk % (0.3-0.7)

                **Exits (4 params):**
                - `fixed_tp_r` - Take profit in R
                - `min_tp_r` - Minimum TP
                - `trail_start_r` - When to start trailing
                - `trail_atr_mult` - Trail distance
                """)

            with st.expander("🔒 What's FROZEN (Cannot Change)"):
                st.markdown("""
                **Strategy Core:**
                - `use_smc: 1` - Smart Money Concepts ON
                - `use_mtf: 1` - Multi-timeframe ON
                - `use_displacement: 1` - Displacement detection ON
                - `use_chop_filter: 1` - Chop filter ON
                - `use_trend_filter: 1` - Trend filter ON
                - `use_news_filter: 1` - News avoidance ON
                - All killzone settings (London/NY ON, Asian OFF)

                **Plus 69 more parameters with sensible defaults**
                """)

            st.markdown("---")

            # Run button
            if st.button("🚀 RUN PORTFOLIO OPTIMIZATION", type="primary", use_container_width=True):
                with st.spinner(f"Running {n_trials} trials on all symbols... This will take ~{n_trials//2} minutes"):
                    try:
                        # Initialize optimizer
                        opt = PortfolioLevelOptimizer(db_manager, timeframe=selected_timeframe)

                        # Progress placeholder
                        progress_bar = st.progress(0)
                        status_text = st.empty()

                        # Run optimization
                        status_text.text("🔄 Initializing optimization...")
                        results = opt.run_portfolio_optimization(n_trials=n_trials)
                        progress_bar.progress(100)

                        # Display results
                        st.success("✅ Optimization Complete!")

                        st.subheader("📊 Portfolio Metrics")
                        col1, col2, col3, col4 = st.columns(4)

                        portfolio_sharpe = results['portfolio_metrics']['portfolio_sharpe']
                        avg_corr = results['portfolio_metrics']['avg_correlation']
                        div_ratio = results['portfolio_metrics']['diversification_ratio']
                        worst_sharpe = results['portfolio_metrics']['worst_symbol_sharpe']

                        col1.metric("Portfolio Sharpe", f"{portfolio_sharpe:.3f}",
                                   "✅ Good" if portfolio_sharpe > 0.6 else "⚠️ Weak")
                        col2.metric("Avg Correlation", f"{avg_corr:.3f}",
                                   "✅ Low" if avg_corr < 0.6 else "⚠️ High")
                        col3.metric("Diversification", f"{div_ratio:.2f}",
                                   "✅ Good" if div_ratio > 2.0 else "⚠️ Weak")
                        col4.metric("Worst Symbol", f"{worst_sharpe:.3f}",
                                   "✅ Positive" if worst_sharpe > 0 else "❌ Negative")

                        # Individual symbol results
                        st.markdown("### Individual Symbol Results")
                        symbol_results = []
                        for symbol, metrics in results['individual_results'].items():
                            symbol_results.append({
                                'Symbol': symbol,
                                'Sharpe': f"{metrics['sharpe']:.3f}",
                                'Trades': metrics['total_trades'],
                                'Max DD': f"{metrics['max_drawdown']*100:.1f}%"
                            })

                        df_results = pd.DataFrame(symbol_results)
                        st.dataframe(df_results, use_container_width=True)

                        # Save option
                        st.markdown("---")
                        if st.button("💾 SAVE TO DATABASE & APPLY", type="primary", use_container_width=True):
                            with st.spinner("Saving parameters to all symbols..."):
                                success = opt.save_portfolio_results(results)
                                if success:
                                    st.success("✅ Parameters saved! Restart MT5 EA to apply.")
                                    st.info("Run: `docker compose restart mt5`")
                                else:
                                    st.error("❌ Failed to save some parameters. Check logs.")

                    except Exception as e:
                        st.error(f"❌ Optimization failed: {e}")
                        import traceback
                        st.code(traceback.format_exc())

    with tab2:
        st.subheader("Optimization History")

        try:
            # Load optimization history
            db_manager = DatabaseManager(DB_PATH)
            df_history = db_manager.get_optimization_history(limit=50)

            if not df_history.empty:
                # Display recent runs
                st.markdown("### Recent Optimization Runs")

                # Format for display
                df_display = df_history.copy()
                if 'completed_at' in df_display.columns:
                    df_display['completed_at'] = pd.to_datetime(df_display['completed_at'], unit='s').dt.strftime('%Y-%m-%d %H:%M')

                # Show key columns
                display_cols = ['completed_at', 'mode', 'best_sharpe', 'test_sharpe', 'oos_degradation', 'status']
                available_cols = [col for col in display_cols if col in df_display.columns]

                st.dataframe(df_display[available_cols] if available_cols else df_display,
                           use_container_width=True, height=400)

                # Stats
                st.markdown("### Statistics")
                col1, col2, col3 = st.columns(3)

                completed = (df_history['status'] == 'completed').sum() if 'status' in df_history.columns else len(df_history)
                avg_sharpe = df_history['best_sharpe'].mean() if 'best_sharpe' in df_history.columns else 0

                col1.metric("Total Runs", len(df_history))
                col2.metric("Completed", completed)
                col3.metric("Avg Sharpe", f"{avg_sharpe:.3f}")

            else:
                st.info("📊 No optimization history yet. Run your first optimization above!")

        except Exception as e:
            st.warning(f"Could not load optimization history: {e}")

elif page == "⚙️ Settings":
    st.title("⚙️ Settings")
    st.caption("System configuration, symbol management, and database tools")

    # Tabs for different settings sections
    tab1, tab2, tab3 = st.tabs(["🎯 Symbol Configuration", "⚙️ System Settings", "💾 Database Management"])

    with tab1:
        st.subheader("Symbol Configuration")

        col1, col2 = st.columns([3, 1])
        with col2:
            if st.button("🔄 Reload from DB", key="reload_configs"):
                st.cache_data.clear()
                st.rerun()

        # Load symbol configs
        df_configs = load_data("SELECT * FROM SymbolConfigs")

        if not df_configs.empty:
            st.info(f"📋 **{len(df_configs)} symbols configured**")

            # Display configuration table (editable)
            st.markdown("### Configuration Table")
            st.caption("⚠️ Editing directly here does NOT save to database. Use optimizer or manual SQL updates.")

            # Show subset of important columns if too many
            if len(df_configs.columns) > 20:
                key_cols = ['symbol', 'timeframe', 'risk_base', 'min_confluence_entry',
                           'swing_lookback', 'atr_period', 'fixed_tp_r', 'trail_start_r']
                available_key_cols = [col for col in key_cols if col in df_configs.columns]

                show_all = st.checkbox("Show all columns", value=False, key="show_all_cols")

                if show_all:
                    st.dataframe(df_configs, use_container_width=True, height=400)
                else:
                    st.dataframe(df_configs[available_key_cols] if available_key_cols else df_configs,
                               use_container_width=True, height=400)
            else:
                st.dataframe(df_configs, use_container_width=True, height=400)

            # Bulk operations
            st.markdown("---")
            st.markdown("### Bulk Operations")

            col1, col2 = st.columns(2)

            with col1:
                st.markdown("**Export Configuration**")
                if st.button("📥 Export All Symbols to CSV"):
                    csv = df_configs.to_csv(index=False)
                    st.download_button(
                        label="💾 Download CSV",
                        data=csv,
                        file_name=f"symbol_configs_{time.strftime('%Y%m%d_%H%M%S')}.csv",
                        mime="text/csv"
                    )

            with col2:
                st.markdown("**Apply Optimized Parameters**")
                st.caption("Parameters are applied automatically after optimization")
                if st.button("🔄 Sync from Last Optimization"):
                    st.info("Sync happens automatically. Run optimization from 🧠 Optimization page.")

        else:
            st.warning("⚠️ No symbol configurations found in database")
            st.info("Symbols should be automatically created when EA starts. Check MT5 container.")

    with tab2:
        st.subheader("System Settings")

        # System Health Status
        st.markdown("### System Health")

        col1, col2, col3, col4 = st.columns(4)

        # Database status
        db_exists = os.path.exists(DB_PATH)
        col1.metric("Database", "🟢 Connected" if db_exists else "🔴 Not Found")

        # Database size
        if db_exists:
            db_size = os.path.getsize(DB_PATH) / 1024 / 1024  # MB
            col2.metric("DB Size", f"{db_size:.2f} MB")
        else:
            col2.metric("DB Size", "N/A")

        # Table counts
        try:
            table_counts = {
                'Trades': load_data("SELECT COUNT(*) as cnt FROM Trades")['cnt'].iloc[0],
                'Signals': load_data("SELECT COUNT(*) as cnt FROM Signals")['cnt'].iloc[0],
                'Configs': load_data("SELECT COUNT(*) as cnt FROM SymbolConfigs")['cnt'].iloc[0],
            }
            col3.metric("Total Trades", table_counts['Trades'])
            col4.metric("Total Signals", table_counts['Signals'])
        except:
            col3.metric("Total Trades", "N/A")
            col4.metric("Total Signals", "N/A")

        st.markdown("---")

        # Auto-optimization settings (reference to scheduler)
        st.markdown("### Auto-Optimization")
        st.info("⏰ Scheduler settings are available in the left sidebar under 'Auto-Optimization'")

        # Risk limits
        st.markdown("### Risk Management")
        st.caption("These settings should be configured in the MT5 EA code")

        col1, col2 = st.columns(2)
        with col1:
            st.metric("Max Positions", "10", "Configured in EA")
        with col2:
            st.metric("Max Drawdown Alert", "25%", "Configured in EA")

    with tab3:
        st.subheader("Database Management")

        if not db_exists:
            st.error(f"❌ Database not found at: {DB_PATH}")
            st.info("The database should be created automatically by the MT5 EA. Check if the EA is running.")
        else:
            # Database info
            st.success(f"✅ Database connected: `{DB_PATH}`")

            # Table information
            st.markdown("### Database Tables")

            try:
                tables_query = "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
                df_tables = load_data(tables_query)

                if not df_tables.empty:
                    table_info = []
                    for table in df_tables['name'].tolist():
                        try:
                            count = load_data(f"SELECT COUNT(*) as cnt FROM {table}")['cnt'].iloc[0]
                            table_info.append({
                                'Table': table,
                                'Rows': count,
                                'Status': '✅' if count > 0 else '⚪'
                            })
                        except:
                            table_info.append({
                                'Table': table,
                                'Rows': 'Error',
                                'Status': '❌'
                            })

                    df_table_info = pd.DataFrame(table_info)
                    st.dataframe(df_table_info, use_container_width=True)
                else:
                    st.warning("No tables found in database")

            except Exception as e:
                st.error(f"Error reading database structure: {e}")

            st.markdown("---")

            # Maintenance operations
            st.markdown("### Maintenance Operations")

            st.warning("⚠️ **Caution**: These operations can delete data. Use carefully!")

            col1, col2 = st.columns(2)

            with col1:
                st.markdown("**Clear Old Data**")
                days_to_keep = st.number_input("Keep last N days", min_value=7, max_value=365, value=30)

                if st.button("🗑️ Clear Old Signals", key="clear_signals"):
                    confirm = st.checkbox("Confirm deletion", key="confirm_signals")
                    if confirm:
                        try:
                            conn = get_connection()
                            cursor = conn.cursor()
                            cursor.execute(f"DELETE FROM Signals WHERE time < unixepoch('now', '-{days_to_keep} days')")
                            conn.commit()
                            deleted = cursor.rowcount
                            st.success(f"✅ Deleted {deleted} old signals")
                        except Exception as e:
                            st.error(f"Error: {e}")

                if st.button("🗑️ Clear Old Trades", key="clear_trades"):
                    confirm = st.checkbox("Confirm deletion", key="confirm_trades")
                    if confirm:
                        try:
                            conn = get_connection()
                            cursor = conn.cursor()
                            cursor.execute(f"DELETE FROM Trades WHERE entry_time < unixepoch('now', '-{days_to_keep} days')")
                            conn.commit()
                            deleted = cursor.rowcount
                            st.success(f"✅ Deleted {deleted} old trades")
                        except Exception as e:
                            st.error(f"Error: {e}")

            with col2:
                st.markdown("**Database Health**")

                if st.button("🔍 Run VACUUM", key="vacuum_db"):
                    try:
                        conn = get_connection()
                        conn.execute("VACUUM")
                        st.success("✅ Database optimized")
                    except Exception as e:
                        st.error(f"Error: {e}")

                if st.button("🔍 Check Integrity", key="check_integrity"):
                    try:
                        result = load_data("PRAGMA integrity_check")
                        if result.iloc[0, 0] == "ok":
                            st.success("✅ Database integrity OK")
                        else:
                            st.error(f"❌ Integrity issues: {result}")
                    except Exception as e:
                        st.error(f"Error: {e}")
