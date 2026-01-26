"""
MT5 Trading Dashboard - Streamlit Application
Direct connection to MT5 via Wine (mt5linux)
"""

import streamlit as st
from src.mt5_direct import get_connector
from src.data_engine import DataEngine
from src.analytics import PerformanceAnalytics
# from src.visualizations import create_equity_curve, create_symbol_distribution # Module doesn't exist yet
from src.config import config
from src.logger import initialize_logging, get_logger, shutdown_logging
from components import (
    display_kpi_metrics,
    ChartBuilder,
    render_equity_curve,
    render_drawdown_chart,
    render_profit_distribution,
    render_symbol_performance,
    render_time_analysis,
    # render_correlation_heatmap,  # Not in components yet
    # render_governor_dashboard  # Not in components yet
)
from components.governor_components import (
    render_symbol_scores_table,
    render_correlation_heatmap,
    render_group_cards,
    render_currency_exposure,
    render_governor_controls,
    render_sync_status,
    render_active_group_summary,
    render_group_comparison_table
)
from components.monitor_components import (
    render_ea_status_grid,
    render_governor_metrics_card,
    render_group_risk_bars,
    render_ea_summary_stats,
    render_active_symbol_chips,
    render_inactive_symbol_chips
)
from components.alert_components import (
    render_alert_panel,
    render_health_dashboard,
    render_gv_inspector,
    render_quick_actions_sidebar
)
import pandas as pd
import MetaTrader5 as mt5
from datetime import timedelta, datetime
import time

# Initialize logging system
initialize_logging()
logger = get_logger(__name__)

# Page Config
st.set_page_config(
    page_title=config.PAGE_TITLE,
    page_icon="📊",
    layout="wide",
    initial_sidebar_state="expanded",
)

logger.info("Application started")

# Custom CSS for better aesthetics
st.markdown("""
    <style>
    .stMetric {
        background-color: #1e1e1e;
        padding: 10px;
        border-radius: 5px;
    }
    .metric-positive {
        color: #4CAF50;
    }
    .metric-negative {
        color: #ef5350;
    }
    </style>
""", unsafe_allow_html=True)

# Initialize Connector
connector = get_connector()

# Sidebar Configuration
with st.sidebar:
    st.header("🔌 Connection Status")

    if connector.connect():
        st.success("✅ MT5 Connected")

        account_info = connector.get_account_info()
        if account_info:
            st.divider()
            st.subheader("Account Info")
            st.metric("Account", account_info.get("login"))
            st.metric("Balance", f"${account_info.get('balance'):,.2f}")

            equity = account_info.get('equity')
            balance = account_info.get('balance')
            floating_pl = equity - balance

            st.metric(
                "Equity",
                f"${equity:,.2f}",
                delta=f"${floating_pl:,.2f}"
            )
            st.metric("Server", account_info.get("server"))

            st.divider()
            st.subheader("⚙️ Settings")

            # Auto-refresh toggle
            auto_refresh = st.checkbox("Auto-refresh", value=False)
            refresh_interval = st.slider(
                "Refresh interval (seconds)",
                min_value=5,
                max_value=60,
                value=10,
                step=5,
                disabled=not auto_refresh
            )

            # Days to analyze
            days_to_fetch = st.selectbox(
                "Historical period",
                options=[7, 14, 30, 60, 90, 180, 365],
                index=2
            )

            # Initial balance for equity curve
            initial_balance = st.number_input(
                "Initial Balance",
                min_value=0.0,
                value=10000.0,
                step=1000.0,
                format="%.2f"
            )

            st.divider()
            if st.button("🔄 Manual Refresh"):
                st.rerun()
            
            # Multi-Account Info
            st.divider()
            st.subheader("🔑 Account")
            
            from src.multi_account import AccountManager
            account_mgr = AccountManager()
            current_account = account_mgr.get_current_account()
            
            if current_account:
                st.caption(f"Login: {current_account['login']}")
                st.caption(f"Server: {current_account['server']}")
                
                # List known accounts
                known_accounts = account_mgr.list_known_accounts()
                if len(known_accounts) > 1:
                    st.caption(f"Known accounts: {len(known_accounts)}")
            
            # Quick Actions
            render_quick_actions_sidebar()

    else:
        st.error("❌ MT5 Disconnected")
        st.warning("Please ensure MetaTrader 5 is running and Algo Trading is enabled.")
        if st.button("Retry Connection"):
            st.rerun()
        st.stop()

