"""
P/L Calendar Heatmap Component
Visual calendar with color-coded daily P/L
"""

import streamlit as st
import pandas as pd
import plotly.graph_objects as go
import calendar
from datetime import datetime, timedelta
from utils.db_reader import DatabaseReader


def render(db: DatabaseReader):
    """Render P/L calendar heatmap"""
    st.subheader("📅 P/L Calendar")

    # Get all trades
    trades_df = db.get_trade_history(days=0)

    if trades_df.empty:
        st.info("No trade data available for calendar")
        return

    # Month selector
    col1, col2, col3 = st.columns([2, 2, 3])

    with col1:
        # Get available months from data
        trades_df['date'] = pd.to_datetime(trades_df['close_time']).dt.date
        trades_df['year_month'] = pd.to_datetime(trades_df['close_time']).dt.to_period('M')

        available_months = sorted(trades_df['year_month'].unique(), reverse=True)

        if available_months:
            selected_month_str = st.selectbox(
                "Select Month",
                [str(m) for m in available_months],
                key="calendar_month"
            )
            selected_month = pd.Period(selected_month_str)
        else:
            st.warning("No data available")
            return

    with col2:
        # View type
        view_type = st.selectbox(
            "View Type",
            ["P/L", "Win Rate", "Trade Count"],
            key="calendar_view"
        )

    # Filter trades for selected month
    month_trades = trades_df[trades_df['year_month'] == selected_month].copy()

    # Calculate daily metrics
    daily_stats = month_trades.groupby('date').agg({
        'profit': ['sum', 'count', lambda x: (x > 0).sum()]
    }).reset_index()

    daily_stats.columns = ['date', 'total_pl', 'trade_count', 'wins']
    daily_stats['win_rate'] = (daily_stats['wins'] / daily_stats['trade_count'] * 100).round(1)

    # Monthly summary
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        monthly_pl = daily_stats['total_pl'].sum()
        st.metric("Monthly P/L", f"${monthly_pl:,.2f}", delta_color="off")

    with col2:
        total_trades = daily_stats['trade_count'].sum()
        st.metric("Total Trades", int(total_trades))

    with col3:
        winning_days = len(daily_stats[daily_stats['total_pl'] > 0])
        total_days = len(daily_stats)
        win_rate = (winning_days / total_days * 100) if total_days > 0 else 0
        st.metric("Winning Days", f"{winning_days}/{total_days} ({win_rate:.0f}%)")

    with col4:
        best_day = daily_stats.loc[daily_stats['total_pl'].idxmax()] if not daily_stats.empty else None
        if best_day is not None:
            st.metric("Best Day", f"${best_day['total_pl']:.2f}")
        else:
            st.metric("Best Day", "$0.00")

    st.divider()

    # Create calendar heatmap
    year = selected_month.year
    month = selected_month.month

    # Get calendar for the month
    cal = calendar.monthcalendar(year, month)

    # Prepare data for heatmap
    day_names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

    # Create data matrix
    weeks = []
    hover_texts = []
    colors = []

    for week in cal:
        week_data = []
        week_hover = []
        week_colors = []

        for day in week:
            if day == 0:
                week_data.append(None)
                week_hover.append("")
                week_colors.append('#f0f0f0')
            else:
                date = pd.Timestamp(year=year, month=month, day=day).date()
                day_stats = daily_stats[daily_stats['date'] == date]

                if not day_stats.empty:
                    stat = day_stats.iloc[0]
                    pl = stat['total_pl']
                    trades = stat['trade_count']
                    wins = stat['wins']
                    wr = stat['win_rate']

                    if view_type == "P/L":
                        value = pl
                        hover = f"Date: {date}<br>P/L: ${pl:.2f}<br>Trades: {int(trades)}<br>Win Rate: {wr:.1f}%"

                        # Color based on P/L
                        if pl > 100:
                            color = '#006400'  # Dark green
                        elif pl > 0:
                            color = '#90EE90'  # Light green
                        elif pl > -100:
                            color = '#FFB6C1'  # Light red
                        else:
                            color = '#8B0000'  # Dark red

                    elif view_type == "Win Rate":
                        value = wr
                        hover = f"Date: {date}<br>Win Rate: {wr:.1f}%<br>Trades: {int(trades)}<br>P/L: ${pl:.2f}"

                        # Color based on win rate
                        if wr >= 70:
                            color = '#006400'
                        elif wr >= 50:
                            color = '#90EE90'
                        elif wr >= 30:
                            color = '#FFB6C1'
                        else:
                            color = '#8B0000'

                    else:  # Trade Count
                        value = trades
                        hover = f"Date: {date}<br>Trades: {int(trades)}<br>P/L: ${pl:.2f}<br>Win Rate: {wr:.1f}%"

                        # Color based on trade count
                        if trades >= 5:
                            color = '#006400'
                        elif trades >= 3:
                            color = '#90EE90'
                        elif trades >= 1:
                            color = '#FFD700'
                        else:
                            color = '#f0f0f0'

                    week_data.append(value)
                    week_hover.append(hover)
                    week_colors.append(color)
                else:
                    # No trades on this day
                    week_data.append(0)
                    week_hover.append(f"Date: {date}<br>No trades")
                    week_colors.append('#f0f0f0')

        weeks.append(week_data)
        hover_texts.append(week_hover)
        colors.append(week_colors)

    # Create heatmap figure
    fig = go.Figure()

    # Add traces for each week
    for week_idx, (week, hover, color) in enumerate(zip(weeks, hover_texts, colors)):
        for day_idx, (value, h, c) in enumerate(zip(week, hover, color)):
            if value is not None:
                fig.add_trace(go.Scatter(
                    x=[day_idx],
                    y=[len(weeks) - week_idx - 1],
                    mode='markers+text',
                    marker=dict(
                        size=80,
                        color=c,
                        line=dict(width=1, color='white')
                    ),
                    text=str(week[day_idx]) if week[day_idx] != 0 else cal[week_idx][day_idx],
                    textfont=dict(size=12, color='black' if c in ['#90EE90', '#FFD700', '#f0f0f0'] else 'white'),
                    hovertext=h,
                    hoverinfo='text',
                    showlegend=False
                ))

    # Update layout
    fig.update_layout(
        title=f"{calendar.month_name[month]} {year}",
        xaxis=dict(
            tickmode='array',
            tickvals=list(range(7)),
            ticktext=day_names,
            showgrid=False,
            zeroline=False
        ),
        yaxis=dict(
            showticklabels=False,
            showgrid=False,
            zeroline=False
        ),
        height=400,
        margin=dict(l=20, r=20, t=60, b=20),
        plot_bgcolor='white',
        hovermode='closest'
    )

    st.plotly_chart(fig, use_container_width=True)

    st.divider()

    # Daily breakdown table
    st.subheader("📊 Daily Breakdown")

    if not daily_stats.empty:
        # Format for display
        display_df = daily_stats.copy()
        display_df['date'] = pd.to_datetime(display_df['date']).dt.strftime('%Y-%m-%d (%a)')
        display_df['total_pl'] = display_df['total_pl'].apply(lambda x: f"${x:,.2f}")
        display_df['win_rate'] = display_df['win_rate'].apply(lambda x: f"{x:.1f}%")

        display_df = display_df.rename(columns={
            'date': 'Date',
            'total_pl': 'P/L',
            'trade_count': 'Trades',
            'wins': 'Wins',
            'win_rate': 'Win Rate'
        })

        display_df = display_df.sort_values('Date', ascending=False)

        st.dataframe(
            display_df,
            use_container_width=True,
            hide_index=True,
            height=400
        )

    # Best and worst days
    col1, col2 = st.columns(2)

    with col1:
        st.markdown("#### 🏆 Top 3 Best Days")
        best_days = daily_stats.nlargest(3, 'total_pl')
        for _, day in best_days.iterrows():
            st.success(f"**{day['date']}**: ${day['total_pl']:.2f} ({int(day['trade_count'])} trades)")

    with col2:
        st.markdown("#### 📉 Top 3 Worst Days")
        worst_days = daily_stats.nsmallest(3, 'total_pl')
        for _, day in worst_days.iterrows():
            st.error(f"**{day['date']}**: ${day['total_pl']:.2f} ({int(day['trade_count'])} trades)")

    st.divider()
