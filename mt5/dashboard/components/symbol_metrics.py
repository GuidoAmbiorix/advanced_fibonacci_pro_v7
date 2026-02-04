"""
Symbol-Level Metrics Component
Displays performance metrics broken down by symbol
"""

import streamlit as st
import pandas as pd
import plotly.express as px
from utils.db_reader import DatabaseReader


def render(db: DatabaseReader):
    """Render symbol metrics section"""
    st.subheader("🎯 Symbol Performance")

    symbol_metrics = db.get_symbol_metrics()

    if symbol_metrics.empty:
        st.info("No symbol data available")
        return

    # Display metrics table
    display_df = symbol_metrics.copy()

    # Format columns
    if 'total_profit' in display_df.columns:
        display_df['Total P/L'] = display_df['total_profit'].apply(lambda x: f"${x:,.2f}")
    if 'avg_profit' in display_df.columns:
        display_df['Avg P/L'] = display_df['avg_profit'].apply(lambda x: f"${x:,.2f}")
    if 'best_trade' in display_df.columns:
        display_df['Best Trade'] = display_df['best_trade'].apply(lambda x: f"${x:,.2f}")
    if 'worst_trade' in display_df.columns:
        display_df['Worst Trade'] = display_df['worst_trade'].apply(lambda x: f"${x:,.2f}")
    if 'avg_win' in display_df.columns:
        display_df['Avg Win'] = display_df['avg_win'].apply(lambda x: f"${x:,.2f}" if pd.notna(x) else "N/A")
    if 'avg_loss' in display_df.columns:
        display_df['Avg Loss'] = display_df['avg_loss'].apply(lambda x: f"${x:,.2f}" if pd.notna(x) else "N/A")
    if 'win_rate' in display_df.columns:
        display_df['Win Rate'] = display_df['win_rate'].apply(lambda x: f"{x:.1f}%")
    if 'profit_factor' in display_df.columns:
        display_df['Profit Factor'] = display_df['profit_factor'].apply(lambda x: f"{x:.2f}" if x < 999 else "∞")

    # Select columns for display
    display_columns = ['symbol', 'total_trades', 'Win Rate', 'Profit Factor',
                       'Total P/L', 'Avg Win', 'Avg Loss', 'Best Trade', 'Worst Trade']

    available_columns = [col for col in display_columns if col in display_df.columns]
    display_df_final = display_df[available_columns]

    # Rename symbol column
    display_df_final = display_df_final.rename(columns={
        'symbol': 'Symbol',
        'total_trades': 'Trades'
    })

    st.dataframe(
        display_df_final,
        use_container_width=True,
        hide_index=True,
        height=300
    )

    # Visual charts
    col1, col2 = st.columns(2)

    with col1:
        st.subheader("P/L by Symbol")
        if 'total_profit' in symbol_metrics.columns:
            fig = px.bar(
                symbol_metrics.sort_values('total_profit', ascending=True).tail(10),
                x='total_profit',
                y='symbol',
                orientation='h',
                labels={'total_profit': 'Total P/L ($)', 'symbol': 'Symbol'},
                color='total_profit',
                color_continuous_scale=['red', 'yellow', 'green']
            )
            fig.update_layout(
                showlegend=False,
                height=300,
                margin=dict(l=0, r=0, t=0, b=0)
            )
            st.plotly_chart(fig, use_container_width=True)

    with col2:
        st.subheader("Win Rate by Symbol")
        if 'win_rate' in symbol_metrics.columns:
            fig = px.bar(
                symbol_metrics.sort_values('win_rate', ascending=True).tail(10),
                x='win_rate',
                y='symbol',
                orientation='h',
                labels={'win_rate': 'Win Rate (%)', 'symbol': 'Symbol'},
                color='win_rate',
                color_continuous_scale='Blues'
            )
            fig.update_layout(
                showlegend=False,
                height=300,
                margin=dict(l=0, r=0, t=0, b=0)
            )
            st.plotly_chart(fig, use_container_width=True)

    # Check current signal status for symbols
    st.subheader("Current Signal Status")
    signals_df = db.get_recent_signals(hours=1)

    if not signals_df.empty:
        # Get most recent signal per symbol
        latest_signals = signals_df.sort_values('time').groupby('symbol').last().reset_index()

        display_signals = latest_signals[['symbol', 'score', 'allowed', 'rejection_reason']].copy()
        display_signals['Status'] = display_signals['allowed'].map({1: '✅ Allowed', 0: '❌ Blocked'})

        # Format score
        if 'score' in display_signals.columns:
            display_signals['Score'] = display_signals['score'].round(1)

        # Select display columns
        signal_display = display_signals[['symbol', 'Score', 'Status', 'rejection_reason']]
        signal_display = signal_display.rename(columns={
            'symbol': 'Symbol',
            'rejection_reason': 'Reason'
        })

        st.dataframe(
            signal_display,
            use_container_width=True,
            hide_index=True,
            height=200
        )
    else:
        st.info("No recent signals in the last hour")

    st.divider()