# Main Content
st.title("🧠 Elite MT5 Trading Intelligence Platform")
st.markdown("### *Real-Time Monitoring & Advanced Analytics*")

if not connector.initialized:
    st.warning("Please ensure MetaTrader 5 is running and Algo Trading is allowed.")
    st.stop()

# Initialize Engines
data_engine = DataEngine()

# Fetch Data
with st.spinner("📥 Fetching Trade History..."):
    trades_df = data_engine.fetch_trades(days=days_to_fetch)
    open_positions_df = data_engine.get_open_positions()

# Create Analytics Engine
analytics = PerformanceAnalytics(trades_df) if not trades_df.empty else None

# Tabs
tab1, tab_ea, tab2, tab3, tab4, tab5, tab6, tab_gv, tab_health, tab7 = st.tabs([
    "📊 Live Dashboard",
    "🤖 EA Status Monitor",
    "🎯 Portfolio Governor",
    "📈 Performance Analytics",
    "🔎 Trade Inspector",
    "💹 Symbol & Time Analysis",
    "🧩 Pattern Intelligence",
    "🔍 GlobalVariables",
    "🏥 System Health",
    "⚙️ Advanced Stats"
])

# ==================== TAB 1: LIVE DASHBOARD ====================
with tab1:
    st.markdown("#### 🎯 Real-Time Overview")

    # Open Positions Section
    st.markdown("### 📍 Open Positions")

    if not open_positions_df.empty:
        total_floating_pl = open_positions_df['profit'].sum()

        col1, col2, col3, col4 = st.columns(4)
        with col1:
            st.metric("Open Positions", len(open_positions_df))
        with col2:
            st.metric(
                "Floating P&L",
                f"${total_floating_pl:,.2f}",
                delta=f"{'🟢' if total_floating_pl > 0 else '🔴'}"
            )
        with col3:
            buy_positions = len(open_positions_df[open_positions_df['type'] == 0])
            st.metric("Buy Positions", buy_positions)
        with col4:
            sell_positions = len(open_positions_df[open_positions_df['type'] == 1])
            st.metric("Sell Positions", sell_positions)

        # Display positions table
        st.dataframe(
            open_positions_df[[
                'ticket', 'symbol', 'type', 'volume', 'price_open',
                'price_current', 'profit', 'time'
            ]].rename(columns={
                'type': 'direction',
                'price_open': 'entry',
                'price_current': 'current'
            }),
            use_container_width=True,
            hide_index=True
        )
    else:
        st.info("📭 No open positions")

    st.divider()

    # Performance KPIs
    st.markdown("### 📊 Performance Metrics")
    display_kpi_metrics(trades_df)

    if not trades_df.empty and analytics:
        # Quick stats
        summary = analytics.get_summary_stats()

        col1, col2, col3, col4, col5 = st.columns(5)

        with col1:
            st.metric(
                "Sharpe Ratio",
                f"{summary.get('sharpe_ratio', 0):.2f}"
            )

        with col2:
            st.metric(
                "Expectancy",
                f"${summary.get('expectancy', 0):.2f}"
            )

        with col3:
            current_dd = summary.get('current_drawdown_pct', 0)
            st.metric(
                "Current DD",
                f"{current_dd:.2f}%",
                delta=f"{'🟢' if current_dd < 5 else '🔴'}"
            )

        with col4:
            streak_type = summary.get('current_streak_type', 'NONE')
            streak_val = summary.get('current_streak', 0)
            st.metric(
                f"Current Streak ({streak_type})",
                streak_val
            )

        with col5:
            avg_win = summary.get('avg_win', 0)
            avg_loss = summary.get('avg_loss', 0)
            risk_reward = abs(avg_win / avg_loss) if avg_loss != 0 else 0
            st.metric(
                "Risk:Reward",
                f"1:{risk_reward:.2f}"
            )

        st.divider()

        # Recent Trades Table
        st.markdown("### 📜 Recent Trades")
        recent_trades = trades_df.tail(20).copy()
        recent_trades['total_profit'] = (
            recent_trades['profit'] +
            recent_trades['commission'] +
            recent_trades['swap']
        )

        st.dataframe(
            recent_trades[[
                'ticket', 'symbol', 'direction', 'entry_time', 'exit_time',
                'volume', 'profit', 'total_profit', 'duration_minutes'
            ]].sort_values('exit_time', ascending=False),
            use_container_width=True,
            hide_index=True
        )
    else:
        st.info(f"No closed trades found in the last {days_to_fetch} days.")

