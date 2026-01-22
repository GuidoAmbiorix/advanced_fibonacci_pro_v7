import streamlit as st
import pandas as pd

def display_kpi_metrics(trades_df: pd.DataFrame):
    """
    Displays the top-row KPI cards: Net Profit, Win Rate, Total Trades, Profit Factor.
    """
    if trades_df.empty:
        st.warning("No trades available for metrics.")
        return

    total_profit = (trades_df['profit'] + trades_df['commission'] + trades_df['swap']).sum()
    total_trades = len(trades_df)

    trades_df['total_profit'] = trades_df['profit'] + trades_df['commission'] + trades_df['swap']
    winning_trades = trades_df[trades_df['total_profit'] > 0]
    losing_trades = trades_df[trades_df['total_profit'] <= 0]
    
    win_rate = (len(winning_trades) / total_trades) * 100 if total_trades > 0 else 0
    
    gross_profit = winning_trades['total_profit'].sum()
    gross_loss = abs(losing_trades['total_profit'].sum())
    profit_factor = (gross_profit / gross_loss) if gross_loss > 0 else float('inf')

    # Layout
    col1, col2, col3, col4 = st.columns(4)
    
    with col1:
        st.metric("Net Profit", f"${total_profit:,.2f}", delta=f"{len(winning_trades)} W / {len(losing_trades)} L")
    
    with col2:
        st.metric("Win Rate", f"{win_rate:.1f}%")
        
    with col3:
        st.metric("Profit Factor", f"{profit_factor:.2f}")
        
    with col4:
        st.metric("Total Trades", total_trades)

    st.divider()
