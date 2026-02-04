"""
System Health Monitor Component
Monitor EA status, errors, and system health
"""

import streamlit as st
import pandas as pd
from datetime import datetime, timedelta
from utils.db_reader import DatabaseReader


def render(db: DatabaseReader):
    """Render system health monitor"""
    st.subheader("🏥 System Health Monitor")

    # Get system state
    account_summary = db.get_account_summary()
    last_update = account_summary.get('last_update')

    # Calculate system status
    if last_update:
        last_update_dt = datetime.fromtimestamp(last_update) if isinstance(last_update, (int, float)) else None
        if last_update_dt:
            seconds_since_update = (datetime.now() - last_update_dt).total_seconds()
            is_running = seconds_since_update < 60  # Consider running if updated in last 60 seconds
        else:
            is_running = False
            seconds_since_update = None
    else:
        is_running = False
        seconds_since_update = None

    # Status indicators
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        if is_running:
            st.markdown("### 🟢 EA Status")
            st.success("**RUNNING**")
        else:
            st.markdown("### 🔴 EA Status")
            st.error("**STOPPED**")

    with col2:
        st.markdown("### ⏱️ Last Heartbeat")
        if last_update_dt:
            time_ago = datetime.now() - last_update_dt
            if time_ago.total_seconds() < 60:
                st.info(f"**{int(time_ago.total_seconds())}s ago**")
            elif time_ago.total_seconds() < 3600:
                st.info(f"**{int(time_ago.total_seconds() / 60)}m ago**")
            else:
                st.warning(f"**{int(time_ago.total_seconds() / 3600)}h ago**")
        else:
            st.warning("**No data**")

    with col3:
        st.markdown("### 🛡️ Kill Switch")
        # We don't have kill switch state in DB yet, so this is placeholder
        st.info("**ACTIVE**")

    with col4:
        st.markdown("### 📊 Data Quality")
        # Check if we have recent trades
        positions = db.get_open_positions()
        trades = db.get_trade_history(days=1)

        if not trades.empty or not positions.empty:
            st.success("**GOOD**")
        else:
            st.warning("**NO RECENT DATA**")

    st.divider()

    # Detailed metrics
    col1, col2, col3 = st.columns(3)

    with col1:
        st.markdown("#### 💾 Database Stats")

        # Total trades
        all_trades = db.get_trade_history(days=0)
        st.metric("Total Trades", len(all_trades))

        # Recent trades
        recent_trades = db.get_trade_history(days=7)
        st.metric("Trades (7d)", len(recent_trades))

        # Open positions
        open_pos = len(positions)
        st.metric("Open Positions", open_pos)

    with col2:
        st.markdown("#### 📡 Signal Activity")

        # Recent signals
        signals_1h = db.get_recent_signals(hours=1)
        st.metric("Signals (1h)", len(signals_1h))

        signals_24h = db.get_recent_signals(hours=24)
        st.metric("Signals (24h)", len(signals_24h))

        # Allowed signals
        if not signals_24h.empty:
            allowed = len(signals_24h[signals_24h['allowed'] == 1])
            st.metric("Allowed (24h)", allowed)

    with col3:
        st.markdown("#### ⚡ Performance")

        # Account metrics
        balance = account_summary.get('balance', 0)
        equity = account_summary.get('equity', 0)

        st.metric("Balance", f"${balance:,.2f}")
        st.metric("Equity", f"${equity:,.2f}")

        floating_pl = account_summary.get('floating_pl', 0)
        st.metric("Floating P/L", f"${floating_pl:,.2f}", delta_color="off")

    st.divider()

    # Connection status
    st.markdown("#### 🔌 Connection Status")

    col1, col2, col3 = st.columns(3)

    with col1:
        st.markdown("**Database Connection**")
        if is_running:
            st.success("✅ Connected")
        else:
            st.error("❌ Disconnected")

    with col2:
        st.markdown("**MT5 Terminal**")
        if is_running:
            st.success("✅ Active")
        else:
            st.warning("⚠️ Status Unknown")

    with col3:
        st.markdown("**Data Stream**")
        if seconds_since_update is not None and seconds_since_update < 30:
            st.success("✅ Real-time")
        elif seconds_since_update is not None and seconds_since_update < 300:
            st.warning("⚠️ Delayed")
        else:
            st.error("❌ Stale")

    st.divider()

    # Recent activity timeline
    st.markdown("#### 📅 Recent Activity")

    # Combine trades and signals for timeline
    activity_items = []

    # Add recent trades
    if not recent_trades.empty:
        for _, trade in recent_trades.iterrows():
            if pd.notna(trade.get('close_time')):
                activity_items.append({
                    'time': trade['close_time'],
                    'type': 'Trade Closed',
                    'details': f"{trade['symbol']} | Profit: ${trade['profit']:.2f}",
                    'icon': '💰' if trade['profit'] > 0 else '📉'
                })

    # Add recent signals
    if not signals_24h.empty:
        for _, signal in signals_24h.head(10).iterrows():
            activity_items.append({
                'time': signal['time'],
                'type': 'Signal',
                'details': f"{signal['symbol']} | Score: {signal['score']:.1f} | {'✅ Allowed' if signal['allowed'] else '❌ Rejected'}",
                'icon': '📡'
            })

    # Sort by time
    if activity_items:
        activity_df = pd.DataFrame(activity_items)
        activity_df = activity_df.sort_values('time', ascending=False).head(15)

        for _, item in activity_df.iterrows():
            time_str = item['time'].strftime('%Y-%m-%d %H:%M:%S') if pd.notna(item['time']) else 'N/A'
            st.markdown(f"""
            <div style="
                padding: 10px;
                margin: 5px 0;
                background-color: #f8f9fa;
                border-left: 3px solid #007bff;
                border-radius: 3px;
            ">
                {item['icon']} <strong>{item['type']}</strong> - {time_str}<br/>
                <small style="color: #666;">{item['details']}</small>
            </div>
            """, unsafe_allow_html=True)
    else:
        st.info("No recent activity")

    st.divider()

    # System recommendations
    st.markdown("#### 💡 System Recommendations")

    recommendations = []

    # Check for stale data
    if seconds_since_update and seconds_since_update > 300:
        recommendations.append("⚠️ Data hasn't updated in over 5 minutes. Check if EA is running.")

    # Check for no recent trades
    if len(recent_trades) == 0:
        recommendations.append("ℹ️ No trades in the last 7 days. Check confluence scores and filters.")

    # Check for low signal activity
    if len(signals_24h) < 10:
        recommendations.append("ℹ️ Low signal activity (< 10 in 24h). Verify symbol list and timeframes.")

    # Check balance vs equity
    if balance > 0 and equity > 0:
        equity_pct = (equity / balance - 1) * 100
        if equity_pct < -5:
            recommendations.append(f"🔴 Equity is {abs(equity_pct):.1f}% below balance. Consider reducing exposure.")
        elif equity_pct > 10:
            recommendations.append(f"🟢 Equity is {equity_pct:.1f}% above balance. Strong performance!")

    # Check open positions
    if open_pos >= 3:
        recommendations.append(f"⚠️ {open_pos} positions open. Monitor risk exposure.")

    if recommendations:
        for rec in recommendations:
            st.info(rec)
    else:
        st.success("✅ All systems operating normally")

    st.divider()