# ==================== TAB EA: EA STATUS MONITOR ====================
with tab_ea:
    st.markdown("#### 🤖 EA Status Monitor")
    st.markdown("*Real-time monitoring of Symbol Engine EAs and Portfolio Governor*")
    
    # Import monitoring modules
    from src.monitor import GovernorMonitor, EAStatusChecker
    
    # Initialize monitors
    governor_monitor = GovernorMonitor()
    ea_status_checker = EAStatusChecker()
    
    # Auto-detect symbols from system
    detected_symbols = ea_status_checker.auto_detect_symbols()
    if detected_symbols:
        ea_status_checker.symbols = detected_symbols
    
    # Two column layout
    col_left, col_right = st.columns([1, 1])
    
    with col_left:
        st.markdown("### 📊 Portfolio Governor Status")
        
        # Get Governor metrics
        governor_metrics = governor_monitor.get_governor_metrics()
        
        # Render Governor metrics card
        render_governor_metrics_card(governor_metrics)
        
        st.divider()
        
        # Group risks
        if governor_metrics.get('active'):
            group_risks = governor_monitor.get_group_risks()
            render_group_risk_bars(group_risks, max_risk=1.0)
    
    with col_right:
        st.markdown("### 🤖 Symbol Engine Status")
        
        # Get EA statuses
        ea_statuses = ea_status_checker.get_all_ea_statuses()
        
        # Summary stats
        summary = ea_status_checker.get_summary_stats()
        render_ea_summary_stats(summary)
        
        st.divider()
        
        # Active/Inactive chips
        active_symbols = ea_status_checker.get_active_symbols()
        inactive_symbols = ea_status_checker.get_inactive_symbols()
        
        if active_symbols:
            render_active_symbol_chips(active_symbols)
            st.write("")  # Spacing
        
        if inactive_symbols:
            render_inactive_symbol_chips(inactive_symbols)
    
    st.divider()
    
    # Full EA status grid
    st.markdown("### 📋 Detailed EA Status")
    render_ea_status_grid(ea_statuses)
    
    # Auto-refresh controls
    st.divider()
    col1, col2, col3 = st.columns([1, 1, 2])
    
    with col1:
        if st.button("🔄 Refresh Now", key="ea_refresh"):
            st.rerun()
    
    with col2:
        auto_refresh_ea = st.checkbox("Auto-refresh", value=False, key="auto_refresh_ea")
    
    with col3:
        if auto_refresh_ea:
            refresh_seconds = st.slider("Refresh interval (s)", 5, 60, 10, key="ea_refresh_interval")
            st.caption(f"Auto-refreshing every {refresh_seconds} seconds")
            time.sleep(refresh_seconds)
            st.rerun()

