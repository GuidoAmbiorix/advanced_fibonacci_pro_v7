"""
Advanced Performance Analytics Component
Detailed performance breakdown and analysis
"""

import streamlit as st
import pandas as pd
import plotly.graph_objects as go
import plotly.express as px
from utils.db_reader import DatabaseReader
from utils.metrics import get_performance_summary


def render(db: DatabaseReader):
    """Render advanced performance analytics"""
    st.subheader("📈 Performance Analytics")

    trades_df = db.get_trade_history(days=0)  # All history

    if trades_df.empty:
        st.info("No trade data available for analysis")
        return

    # Get comprehensive performance summary
    account_summary = db.get_account_summary()
    perf = get_performance_summary(trades_df, account_summary)

    # Display key metrics in columns
    col1, col2, col3, col4, col5 = st.columns(5)

    with col1:
        st.metric("Total Trades", perf['total_trades'])

    with col2:
        st.metric("Win Rate", f"{perf['win_rate']:.1f}%")

    with col3:
        st.metric("Profit Factor", f"{perf['profit_factor']:.2f}")

    with col4:
        st.metric("Expectancy", f"${perf['expectancy']:.2f}")

    with col5:
        st.metric("Sharpe Ratio", f"{perf['sharpe_ratio']:.2f}")

    st.divider()

    # Second row of metrics
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        st.metric("Avg Win", f"${perf['avg_win']:.2f}", delta_color="off")

    with col2:
        st.metric("Avg Loss", f"${perf['avg_loss']:.2f}", delta_color="off")

    with col3:
        st.metric("Best Trade", f"${perf['best_trade']:.2f}", delta_color="off")

    with col4:
        st.metric("Worst Trade", f"${perf['worst_trade']:.2f}", delta_color="off")

    st.divider()

    # Streaks
    col1, col2, col3 = st.columns(3)

    with col1:
        st.metric("Max Consecutive Wins", perf['max_consecutive_wins'])

    with col2:
        st.metric("Max Consecutive Losses", perf['max_consecutive_losses'])

    with col3:
        streak = perf['current_streak']
        streak_text = f"{abs(streak)} {'Wins' if streak > 0 else 'Losses'}"
        st.metric("Current Streak", streak_text, delta_color="off")

    st.divider()

    # Charts
    col1, col2 = st.columns(2)

    with col1:
        # Win/Loss distribution
        st.subheader("Win/Loss Distribution")
        wins = len(trades_df[trades_df['profit'] > 0])
        losses = len(trades_df[trades_df['profit'] <= 0])

        fig = go.Figure(data=[go.Pie(
            labels=['Wins', 'Losses'],
            values=[wins, losses],
            marker=dict(colors=['#00cc96', '#ef553b']),
            hole=0.4
        )])
        fig.update_layout(
            showlegend=True,
            height=300,
            margin=dict(l=0, r=0, t=0, b=0)
        )
        st.plotly_chart(fig, use_container_width=True)

    with col2:
        # Profit distribution
        st.subheader("Profit Distribution")
        fig = go.Figure()

        # Add histogram
        fig.add_trace(go.Histogram(
            x=trades_df['profit'],
            nbinsx=30,
            marker=dict(
                color=trades_df['profit'],
                colorscale='RdYlGn',
                line=dict(width=0.5, color='white')
            ),
            showlegend=False
        ))

        fig.update_layout(
            xaxis_title="Profit/Loss ($)",
            yaxis_title="Frequency",
            height=300,
            margin=dict(l=0, r=0, t=0, b=0),
            showlegend=False
        )
        st.plotly_chart(fig, use_container_width=True)

    # Performance by time
    st.subheader("Performance Over Time")

    # Daily P/L
    if 'close_time' in trades_df.columns:
        trades_df['date'] = pd.to_datetime(trades_df['close_time']).dt.date
        daily_pl = trades_df.groupby('date')['profit'].sum().reset_index()
        daily_pl['cumulative'] = daily_pl['profit'].cumsum()

        fig = go.Figure()

        # Bar chart for daily P/L
        colors = ['green' if x > 0 else 'red' for x in daily_pl['profit']]
        fig.add_trace(go.Bar(
            x=daily_pl['date'],
            y=daily_pl['profit'],
            name='Daily P/L',
            marker_color=colors,
            yaxis='y'
        ))

        # Line chart for cumulative
        fig.add_trace(go.Scatter(
            x=daily_pl['date'],
            y=daily_pl['cumulative'],
            name='Cumulative P/L',
            line=dict(color='blue', width=2),
            yaxis='y2'
        ))

        fig.update_layout(
            xaxis_title="Date",
            yaxis=dict(title="Daily P/L ($)", side='left'),
            yaxis2=dict(title="Cumulative P/L ($)", overlaying='y', side='right'),
            hovermode='x unified',
            height=400,
            legend=dict(x=0, y=1),
            margin=dict(l=0, r=0, t=20, b=0)
        )

        st.plotly_chart(fig, use_container_width=True)

    # Performance by hour of day
    col1, col2 = st.columns(2)

    with col1:
        st.subheader("Performance by Hour")
        if 'entry_time' in trades_df.columns:
            trades_df['hour'] = pd.to_datetime(trades_df['entry_time']).dt.hour
            hourly_perf = trades_df.groupby('hour')['profit'].agg(['sum', 'count']).reset_index()

            fig = go.Figure()
            fig.add_trace(go.Bar(
                x=hourly_perf['hour'],
                y=hourly_perf['sum'],
                marker=dict(
                    color=hourly_perf['sum'],
                    colorscale='RdYlGn',
                    showscale=True
                )
            ))

            fig.update_layout(
                xaxis_title="Hour of Day",
                yaxis_title="Total P/L ($)",
                height=300,
                margin=dict(l=0, r=0, t=0, b=0)
            )
            st.plotly_chart(fig, use_container_width=True)

    with col2:
        st.subheader("Performance by Day of Week")
        if 'entry_time' in trades_df.columns:
            trades_df['weekday'] = pd.to_datetime(trades_df['entry_time']).dt.day_name()
            day_order = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
            trades_df['weekday'] = pd.Categorical(trades_df['weekday'], categories=day_order, ordered=True)

            daily_perf = trades_df.groupby('weekday', observed=True)['profit'].agg(['sum', 'count']).reset_index()

            fig = go.Figure()
            fig.add_trace(go.Bar(
                x=daily_perf['weekday'],
                y=daily_perf['sum'],
                marker=dict(
                    color=daily_perf['sum'],
                    colorscale='RdYlGn',
                    showscale=True
                )
            ))

            fig.update_layout(
                xaxis_title="Day of Week",
                yaxis_title="Total P/L ($)",
                height=300,
                margin=dict(l=0, r=0, t=0, b=0)
            )
            st.plotly_chart(fig, use_container_width=True)

    # Performance by regime and killzone
    col1, col2 = st.columns(2)

    with col1:
        st.subheader("Performance by Regime")
        if 'regime' in trades_df.columns:
            regime_perf = trades_df.groupby('regime')['profit'].agg(['sum', 'count', 'mean']).reset_index()
            regime_perf = regime_perf.sort_values('sum', ascending=False)

            fig = go.Figure()
            fig.add_trace(go.Bar(
                x=regime_perf['regime'],
                y=regime_perf['sum'],
                text=[f"${x:.2f}<br>({int(c)} trades)" for x, c in zip(regime_perf['sum'], regime_perf['count'])],
                textposition='outside',
                marker=dict(
                    color=regime_perf['sum'],
                    colorscale='RdYlGn'
                )
            ))

            fig.update_layout(
                xaxis_title="Market Regime",
                yaxis_title="Total P/L ($)",
                height=300,
                margin=dict(l=0, r=0, t=30, b=0)
            )
            st.plotly_chart(fig, use_container_width=True)

    with col2:
        st.subheader("Performance by Killzone")
        if 'killzone' in trades_df.columns:
            kz_perf = trades_df.groupby('killzone')['profit'].agg(['sum', 'count', 'mean']).reset_index()
            kz_perf = kz_perf.sort_values('sum', ascending=False)

            fig = go.Figure()
            fig.add_trace(go.Bar(
                x=kz_perf['killzone'],
                y=kz_perf['sum'],
                text=[f"${x:.2f}<br>({int(c)} trades)" for x, c in zip(kz_perf['sum'], kz_perf['count'])],
                textposition='outside',
                marker=dict(
                    color=kz_perf['sum'],
                    colorscale='RdYlGn'
                )
            ))

            fig.update_layout(
                xaxis_title="Killzone",
                yaxis_title="Total P/L ($)",
                height=300,
                margin=dict(l=0, r=0, t=30, b=0)
            )
            st.plotly_chart(fig, use_container_width=True)

    st.divider()
