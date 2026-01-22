import streamlit as st
from src.connector import MT5Connector
from src import DataEngine, PerformanceAnalytics, PatternGeneric
from components import (
    display_kpi_metrics,
    ChartBuilder,
    render_equity_curve,
    render_drawdown_chart,
    render_profit_distribution,
    render_symbol_performance,
    render_time_analysis,
    render_monthly_performance
)
import pandas as pd
import MetaTrader5 as mt5
from datetime import timedelta, datetime
import time

# Page Config
st.set_page_config(
    page_title="Elite MT5 Trading Analytics",
    page_icon="📊",
    layout="wide",
    initial_sidebar_state="expanded",
)

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
connector = MT5Connector()

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
tab1, tab2, tab3, tab4, tab5, tab6 = st.tabs([
    "📊 Live Dashboard",
    "📈 Performance Analytics",
    "🔎 Trade Inspector",
    "💹 Symbol & Time Analysis",
    "🧩 Pattern Intelligence",
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

# ==================== TAB 2: PERFORMANCE ANALYTICS ====================
with tab2:
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

# ==================== TAB 3: TRADE INSPECTOR ====================
with tab3:
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

# ==================== TAB 4: SYMBOL & TIME ANALYSIS ====================
with tab4:
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

# ==================== TAB 5: PATTERN INTELLIGENCE ====================
with tab5:
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

# ==================== TAB 6: ADVANCED STATS ====================
with tab6:
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

# Auto-refresh logic
if 'auto_refresh' in locals() and auto_refresh:
    time.sleep(refresh_interval)
    st.rerun()