# ==================== TAB 2: PORTFOLIO GOVERNOR ====================
with tab2:
    st.markdown("#### 🎯 Portfolio Governor")
    st.markdown("*Intelligent portfolio selection - operate 4 symbols from 20 candidates*")
    
    # Initialize Portfolio Governor (cached in session state)
    if 'portfolio_governor' not in st.session_state:
        st.session_state.portfolio_governor = PortfolioGovernor(
            performance_data=trades_df if not trades_df.empty else None
        )
    
    governor = st.session_state.portfolio_governor
    
    # Refresh button
    col1, col2, col3 = st.columns([1, 1, 4])
    with col1:
        if st.button("🔄 Refresh All", key="gov_refresh"):
            with st.spinner("Refreshing portfolio data..."):
                governor.refresh_all()
                st.success("Portfolio data refreshed!")
    with col2:
        st.write(f"Last refresh: {governor.last_refresh.strftime('%H:%M:%S') if governor.last_refresh else 'Never'}")
    
    st.divider()
    
    # Two column layout
    left_col, right_col = st.columns([1, 1])
    
    with left_col:
        st.markdown("### 📊 Symbol Scores")
        
        # Get symbol scores
        if not governor.symbol_scores:
            with st.spinner("Calculating scores..."):
                scores_df = governor.refresh_scores()
        else:
            scores_df = governor.symbol_scorer.get_all_symbol_scores()
        
        render_symbol_scores_table(scores_df)
        
        st.divider()
        
        # Currency Exposure
        st.markdown("### 💱 Currency Exposure")
        exposure = governor.get_currency_exposure()
        render_currency_exposure(exposure)
    
    with right_col:
        st.markdown("### 🔥 Correlation Heatmap")
        
        # Get correlation matrix
        corr_matrix = governor.correlation_engine.get_correlation_heatmap_data()
        if corr_matrix.empty:
            with st.spinner("Calculating correlations..."):
                governor.refresh_correlations(force=True)
                corr_matrix = governor.correlation_engine.get_correlation_heatmap_data()
        
        render_correlation_heatmap(corr_matrix, height=400)
    
    st.divider()
    
    # Group Selection
    st.markdown("### 🎲 Candidate Groups")
    st.caption(f"Showing top 5 from {governor.group_ranker.total_valid_groups} valid combinations")
    
    # Generate groups if needed
    if not governor.candidate_groups:
        with st.spinner("Generating groups..."):
            governor.generate_groups()
    
    # Render group cards
    if governor.candidate_groups:
        selected_id = render_group_cards(
            groups=governor.candidate_groups,
            active_id=governor.active_group_id
        )
        
        # Handle selection
        if selected_id != governor.active_group_id:
            governor.select_group(selected_id)
            st.rerun()
    
    st.divider()
    
    # Active Group Summary
    if governor.active_group:
        render_active_group_summary(
            symbols=governor.active_group,
            symbol_scores=governor.symbol_scores,
            group_info=governor.candidate_groups[governor.active_group_id] if governor.candidate_groups else {}
        )
    
    st.divider()
    
    # Governor Controls
    controls = render_governor_controls(
        mode=governor.mode.value,
        is_locked=governor.mode == GovernorMode.LOCKED
    )
    
    # Handle control actions
    if controls["lock_clicked"]:
        if governor.mode == GovernorMode.LOCKED:
            governor.unlock_group()
            st.success("🔓 Portfolio unlocked")
        else:
            if governor.lock_group():
                st.success("🔒 Portfolio locked for session")
        st.rerun()
    
    if controls["sync_clicked"]:
        with st.spinner("Syncing with MT5..."):
            sync_result = governor.sync_with_mt5()
            render_sync_status(sync_result)
    
    if controls["auto_select"] and governor.mode != GovernorMode.AUTO:
        governor.set_mode(GovernorMode.AUTO)
        governor.select_best_group()
        st.rerun()
    elif not controls["auto_select"] and governor.mode == GovernorMode.AUTO:
        governor.set_mode(GovernorMode.MANUAL)

