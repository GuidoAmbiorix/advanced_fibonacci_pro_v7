"""
Trade History Component
Displays closed trades with filters and charts
"""

import streamlit as st
import pandas as pd
import plotly.graph_objects as go
from utils.db_reader import DatabaseReader


def render(db: DatabaseReader, date_range: str = "7D"):
    """Render trade history section"""
    st.subheader("📜 Trade History")

    # Parse date range
    days_map = {
        "1D": 1,
        "7D": 7,
        "30D": 30,
        "90D": 90,
        "All": 0
    }
    days = days_map.get(date_range, 7)

    # Get trade history
    trades_df = db.get_trade_history(days=days)

    if trades_df.empty:
        st.info("No closed trades in selected period")
        return

    # Filters in columns
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        symbols = ['All'] + sorted(trades_df['symbol'].unique().tolist()) if 'symbol' in trades_df.columns else ['All']
        selected_symbol = st.selectbox("Symbol", symbols, key="hist_symbol")

    with col2:
        regimes = ['All'] + sorted(trades_df['regime'].dropna().unique().tolist()) if 'regime' in trades_df.columns else ['All']
        selected_regime = st.selectbox("Regime", regimes, key="hist_regime")

    with col3:
        killzones = ['All'] + sorted(trades_df['killzone'].dropna().unique().tolist()) if 'killzone' in trades_df.columns else ['All']
        selected_killzone = st.selectbox("Killzone", killzones, key="hist_killzone")

    with col4:
        profit_filter = st.selectbox("Result", ["All", "Winners", "Losers"], key="hist_profit")

    # Apply filters
    filtered_df = trades_df.copy()

    if selected_symbol != 'All':
        filtered_df = filtered_df[filtered_df['symbol'] == selected_symbol]

    if selected_regime != 'All':
        filtered_df = filtered_df[filtered_df['regime'] == selected_regime]

    if selected_killzone != 'All':
        filtered_df = filtered_df[filtered_df['killzone'] == selected_killzone]

    if profit_filter == "Winners":
        filtered_df = filtered_df[filtered_df['profit'] > 0]
    elif profit_filter == "Losers":
        filtered_df = filtered_df[filtered_df['profit'] <= 0]

    if filtered_df.empty:
        st.warning("No trades match the selected filters")
        return

    # Summary metrics
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        total_trades = len(filtered_df)
        st.metric("Trades", total_trades)

    with col2:
        wins = len(filtered_df[filtered_df['profit'] > 0])
        win_rate = (wins / total_trades * 100) if total_trades > 0 else 0
        st.metric("Win Rate", f"{win_rate:.1f}%")

    with col3:
        total_profit = filtered_df['profit'].sum()
        st.metric("Total P/L", f"${total_profit:,.2f}", delta_color="off")

    with col4:
        avg_profit = filtered_df['profit'].mean()
        st.metric("Avg P/L", f"${avg_profit:,.2f}", delta_color="off")

    # Equity curve chart
    st.subheader("Cumulative P/L")
    filtered_df = filtered_df.sort_values('close_time')
    filtered_df['cumulative_pl'] = filtered_df['profit'].cumsum()

    fig = go.Figure()
    fig.add_trace(go.Scatter(
        x=filtered_df['close_time'],
        y=filtered_df['cumulative_pl'],
        mode='lines',
        name='Cumulative P/L',
        line=dict(color='#1f77b4', width=2),
        fill='tozeroy',
        fillcolor='rgba(31, 119, 180, 0.1)'
    ))

    fig.update_layout(
        xaxis_title="Date",
        yaxis_title="Cumulative P/L ($)",
        hovermode='x unified',
        height=300,
        margin=dict(l=0, r=0, t=20, b=0)
    )

    st.plotly_chart(fig, use_container_width=True)

    # Trade table
    st.subheader("Trade Details")

    display_df = filtered_df.copy()

    # Format type
    if 'type' in display_df.columns:
        display_df['Type'] = display_df['type'].map({0: 'BUY', 1: 'SELL'})
    else:
        display_df['Type'] = 'N/A'

    # Select columns for display
    display_columns = ['ticket', 'symbol', 'Type', 'lots', 'entry_price', 'close_price',
                       'entry_time', 'close_time', 'profit', 'exit_reason', 'regime', 'killzone']

    available_columns = [col for col in display_columns if col in display_df.columns or col == 'Type']
    display_df = display_df[available_columns]

    # Rename for better display
    column_names = {
        'ticket': 'Ticket',
        'symbol': 'Symbol',
        'Type': 'Type',
        'lots': 'Lots',
        'entry_price': 'Entry',
        'close_price': 'Close',
        'entry_time': 'Entry Time',
        'close_time': 'Close Time',
        'profit': 'P/L',
        'exit_reason': 'Exit Reason',
        'regime': 'Regime',
        'killzone': 'Killzone'
    }
    display_df = display_df.rename(columns=column_names)

    # Format numeric columns
    if 'Lots' in display_df.columns:
        display_df['Lots'] = display_df['Lots'].round(2)
    if 'Entry' in display_df.columns:
        display_df['Entry'] = display_df['Entry'].round(5)
    if 'Close' in display_df.columns:
        display_df['Close'] = display_df['Close'].round(5)
    if 'P/L' in display_df.columns:
        display_df['P/L'] = display_df['P/L'].round(2)

    # Format times
    if 'Entry Time' in display_df.columns:
        display_df['Entry Time'] = pd.to_datetime(display_df['Entry Time']).dt.strftime('%Y-%m-%d %H:%M')
    if 'Close Time' in display_df.columns:
        display_df['Close Time'] = pd.to_datetime(display_df['Close Time']).dt.strftime('%Y-%m-%d %H:%M')

    # Display table with pagination
    st.dataframe(
        display_df,
        use_container_width=True,
        hide_index=True,
        height=400
    )

    # CSV export
    csv = filtered_df.to_csv(index=False)
    st.download_button(
        label="📥 Download as CSV",
        data=csv,
        file_name=f"trade_history_{date_range}.csv",
        mime="text/csv"
    )

    st.divider()
