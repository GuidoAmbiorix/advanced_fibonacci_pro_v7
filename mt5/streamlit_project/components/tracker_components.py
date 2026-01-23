"""
Portfolio Tracker UI Components - Visualizations for portfolio tracking.
Renders group performance history, attribution analysis, and correlation drift alerts.
"""

import streamlit as st
import plotly.graph_objects as go
import plotly.express as px
import pandas as pd
from typing import Dict, List, Optional
from datetime import datetime


def render_active_group_card(group_details: Optional[Dict]):
    """
    Render card with active portfolio group details.

    Args:
        group_details: Dict with group information
    """
    if not group_details:
        st.info("📊 No active portfolio group")
        return

    st.subheader("🎯 Active Portfolio Group")

    # Main metrics
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        st.metric(
            "Net Profit",
            f"${group_details['net_profit']:.2f}",
            delta=f"{group_details['win_rate']:.1f}% Win Rate"
        )

    with col2:
        st.metric(
            "Trades",
            group_details['trades_count'],
            delta=f"{group_details['winning_trades']}W/{group_details['losing_trades']}L"
        )

    with col3:
        lifetime_days = group_details['lifetime_days']
        st.metric(
            "Lifetime",
            f"{lifetime_days:.1f} days",
            delta=f"${group_details['profit_per_day']:.2f}/day"
        )

    with col4:
        sharpe = group_details.get('sharpe_ratio')
        st.metric(
            "Sharpe Ratio",
            f"{sharpe:.2f}" if sharpe else "N/A",
            delta="Risk-Adjusted"
        )

    # Symbols
    st.markdown("**Symbols:**")
    symbol_cols = st.columns(len(group_details['symbols']))
    for idx, symbol in enumerate(group_details['symbols']):
        with symbol_cols[idx]:
            st.markdown(f"**{symbol}**")

    # Group metrics
    with st.expander("📊 Group Metrics"):
        col1, col2 = st.columns(2)

        with col1:
            st.markdown(f"**Composite Score:** {group_details['composite_score']:.1f}")
            st.markdown(f"**Risk Balance:** {group_details['risk_balance']:.2f}")

        with col2:
            st.markdown(f"**Avg Correlation:** {group_details['avg_correlation']:.3f}")
            st.markdown(f"**Max Correlation:** {group_details['max_correlation']:.3f}")

        if group_details.get('notes'):
            st.markdown(f"**Notes:** {group_details['notes']}")


def render_performance_attribution(attribution_df: pd.DataFrame):
    """
    Render symbol performance attribution chart.

    Args:
        attribution_df: DataFrame with symbol attribution
    """
    if attribution_df.empty:
        st.info("No attribution data available")
        return

    st.subheader("📈 Performance Attribution by Symbol")

    # Create stacked bar chart
    fig = go.Figure()

    # Profit bars
    colors = ['green' if p > 0 else 'red' for p in attribution_df['total_profit']]

    fig.add_trace(go.Bar(
        x=attribution_df['symbol'],
        y=attribution_df['total_profit'],
        marker_color=colors,
        text=attribution_df['total_profit'].round(2),
        textposition='outside',
        name='Total Profit'
    ))

    fig.update_layout(
        title="Profit Contribution by Symbol",
        xaxis_title="Symbol",
        yaxis_title="Profit ($)",
        template="plotly_dark",
        height=400
    )

    st.plotly_chart(fig, use_container_width=True)

    # Detailed metrics table
    with st.expander("📋 Detailed Attribution Metrics"):
        # Format the dataframe for display
        display_df = attribution_df.copy()
        display_df['total_profit'] = display_df['total_profit'].round(2)
        display_df['win_rate'] = display_df['win_rate'].round(1)
        display_df['avg_profit'] = display_df['avg_profit'].round(2)
        display_df['contribution_pct'] = display_df['contribution_pct'].round(1)

        st.dataframe(
            display_df,
            use_container_width=True,
            hide_index=True
        )


def render_group_history(history_df: pd.DataFrame):
    """
    Render portfolio group history timeline.

    Args:
        history_df: DataFrame with group history
    """
    if history_df.empty:
        st.info("No group history available")
        return

    st.subheader("📜 Portfolio Group History")

    # Timeline chart
    fig = go.Figure()

    for idx, row in history_df.iterrows():
        # Color based on profitability
        color = 'green' if row['net_profit'] > 0 else 'red'

        symbols_str = ', '.join(row['symbols'])

        fig.add_trace(go.Scatter(
            x=[row['selected_at'], row['deselected_at'] if pd.notna(row['deselected_at']) else datetime.now()],
            y=[idx, idx],
            mode='lines+markers',
            line=dict(color=color, width=8),
            marker=dict(size=10),
            name=symbols_str,
            hovertemplate=(
                f"<b>{symbols_str}</b><br>"
                f"Profit: ${row['net_profit']:.2f}<br>"
                f"Trades: {row['trades_count']}<br>"
                f"Win Rate: {row['win_rate']:.1f}%<br>"
                f"<extra></extra>"
            )
        ))

    fig.update_layout(
        title="Group Selection Timeline",
        xaxis_title="Date",
        yaxis_title="Group",
        template="plotly_dark",
        height=400,
        showlegend=False
    )

    st.plotly_chart(fig, use_container_width=True)

    # Summary table
    with st.expander("📊 Group Performance Summary"):
        summary_df = history_df[[
            'symbols', 'selected_at', 'net_profit', 'trades_count',
            'win_rate', 'lifetime_hours', 'profit_per_day'
        ]].copy()

        summary_df['symbols'] = summary_df['symbols'].apply(lambda x: ', '.join(x))
        summary_df['selected_at'] = pd.to_datetime(summary_df['selected_at']).dt.strftime('%Y-%m-%d %H:%M')
        summary_df['net_profit'] = summary_df['net_profit'].round(2)
        summary_df['win_rate'] = summary_df['win_rate'].round(1)
        summary_df['lifetime_hours'] = summary_df['lifetime_hours'].round(1)
        summary_df['profit_per_day'] = summary_df['profit_per_day'].round(2)

        st.dataframe(summary_df, use_container_width=True, hide_index=True)