# ==================== TAB 3: PERFORMANCE ANALYTICS ====================
with tab3:
    st.markdown("#### 📈 Advanced Performance Analysis")

    if not trades_df.empty and analytics:
        # Equity Curve
        equity_curve = analytics.calculate_equity_curve(initial_balance)

        if not equity_curve.empty:
            render_equity_curve(equity_curve)

            st.divider()

            # Drawdown Chart
            render_drawdown_chart(equity_curve)

            st.divider()

            # Two column layout for additional charts
            col1, col2 = st.columns(2)

            with col1:
                # Profit Distribution
                profit_dist = analytics.calculate_profit_distribution()
                render_profit_distribution(profit_dist)

            with col2:
                # Monthly Performance
                render_monthly_performance(trades_df)

            st.divider()

            # Drawdown Statistics
            st.markdown("### 📉 Drawdown Statistics")
            dd_stats = analytics.calculate_max_drawdown()

            col1, col2, col3, col4 = st.columns(4)
            with col1:
                st.metric(
                    "Max Drawdown",
                    f"${dd_stats['max_drawdown']:,.2f}"
                )
            with col2:
                st.metric(
                    "Max DD %",
                    f"{dd_stats['max_drawdown_pct']:.2f}%"
                )
            with col3:
                st.metric(
                    "Current DD",
                    f"${dd_stats['current_drawdown']:,.2f}"
                )
            with col4:
                st.metric(
                    "Current DD %",
                    f"{dd_stats['current_drawdown_pct']:.2f}%"
                )
        else:
            st.warning("Not enough data to generate equity curve")
    else:
        st.info("No trade data available for performance analysis")

# ==================== TAB 4: TRADE INSPECTOR ====================
with tab4:
    st.subheader("🔍 Deep Dive Trade Inspector")

    if not trades_df.empty:
        selected_ticket = st.selectbox("Select Trade Ticket", trades_df['ticket'].tolist())

        trade_data = trades_df[trades_df['ticket'] == selected_ticket].iloc[0]

        # Split layout
        c1, c2 = st.columns([1, 2])

        with c1:
            st.markdown("### Trade Details")
            st.markdown(f"**Symbol:** {trade_data['symbol']}")
            st.markdown(f"**Direction:** {trade_data['direction']}")
            st.markdown(f"**Volume:** {trade_data['volume']}")
            st.markdown(f"**Entry Price:** {trade_data['entry_price']}")
            st.markdown(f"**Exit Price:** {trade_data['exit_price']}")
            st.markdown(f"**Entry Time:** {trade_data['entry_time']}")
            st.markdown(f"**Exit Time:** {trade_data['exit_time']}")
            st.markdown(f"**Duration:** {trade_data['duration_minutes']:.1f} minutes")

            st.divider()

            total_pnl = trade_data['profit'] + trade_data['commission'] + trade_data['swap']
            st.markdown(f"**Profit:** ${trade_data['profit']:.2f}")
            st.markdown(f"**Commission:** ${trade_data['commission']:.2f}")
            st.markdown(f"**Swap:** ${trade_data['swap']:.2f}")
            st.markdown(f"**Total P&L:** ${total_pnl:.2f}")

            if trade_data.get('comment'):
                st.markdown(f"**Comment:** {trade_data['comment']}")
            if trade_data.get('magic'):
                st.markdown(f"**Magic Number:** {trade_data['magic']}")

        with c2:
            st.markdown("### Trade Context Chart")

            # Define view window
            timeframe = mt5.TIMEFRAME_M15
            buffer_before = timedelta(hours=4)
            buffer_after = timedelta(hours=2)

            start_dt = trade_data['entry_time'] - buffer_before
            end_dt = trade_data['exit_time'] + buffer_after

            # Fetch OHLC data
            ohlc_df = data_engine.fetch_ohlc(
                trade_data['symbol'],
                timeframe,
                start_dt,
                end_dt
            )

            if not ohlc_df.empty:
                # Build chart with markers
                chart = ChartBuilder(ohlc_df)
                single_trade_df = trades_df[trades_df['ticket'] == selected_ticket]
                markers = chart.add_markers(single_trade_df)

                chart.render_with_markers(
                    title=f"Trade {selected_ticket} - {trade_data['symbol']} (M15)",
                    markers=markers,
                    height=600
                )
            else:
                st.warning(
                    f"No OHLC data found for {trade_data['symbol']}. "
                    "Please download history in MT5."
                )
    else:
        st.info("No trades available for inspection")

