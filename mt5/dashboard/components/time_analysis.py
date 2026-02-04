"""
Time Analysis Component
Heatmaps and analysis of trading performance by time
"""

import streamlit as st
import pandas as pd
import plotly.graph_objects as go
import plotly.express as px
import numpy as np
from utils.db_reader import DatabaseReader


def render(db: DatabaseReader):
    """Render time analysis heatmaps"""
    st.subheader("⏰ Time Analysis")

    trades_df = db.get_trade_history(days=0)

    if trades_df.empty:
        st.info("No trade data available for time analysis")
        return

    # Add time components
    trades_df['entry_time_dt'] = pd.to_datetime(trades_df['entry_time'])
    trades_df['hour'] = trades_df['entry_time_dt'].dt.hour
    trades_df['day_of_week'] = trades_df['entry_time_dt'].dt.day_name()
    trades_df['day_num'] = trades_df['entry_time_dt'].dt.dayofweek

    # Tabs for different views
    tab1, tab2, tab3 = st.tabs(["📊 Entry Time Heatmap", "📈 Performance by Time", "🎯 Best Trading Times"])

    with tab1:
        st.markdown("### Entry Time Distribution Heatmap")
        st.caption("Shows when trades are being entered (darker = more trades)")

        # Create hour x day heatmap
        pivot_data = trades_df.groupby(['day_num', 'hour']).size().reset_index(name='count')

        # Create full grid
        days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
        hours = list(range(24))

        heatmap_data = np.zeros((7, 24))

        for _, row in pivot_data.iterrows():
            heatmap_data[int(row['day_num']), int(row['hour'])] = row['count']

        fig = go.Figure(data=go.Heatmap(
            z=heatmap_data,
            x=hours,
            y=days,
            colorscale='Blues',
            text=heatmap_data.astype(int),
            texttemplate='%{text}',
            textfont={"size": 10},
            colorbar=dict(title="Trades")
        ))

        fig.update_layout(
            xaxis_title="Hour of Day (UTC)",
            yaxis_title="Day of Week",
            height=400,
            margin=dict(l=0, r=0, t=20, b=0)
        )

        st.plotly_chart(fig, use_container_width=True)

    with tab2:
        st.markdown("### Performance by Time")
        st.caption("Shows profit/loss by hour and day (green = profit, red = loss)")

        # Create P/L heatmap
        pivot_pl = trades_df.groupby(['day_num', 'hour'])['profit'].sum().reset_index()

        heatmap_pl = np.zeros((7, 24))

        for _, row in pivot_pl.iterrows():
            heatmap_pl[int(row['day_num']), int(row['hour'])] = row['profit']

        fig = go.Figure(data=go.Heatmap(
            z=heatmap_pl,
            x=hours,
            y=days,
            colorscale='RdYlGn',
            zmid=0,
            text=np.round(heatmap_pl, 1),
            texttemplate='$%{text}',
            textfont={"size": 9},
            colorbar=dict(title="P/L ($)")
        ))

        fig.update_layout(
            xaxis_title="Hour of Day (UTC)",
            yaxis_title="Day of Week",
            height=400,
            margin=dict(l=0, r=0, t=20, b=0)
        )

        st.plotly_chart(fig, use_container_width=True)

        # Win rate heatmap
        st.markdown("### Win Rate by Time")
        st.caption("Shows win rate percentage by hour and day")

        # Calculate win rate
        win_rate_data = trades_df.groupby(['day_num', 'hour']).apply(
            lambda x: (x['profit'] > 0).sum() / len(x) * 100 if len(x) > 0 else 0
        ).reset_index(name='win_rate')

        heatmap_wr = np.zeros((7, 24))

        for _, row in win_rate_data.iterrows():
            heatmap_wr[int(row['day_num']), int(row['hour'])] = row['win_rate']

        fig = go.Figure(data=go.Heatmap(
            z=heatmap_wr,
            x=hours,
            y=days,
            colorscale='RdYlGn',
            zmin=0,
            zmax=100,
            text=np.round(heatmap_wr, 1),
            texttemplate='%{text}%',
            textfont={"size": 9},
            colorbar=dict(title="Win Rate (%)")
        ))

        fig.update_layout(
            xaxis_title="Hour of Day (UTC)",
            yaxis_title="Day of Week",
            height=400,
            margin=dict(l=0, r=0, t=20, b=0)
        )

        st.plotly_chart(fig, use_container_width=True)

    with tab3:
        st.markdown("### Best Trading Times")

        # Aggregate by hour
        hourly_stats = trades_df.groupby('hour').agg({
            'profit': ['sum', 'mean', 'count'],
        }).round(2)

        hourly_stats.columns = ['Total P/L', 'Avg P/L', 'Trade Count']
        hourly_stats['Win Rate'] = trades_df.groupby('hour').apply(
            lambda x: (x['profit'] > 0).sum() / len(x) * 100
        ).round(1)

        hourly_stats = hourly_stats.sort_values('Total P/L', ascending=False)

        # Top 5 best hours
        col1, col2 = st.columns(2)

        with col1:
            st.markdown("#### 🏆 Top 5 Best Hours")
            best_hours = hourly_stats.head(5)
            for hour, row in best_hours.iterrows():
                st.success(f"**{hour:02d}:00** - P/L: ${row['Total P/L']:.2f} | Win Rate: {row['Win Rate']:.1f}% | Trades: {int(row['Trade Count'])}")

        with col2:
            st.markdown("#### 📉 Top 5 Worst Hours")
            worst_hours = hourly_stats.tail(5)
            for hour, row in worst_hours.iterrows():
                st.error(f"**{hour:02d}:00** - P/L: ${row['Total P/L']:.2f} | Win Rate: {row['Win Rate']:.1f}% | Trades: {int(row['Trade Count'])}")

        st.divider()

        # Aggregate by day
        daily_stats = trades_df.groupby('day_of_week').agg({
            'profit': ['sum', 'mean', 'count'],
        }).round(2)

        daily_stats.columns = ['Total P/L', 'Avg P/L', 'Trade Count']
        daily_stats['Win Rate'] = trades_df.groupby('day_of_week').apply(
            lambda x: (x['profit'] > 0).sum() / len(x) * 100
        ).round(1)

        # Reorder by day of week
        day_order = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
        daily_stats = daily_stats.reindex([d for d in day_order if d in daily_stats.index])

        # Best days
        col1, col2 = st.columns(2)

        with col1:
            st.markdown("#### 🏆 Best Days of Week")
            best_days = daily_stats.sort_values('Total P/L', ascending=False).head(3)
            for day, row in best_days.iterrows():
                st.success(f"**{day}** - P/L: ${row['Total P/L']:.2f} | Win Rate: {row['Win Rate']:.1f}% | Trades: {int(row['Trade Count'])}")

        with col2:
            st.markdown("#### 📉 Worst Days of Week")
            worst_days = daily_stats.sort_values('Total P/L', ascending=True).head(3)
            for day, row in worst_days.iterrows():
                st.error(f"**{day}** - P/L: ${row['Total P/L']:.2f} | Win Rate: {row['Win Rate']:.1f}% | Trades: {int(row['Trade Count'])}")

        st.divider()

        # Session analysis (if killzone data available)
        if 'killzone' in trades_df.columns:
            st.markdown("### Performance by Trading Session")

            session_stats = trades_df.groupby('killzone').agg({
                'profit': ['sum', 'mean', 'count'],
            }).round(2)

            session_stats.columns = ['Total P/L', 'Avg P/L', 'Trade Count']
            session_stats['Win Rate'] = trades_df.groupby('killzone').apply(
                lambda x: (x['profit'] > 0).sum() / len(x) * 100
            ).round(1)

            session_stats = session_stats.sort_values('Total P/L', ascending=False)

            # Display as table
            st.dataframe(
                session_stats,
                use_container_width=True,
                height=200
            )

            # Session comparison chart
            fig = go.Figure()

            fig.add_trace(go.Bar(
                x=session_stats.index,
                y=session_stats['Total P/L'],
                name='Total P/L',
                marker=dict(
                    color=session_stats['Total P/L'],
                    colorscale='RdYlGn',
                    showscale=False
                ),
                text=[f"${x:.2f}" for x in session_stats['Total P/L']],
                textposition='outside'
            ))

            fig.update_layout(
                xaxis_title="Trading Session",
                yaxis_title="Total P/L ($)",
                height=300,
                margin=dict(l=0, r=0, t=20, b=0),
                showlegend=False
            )

            st.plotly_chart(fig, use_container_width=True)

    st.divider()

    # Recommendations
    st.markdown("### 💡 Trading Time Recommendations")

    recommendations = []

    # Find best hour
    best_hour = hourly_stats.head(1).index[0]
    best_hour_pl = hourly_stats.head(1)['Total P/L'].values[0]
    recommendations.append(f"🟢 **Best Hour:** {best_hour:02d}:00 (${best_hour_pl:.2f} total P/L)")

    # Find worst hour
    worst_hour = hourly_stats.tail(1).index[0]
    worst_hour_pl = hourly_stats.tail(1)['Total P/L'].values[0]
    if worst_hour_pl < -100:
        recommendations.append(f"🔴 **Avoid Hour:** {worst_hour:02d}:00 (${worst_hour_pl:.2f} total P/L)")

    # Find best day
    best_day = daily_stats.sort_values('Total P/L', ascending=False).head(1).index[0]
    best_day_pl = daily_stats.sort_values('Total P/L', ascending=False).head(1)['Total P/L'].values[0]
    recommendations.append(f"🟢 **Best Day:** {best_day} (${best_day_pl:.2f} total P/L)")

    # High activity times
    high_activity_hours = hourly_stats[hourly_stats['Trade Count'] >= 5].index.tolist()
    if high_activity_hours:
        recommendations.append(f"📊 **High Activity Hours:** {', '.join([f'{h:02d}:00' for h in high_activity_hours[:5]])}")

    for rec in recommendations:
        st.info(rec)

    st.divider()
