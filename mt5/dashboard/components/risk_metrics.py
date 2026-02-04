"""
Risk Metrics Component
Displays risk and exposure metrics
"""

import streamlit as st
import plotly.graph_objects as go
from utils.db_reader import DatabaseReader
from utils.metrics import calculate_drawdown_metrics, calculate_risk_exposure


def render(db: DatabaseReader):
    """Render risk metrics section"""
    st.subheader("⚠️ Risk & Exposure")

    # Get data
    account = db.get_account_summary()
    positions_df = db.get_open_positions()
    equity_curve_df = db.get_equity_curve(days=30)

    balance = account.get('balance', 0)
    equity = account.get('equity', 0)
    margin_used = account.get('margin_used', 0)
    margin_free = account.get('margin_free', 0)

    # Calculate drawdown metrics
    drawdown_metrics = calculate_drawdown_metrics(equity_curve_df, balance)

    # Calculate risk exposure
    exposure_metrics = calculate_risk_exposure(positions_df)

    # Display metrics in columns
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        current_dd = drawdown_metrics['current_drawdown']
        current_dd_pct = drawdown_metrics['current_drawdown_pct']
        st.metric(
            "Current Drawdown",
            f"${current_dd:,.2f}",
            f"{current_dd_pct:.2f}%",
            delta_color="inverse"
        )

    with col2:
        max_dd = drawdown_metrics['max_drawdown']
        max_dd_pct = drawdown_metrics['max_drawdown_pct']
        st.metric(
            "Max Drawdown",
            f"${max_dd:,.2f}",
            f"{max_dd_pct:.2f}%",
            delta_color="off"
        )

    with col3:
        peak_equity = drawdown_metrics['peak_equity']
        st.metric(
            "Peak Equity",
            f"${peak_equity:,.2f}",
            delta_color="off"
        )

    with col4:
        margin_pct = (margin_used / equity * 100) if equity > 0 else 0
        st.metric(
            "Margin Used %",
            f"{margin_pct:.1f}%",
            delta_color="off"
        )

    st.divider()

    # Exposure metrics
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        st.metric("Total Positions", exposure_metrics['total_positions'])

    with col2:
        st.metric("Total Lots", f"{exposure_metrics['total_lots']:.2f}")

    with col3:
        st.metric("Long Positions", exposure_metrics['long_positions'])

    with col4:
        st.metric("Short Positions", exposure_metrics['short_positions'])

    # Visualizations
    col1, col2 = st.columns(2)

    with col1:
        st.subheader("Positions by Symbol")
        positions_by_symbol = exposure_metrics['positions_by_symbol']

        if positions_by_symbol:
            fig = go.Figure(data=[go.Pie(
                labels=list(positions_by_symbol.keys()),
                values=list(positions_by_symbol.values()),
                hole=0.4
            )])
            fig.update_layout(
                showlegend=True,
                height=300,
                margin=dict(l=0, r=0, t=0, b=0)
            )
            st.plotly_chart(fig, use_container_width=True)
        else:
            st.info("No open positions")

    with col2:
        st.subheader("Equity Curve (30 days)")
        if not equity_curve_df.empty and 'cumulative_pl' in equity_curve_df.columns:
            equity_curve_df['equity'] = balance + equity_curve_df['cumulative_pl']

            fig = go.Figure()
            fig.add_trace(go.Scatter(
                x=equity_curve_df['time'],
                y=equity_curve_df['equity'],
                mode='lines',
                name='Equity',
                line=dict(color='#2E86AB', width=2),
                fill='tozeroy',
                fillcolor='rgba(46, 134, 171, 0.1)'
            ))

            # Add peak equity line
            peak = equity_curve_df['equity'].max()
            fig.add_hline(
                y=peak,
                line_dash="dash",
                line_color="green",
                annotation_text=f"Peak: ${peak:,.2f}",
                annotation_position="right"
            )

            fig.update_layout(
                xaxis_title="Date",
                yaxis_title="Equity ($)",
                showlegend=False,
                height=300,
                margin=dict(l=0, r=0, t=20, b=0),
                hovermode='x unified'
            )
            st.plotly_chart(fig, use_container_width=True)
        else:
            st.info("Not enough data for equity curve")

    # Risk warnings
    st.subheader("Risk Alerts")

    alerts = []

    # Check margin level
    if margin_pct > 80:
        alerts.append("🔴 HIGH MARGIN USAGE: Margin used exceeds 80% of equity")
    elif margin_pct > 60:
        alerts.append("🟡 ELEVATED MARGIN: Margin used exceeds 60% of equity")

    # Check drawdown
    if current_dd_pct > 20:
        alerts.append("🔴 SEVERE DRAWDOWN: Current drawdown exceeds 20%")
    elif current_dd_pct > 10:
        alerts.append("🟡 SIGNIFICANT DRAWDOWN: Current drawdown exceeds 10%")

    # Check position concentration
    if positions_by_symbol:
        max_symbol_count = max(positions_by_symbol.values())
        total_positions = sum(positions_by_symbol.values())
        concentration = (max_symbol_count / total_positions * 100) if total_positions > 0 else 0

        if concentration > 50:
            alerts.append(f"🟡 POSITION CONCENTRATION: {concentration:.0f}% of positions in single symbol")

    if alerts:
        for alert in alerts:
            st.warning(alert)
    else:
        st.success("✅ All risk metrics within acceptable ranges")

    st.divider()