# ==================== TAB 5: SYMBOL & TIME ANALYSIS ====================
with tab5:
    st.markdown("#### 💹 Symbol & Time Performance Analysis")

    if not trades_df.empty and analytics:
        # Symbol Performance
        st.markdown("### 🎯 Performance by Symbol")
        symbol_stats = analytics.analyze_by_symbol()

        if not symbol_stats.empty:
            render_symbol_performance(symbol_stats)

            st.dataframe(
                symbol_stats.style.format({
                    'total_pnl': "${:.2f}",
                    'avg_pnl': "${:.2f}",
                    'std_pnl': "${:.2f}",
                    'avg_duration': "{:.1f} min",
                    'win_rate': "{:.1f}%"
                }).background_gradient(subset=['total_pnl'], cmap='RdYlGn'),
                use_container_width=True,
                hide_index=True
            )

        st.divider()

        # Time-based Analysis
        st.markdown("### ⏰ Time-Based Performance")
        time_stats = analytics.analyze_by_time()
        render_time_analysis(time_stats)

        # Display tables
        col1, col2 = st.columns(2)

        with col1:
            if not time_stats['by_hour'].empty:
                st.markdown("**Performance by Hour**")
                st.dataframe(
                    time_stats['by_hour'].style.format({
                        'total_pnl': "${:.2f}",
                        'avg_pnl': "${:.2f}"
                    }),
                    use_container_width=True,
                    hide_index=True
                )

        with col2:
            if not time_stats['by_day'].empty:
                st.markdown("**Performance by Day**")
                st.dataframe(
                    time_stats['by_day'].style.format({
                        'total_pnl': "${:.2f}",
                        'avg_pnl': "${:.2f}"
                    }),
                    use_container_width=True,
                    hide_index=True
                )
    else:
        st.info("No trade data available for symbol & time analysis")

# ==================== TAB 6: PATTERN INTELLIGENCE ====================
with tab6:
    st.markdown("#### 🧩 Pattern Intelligence")

    if trades_df.empty:
        st.info("No trades to analyze.")
    else:
        pattern_engine = PatternGeneric(trades_df)

        # Add total_profit column
        trades_df['total_profit'] = (
            trades_df['profit'] +
            trades_df['commission'] +
            trades_df['swap']
        )

        stats_df = pattern_engine.analyze_patterns()

        if not stats_df.empty:
            col1, col2 = st.columns([2, 1])

            with col1:
                st.dataframe(
                    stats_df.style.format({
                        'total_pnl': "${:.2f}",
                        'avg_pnl': "${:.2f}",
                        'win_rate': "{:.1f}%"
                    }).background_gradient(subset=['total_pnl'], cmap='RdYlGn'),
                    use_container_width=True,
                    hide_index=True
                )

            with col2:
                st.bar_chart(stats_df.set_index('details_pattern')['total_pnl'])
        else:
            st.info("No pattern data available")

