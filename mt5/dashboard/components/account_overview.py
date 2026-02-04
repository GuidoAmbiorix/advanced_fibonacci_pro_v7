"""
Account Overview Component
Displays key account metrics in a clean card layout
"""

import streamlit as st
from utils.db_reader import DatabaseReader
from utils.metrics import format_currency, format_percentage


def render(db: DatabaseReader):
    """Render account overview section"""
    st.subheader("📊 Account Overview")

    # Get data
    account = db.get_account_summary()
    daily_pl = db.get_daily_pl()
    total_pl = db.get_total_pl()
    positions_df = db.get_open_positions()
    trades_df = db.get_trade_history(days=0)  # All history for metrics

    # Calculate metrics
    balance = account.get('balance', 0)
    equity = account.get('equity', 0)
    floating_pl = account.get('floating_pl', 0)
    open_positions_count = len(positions_df)

    # Win rate calculation
    if not trades_df.empty:
        wins = len(trades_df[trades_df['profit'] > 0])
        total_trades = len(trades_df)
        win_rate = (wins / total_trades * 100) if total_trades > 0 else 0.0

        # Profit factor
        gross_profit = trades_df[trades_df['profit'] > 0]['profit'].sum()
        gross_loss = abs(trades_df[trades_df['profit'] <= 0]['profit'].sum())
        profit_factor = (gross_profit / gross_loss) if gross_loss > 0 else 0.0
    else:
        win_rate = 0.0
        profit_factor = 0.0

    # Display metrics in columns
    col1, col2, col3, col4, col5, col6 = st.columns(6)

    with col1:
        st.metric(
            label="Balance",
            value=format_currency(balance),
            delta=None
        )

    with col2:
        st.metric(
            label="Equity",
            value=format_currency(equity),
            delta=format_currency(floating_pl) if floating_pl != 0 else None,
            delta_color="normal"
        )

    with col3:
        st.metric(
            label="Daily P/L",
            value=format_currency(daily_pl),
            delta=format_percentage((daily_pl / balance * 100) if balance > 0 else 0) if daily_pl != 0 else None,
            delta_color="normal"
        )

    with col4:
        st.metric(
            label="Total P/L",
            value=format_currency(total_pl),
            delta=format_percentage((total_pl / balance * 100) if balance > 0 else 0) if total_pl != 0 else None,
            delta_color="normal"
        )

    with col5:
        st.metric(
            label="Open Positions",
            value=open_positions_count,
            delta=None
        )

    with col6:
        st.metric(
            label="Win Rate",
            value=f"{win_rate:.1f}%",
            delta=f"PF: {profit_factor:.2f}" if profit_factor > 0 else None,
            delta_color="off"
        )

    # Additional info row
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        margin_used = account.get('margin_used', 0)
        st.metric("Margin Used", format_currency(margin_used))

    with col2:
        margin_free = account.get('margin_free', 0)
        st.metric("Margin Free", format_currency(margin_free))

    with col3:
        margin_pct = (margin_used / equity * 100) if equity > 0 else 0
        st.metric("Margin %", f"{margin_pct:.1f}%")

    with col4:
        total_trades = len(trades_df)
        st.metric("Total Trades", total_trades)

    st.divider()