def render_correlation_drift_alert(drifts: List[Dict]):
    """
    Render alerts for correlation drift detection.

    Args:
        drifts: List of detected drifts
    """
    if not drifts:
        st.success("✅ No significant correlation drift detected")
        return

    st.warning(f"⚠️ {len(drifts)} Correlation Drift(s) Detected")

    for drift in drifts:
        severity_color = "🔴" if drift['severity'] == 'high' else "🟡"

        with st.expander(f"{severity_color} {drift['type'].replace('_', ' ').title()}"):
            col1, col2, col3 = st.columns(3)

            with col1:
                st.metric("Original", f"{drift['original']:.3f}")

            with col2:
                st.metric("Current", f"{drift['current']:.3f}")

            with col3:
                st.metric("Drift", f"{drift['drift']:.3f}")

            st.markdown(f"**Severity:** {drift['severity'].upper()}")

            if drift['severity'] == 'high':
                st.error("⚠️ Consider reviewing portfolio group selection")


def render_lifecycle_analysis(lifecycle: Dict):
    """
    Render portfolio group lifecycle analysis.

    Args:
        lifecycle: Dict with lifecycle metrics
    """
    if not lifecycle:
        st.info("Insufficient data for lifecycle analysis")
        return

    st.subheader("🔄 Portfolio Lifecycle Analysis")

    # Key metrics
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        st.metric(
            "Total Groups",
            lifecycle['total_groups'],
            delta=f"{lifecycle['profitable_rate']:.1f}% Profitable"
        )

    with col2:
        st.metric(
            "Avg Lifetime",
            f"{lifecycle['avg_lifetime_days']:.1f} days",
            delta=f"{lifecycle['avg_trades_per_group']:.0f} trades/group"
        )

    with col3:
        st.metric(
            "Total Net Profit",
            f"${lifecycle['total_net_profit']:.2f}",
            delta=f"{lifecycle['avg_win_rate']:.1f}% avg WR"
        )

    with col4:
        st.metric(
            "Avg Correlation",
            f"{lifecycle['avg_starting_correlation']:.3f}",
            delta=f"{lifecycle['avg_max_correlation']:.3f} max"
        )

    # Best and worst groups
    col1, col2 = st.columns(2)

    with col1:
        if lifecycle.get('best_group'):
            st.success("🏆 Best Performing Group")
            best = lifecycle['best_group']
            st.markdown(f"**Symbols:** {', '.join(best['symbols'])}")
            st.markdown(f"**Profit:** ${best['profit']:.2f}")
            st.markdown(f"**Trades:** {best['trades']}")

    with col2:
        if lifecycle.get('worst_group'):
            st.error("📉 Worst Performing Group")
            worst = lifecycle['worst_group']
            st.markdown(f"**Symbols:** {', '.join(worst['symbols'])}")
            st.markdown(f"**Loss:** ${worst['profit']:.2f}")
            st.markdown(f"**Trades:** {worst['trades']}")


def render_tracker_dashboard(
    active_group: Optional[Dict],
    attribution_df: pd.DataFrame,
    history_df: pd.DataFrame,
    drifts: List[Dict],
    lifecycle: Dict
):
    """
    Render complete portfolio tracker dashboard.

    Args:
        active_group: Active group details
        attribution_df: Attribution DataFrame
        history_df: History DataFrame
        drifts: Correlation drifts
        lifecycle: Lifecycle analysis
    """
    st.title("📊 Portfolio Performance Tracker")

    # Active group card
    render_active_group_card(active_group)

    st.divider()

    # Correlation drift alerts
    if active_group:
        render_correlation_drift_alert(drifts)
        st.divider()

    # Two-column layout for charts
    col1, col2 = st.columns(2)

    with col1:
        # Performance attribution
        if not attribution_df.empty:
            render_performance_attribution(attribution_df)

    with col2:
        # Lifecycle analysis
        if lifecycle:
            render_lifecycle_analysis(lifecycle)

    st.divider()

    # Group history
    if not history_df.empty:
        render_group_history(history_df)


def render_cache_status(cache_stats: Dict):
    """
    Render database cache status.

    Args:
        cache_stats: Dict with cache statistics
    """
    st.sidebar.markdown("### 💾 Cache Status")

    if not cache_stats:
        st.sidebar.info("Cache info unavailable")
        return

    # Cache status indicator
    status = cache_stats.get('cache_status', 'unknown')
    if status == 'fresh':
        st.sidebar.success(f"✅ Cache Fresh")
    else:
        st.sidebar.warning(f"⚠️ Cache Stale")

    # Metrics
    st.sidebar.metric(
        "Cached Trades",
        cache_stats.get('cached_trades', 0)
    )

    latest_trade = cache_stats.get('latest_trade')
    if latest_trade:
        st.sidebar.text(f"Latest: {latest_trade.strftime('%Y-%m-%d %H:%M')}")

    cache_age = cache_stats.get('cache_age_hours')
    if cache_age is not None:
        st.sidebar.text(f"Age: {cache_age:.1f} hours")

    db_size = cache_stats.get('database_size_mb', 0)
    st.sidebar.text(f"DB Size: {db_size:.2f} MB")