# ==================== TAB 7: ADVANCED STATS ====================
with tab7:
    st.markdown("#### ⚙️ Advanced Statistics & Risk Metrics")

    if not trades_df.empty and analytics:
        summary = analytics.get_summary_stats()

        # Three columns for comprehensive stats
        col1, col2, col3 = st.columns(3)

        with col1:
            st.markdown("### 📊 Trading Statistics")
            st.metric("Total Trades", summary.get('total_trades', 0))
            st.metric("Winning Trades", summary.get('winning_trades', 0))
            st.metric("Losing Trades", summary.get('losing_trades', 0))
            st.metric("Win Rate", f"{summary.get('win_rate', 0):.2f}%")

        with col2:
            st.markdown("### 💰 Profit Metrics")
            st.metric("Net Profit", f"${summary.get('net_profit', 0):,.2f}")
            st.metric("Gross Profit", f"${summary.get('gross_profit', 0):,.2f}")
            st.metric("Gross Loss", f"${summary.get('gross_loss', 0):,.2f}")
            st.metric("Profit Factor", f"{summary.get('profit_factor', 0):.2f}")
            st.metric("Average Win", f"${summary.get('avg_win', 0):.2f}")
            st.metric("Average Loss", f"${summary.get('avg_loss', 0):.2f}")

        with col3:
            st.markdown("### 📉 Risk Metrics")
            st.metric("Expectancy", f"${summary.get('expectancy', 0):.2f}")
            st.metric("Sharpe Ratio", f"{summary.get('sharpe_ratio', 0):.2f}")
            st.metric("Max Drawdown", f"${summary.get('max_drawdown', 0):,.2f}")
            st.metric("Max DD %", f"{summary.get('max_drawdown_pct', 0):.2f}%")
            st.metric("Current DD", f"${summary.get('current_drawdown', 0):,.2f}")
            st.metric("Current DD %", f"{summary.get('current_drawdown_pct', 0):.2f}%")

        st.divider()

        # Streak Analysis
        st.markdown("### 🔥 Streak Analysis")
        col1, col2, col3 = st.columns(3)

        with col1:
            st.metric(
                "Longest Win Streak",
                summary.get('longest_win_streak', 0)
            )

        with col2:
            st.metric(
                "Longest Loss Streak",
                summary.get('longest_loss_streak', 0)
            )

        with col3:
            streak_type = summary.get('current_streak_type', 'NONE')
            current_streak = summary.get('current_streak', 0)
            st.metric(
                f"Current Streak ({streak_type})",
                current_streak
            )
    else:
        st.info("No trade data available for advanced statistics")

# ==================== TAB GV: GLOBALVARIABLES INSPECTOR ====================
with tab_gv:
    st.markdown("#### 🔍 GlobalVariables Inspector")
    
    # Filter options
    col1, col2, col3 = st.columns(3)
    
    with col1:
        filter_gov = st.checkbox("Governor (PG_)", value=True)
    with col2:
        filter_mult = st.checkbox("Multipliers", value=True)
    with col3:
        show_all = st.checkbox("Show All", value=False)
    
    # Display GlobalVariables
    if show_all:
        render_gv_inspector("")
    elif filter_gov or filter_mult:
        prefixes = []
        if filter_gov:
            prefixes.append("PG_")
        if filter_mult:
            prefixes.append("GovernorMultiplier_")
        
        # Show for first prefix (can be enhanced)
        render_gv_inspector(prefixes[0] if prefixes else "")

# ==================== TAB HEALTH: SYSTEM HEALTH ====================
with tab_health:
    st.markdown("#### 🏥 System Health Dashboard")
    
    from src.monitor import HealthChecker, AlertManager, GovernorMonitor, EAStatusChecker
    
    # Initialize
    health_checker = HealthChecker()
    
    if 'alert_manager' not in st.session_state:
        st.session_state.alert_manager = AlertManager()
    alert_mgr = st.session_state.alert_manager
    
    # Run diagnostics
    health_results = health_checker.run_full_diagnostic()
    
    # Check alerts
    gov_monitor = GovernorMonitor()
    ea_checker = EAStatusChecker()
    gov_metrics = gov_monitor.get_governor_metrics()
    ea_statuses = ea_checker.get_all_ea_statuses()
    
    alert_mgr.check_governor_thresholds(gov_metrics)
    alert_mgr.check_ea_health(ea_statuses)
    
    # Display
    col1, col2 = st.columns([2, 1])
    
    with col1:
        render_health_dashboard(health_results)
    
    with col2:
        recent_alerts = alert_mgr.get_recent_alerts(60)
        if render_alert_panel(recent_alerts, 10):
            alert_mgr.clear_alerts()
            st.rerun()

# Auto-refresh logic
if 'auto_refresh' in locals() and auto_refresh:
    time.sleep(refresh_interval)
    st.rerun()
