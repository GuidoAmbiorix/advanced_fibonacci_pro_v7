"""
Open Positions Component
Displays current open positions in a table
"""

import streamlit as st
import pandas as pd
from utils.db_reader import DatabaseReader
from datetime import datetime


def render(db: DatabaseReader):
    """Render open positions table"""
    st.subheader("📈 Open Positions")

    positions_df = db.get_open_positions()

    if positions_df.empty:
        st.info("No open positions")
        return

    # Prepare display dataframe
    display_df = positions_df.copy()

    # Format type
    if 'type' in display_df.columns:
        display_df['Type'] = display_df['type'].map({0: '🟢 BUY', 1: '🔴 SELL'})
    else:
        display_df['Type'] = 'N/A'

    # Format columns for display
    display_columns = {
        'ticket': 'Ticket',
        'symbol': 'Symbol',
        'Type': 'Type',
        'lots': 'Lots',
        'entry_price': 'Entry',
        'profit': 'P/L',
        'entry_time': 'Time',
        'confluence_score': 'Score',
        'regime': 'Regime',
        'killzone': 'Killzone'
    }

    # Select and rename columns that exist
    available_columns = [col for col in display_columns.keys() if col in display_df.columns or col == 'Type']
    display_df = display_df[available_columns]
    display_df = display_df.rename(columns=display_columns)

    # Format numeric columns
    if 'Lots' in display_df.columns:
        display_df['Lots'] = display_df['Lots'].round(2)
    if 'Entry' in display_df.columns:
        display_df['Entry'] = display_df['Entry'].round(5)
    if 'Score' in display_df.columns:
        display_df['Score'] = display_df['Score'].round(1)

    # Format time
    if 'Time' in display_df.columns:
        display_df['Time'] = pd.to_datetime(display_df['Time']).dt.strftime('%Y-%m-%d %H:%M')

    # Color code profit/loss
    def color_profit(val):
        try:
            val_float = float(val)
            if val_float > 0:
                return f'<span style="color: green; font-weight: bold">${val_float:,.2f}</span>'
            elif val_float < 0:
                return f'<span style="color: red; font-weight: bold">${val_float:,.2f}</span>'
            else:
                return f'${val_float:,.2f}'
        except:
            return val

    if 'P/L' in display_df.columns:
        display_df['P/L'] = display_df['P/L'].apply(color_profit)

    # Display as HTML table for colored profit
    st.write(display_df.to_html(escape=False, index=False), unsafe_allow_html=True)

    # Summary stats
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        total_pl = positions_df['profit'].sum() if 'profit' in positions_df.columns else 0
        st.metric("Total Floating P/L", f"${total_pl:,.2f}", delta_color="off")

    with col2:
        avg_pl = positions_df['profit'].mean() if 'profit' in positions_df.columns else 0
        st.metric("Avg P/L per Position", f"${avg_pl:,.2f}", delta_color="off")

    with col3:
        total_lots = positions_df['lots'].sum() if 'lots' in positions_df.columns else 0
        st.metric("Total Lots", f"{total_lots:.2f}")

    with col4:
        unique_symbols = positions_df['symbol'].nunique() if 'symbol' in positions_df.columns else 0
        st.metric("Unique Symbols", unique_symbols)

    st.divider()
