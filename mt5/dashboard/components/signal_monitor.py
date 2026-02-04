"""
Live Signal Monitor Component
Real-time view of trading signals as they're generated
"""

import streamlit as st
import pandas as pd
import plotly.graph_objects as go
from datetime import datetime, timedelta
from utils.db_reader import DatabaseReader


def get_score_color(score):
    """Get color based on signal score"""
    if score >= 18:
        return '#00cc96'  # Elite (green)
    elif score >= 14:
        return '#ffa500'  # Strong (orange)
    elif score >= 10:
        return '#ffed4e'  # Good (yellow)
    else:
        return '#ef553b'  # Weak (red)


def get_score_label(score):
    """Get label based on signal score"""
    if score >= 18:
        return '🔥 ELITE'
    elif score >= 14:
        return '⚡ STRONG'
    elif score >= 10:
        return '✅ GOOD'
    else:
        return '⚠️ WEAK'


def render(db: DatabaseReader, hours: int = 2):
    """Render live signal monitor"""
    st.subheader("📡 Live Signal Monitor")

    # Get recent signals
    signals_df = db.get_recent_signals(hours=hours)

    if signals_df.empty:
        st.info(f"No signals in the last {hours} hours")
        return

    # Control row
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        time_filter = st.selectbox(
            "Time Range",
            ["Last 1 Hour", "Last 2 Hours", "Last 6 Hours", "Last 24 Hours"],
            index=1,
            key="signal_time_filter"
        )
        hours = int(time_filter.split()[1]) if "Hour" in time_filter else 24

    with col2:
        symbol_filter = st.selectbox(
            "Symbol",
            ["All"] + sorted(signals_df['symbol'].unique().tolist()),
            key="signal_symbol_filter"
        )

    with col3:
        status_filter = st.selectbox(
            "Status",
            ["All", "Allowed Only", "Rejected Only"],
            key="signal_status_filter"
        )

    with col4:
        min_score = st.slider(
            "Min Score",
            0.0,
            30.0,
            0.0,
            0.5,
            key="signal_min_score"
        )

    # Apply filters
    filtered_df = signals_df.copy()

    if symbol_filter != "All":
        filtered_df = filtered_df[filtered_df['symbol'] == symbol_filter]

    if status_filter == "Allowed Only":
        filtered_df = filtered_df[filtered_df['allowed'] == 1]
    elif status_filter == "Rejected Only":
        filtered_df = filtered_df[filtered_df['allowed'] == 0]

    if min_score > 0:
        filtered_df = filtered_df[filtered_df['score'] >= min_score]

    # Summary metrics
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        total_signals = len(filtered_df)
        st.metric("Total Signals", total_signals)

    with col2:
        allowed_signals = len(filtered_df[filtered_df['allowed'] == 1])
        allowed_pct = (allowed_signals / total_signals * 100) if total_signals > 0 else 0
        st.metric("Allowed", f"{allowed_signals} ({allowed_pct:.0f}%)")

    with col3:
        avg_score = filtered_df['score'].mean() if not filtered_df.empty else 0
        st.metric("Avg Score", f"{avg_score:.1f}")

    with col4:
        elite_signals = len(filtered_df[filtered_df['score'] >= 18])
        st.metric("🔥 Elite Signals", elite_signals)

    st.divider()

    # Signal feed
    st.subheader("📊 Signal Feed")

    if filtered_df.empty:
        st.warning("No signals match the selected filters")
        return

    # Sort by time descending (most recent first)
    filtered_df = filtered_df.sort_values('time', ascending=False)

    # Display signals as cards
    for idx, signal in filtered_df.iterrows():
        score = signal['score']
        allowed = signal['allowed'] == 1
        symbol = signal['symbol']
        direction = "🟢 LONG" if signal['direction'] > 0 else "🔴 SHORT"
        time_str = signal['time'].strftime('%Y-%m-%d %H:%M:%S') if pd.notna(signal['time']) else 'N/A'

        score_color = get_score_color(score)
        score_label = get_score_label(score)

        # Status badge
        if allowed:
            status_badge = "✅ **ALLOWED**"
            card_color = "#d4edda"
        else:
            status_badge = "❌ **REJECTED**"
            card_color = "#f8d7da"

        # Create card
        with st.container():
            st.markdown(f"""
            <div style="
                border-left: 5px solid {score_color};
                padding: 15px;
                margin: 10px 0;
                background-color: {card_color};
                border-radius: 5px;
            ">
                <div style="display: flex; justify-content: space-between; align-items: center;">
                    <div>
                        <h3 style="margin: 0; color: #333;">{symbol} {direction}</h3>
                        <p style="margin: 5px 0; color: #666;">🕐 {time_str}</p>
                    </div>
                    <div style="text-align: right;">
                        <div style="
                            background-color: {score_color};
                            color: white;
                            padding: 10px 20px;
                            border-radius: 5px;
                            font-weight: bold;
                            font-size: 18px;
                        ">
                            {score:.1f} / 30
                        </div>
                        <p style="margin: 5px 0; font-weight: bold;">{score_label}</p>
                    </div>
                </div>
            </div>
            """, unsafe_allow_html=True)

            # Details in expander
            with st.expander("📋 Signal Details"):
                col1, col2, col3 = st.columns(3)

                with col1:
                    st.write("**Status:**", status_badge)
                    if not allowed and pd.notna(signal.get('rejection_reason')):
                        st.write("**Reason:**", signal['rejection_reason'])

                with col2:
                    if pd.notna(signal.get('smc_score')):
                        st.write("**SMC Score:**", f"{signal['smc_score']:.1f}")
                    if pd.notna(signal.get('fib_score')):
                        st.write("**Fib Score:**", f"{signal['fib_score']:.1f}")

                with col3:
                    if pd.notna(signal.get('rank')):
                        st.write("**Rank:**", f"#{int(signal['rank'])}")

    # Score distribution chart
    st.divider()
    st.subheader("📊 Score Distribution")

    col1, col2 = st.columns(2)

    with col1:
        # Histogram of scores
        fig = go.Figure()
        fig.add_trace(go.Histogram(
            x=filtered_df['score'],
            nbinsx=20,
            marker=dict(
                color=filtered_df['score'],
                colorscale=[[0, '#ef553b'], [0.33, '#ffed4e'], [0.66, '#ffa500'], [1, '#00cc96']],
                showscale=True,
                colorbar=dict(title="Score")
            ),
            name='Score Distribution'
        ))

        # Add vertical lines for thresholds
        fig.add_vline(x=10, line_dash="dash", line_color="yellow", annotation_text="Good (10)")
        fig.add_vline(x=14, line_dash="dash", line_color="orange", annotation_text="Strong (14)")
        fig.add_vline(x=18, line_dash="dash", line_color="green", annotation_text="Elite (18)")

        fig.update_layout(
            xaxis_title="Confluence Score",
            yaxis_title="Frequency",
            height=300,
            margin=dict(l=0, r=0, t=20, b=0),
            showlegend=False
        )
        st.plotly_chart(fig, use_container_width=True)

    with col2:
        # Allowed vs Rejected
        allowed_count = len(filtered_df[filtered_df['allowed'] == 1])
        rejected_count = len(filtered_df[filtered_df['allowed'] == 0])

        fig = go.Figure(data=[go.Pie(
            labels=['Allowed', 'Rejected'],
            values=[allowed_count, rejected_count],
            marker=dict(colors=['#00cc96', '#ef553b']),
            hole=0.4
        )])

        fig.update_layout(
            height=300,
            margin=dict(l=0, r=0, t=0, b=0),
            showlegend=True
        )
        st.plotly_chart(fig, use_container_width=True)

    # Signals by symbol
    st.subheader("📊 Signals by Symbol")

    symbol_stats = filtered_df.groupby('symbol').agg({
        'score': ['count', 'mean', 'max'],
        'allowed': 'sum'
    }).round(2)

    symbol_stats.columns = ['Total', 'Avg Score', 'Max Score', 'Allowed']
    symbol_stats = symbol_stats.sort_values('Total', ascending=False)
    symbol_stats['Allowed %'] = (symbol_stats['Allowed'] / symbol_stats['Total'] * 100).round(1)

    st.dataframe(
        symbol_stats,
        use_container_width=True,
        height=250
    )

    st.divider()
