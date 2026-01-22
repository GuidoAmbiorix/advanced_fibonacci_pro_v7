import pandas as pd
import streamlit as st
import plotly.graph_objects as go
import plotly.express as px
from streamlit_lightweight_charts import renderLightweightCharts
from typing import List, Dict

class ChartBuilder:
    def __init__(self, data: pd.DataFrame):
        """
        data: DataFrame containing OHLCV data with a 'time' column.
        """
        self.data = data.copy()
        # Ensure time is formatted for lightweight-charts (unix timestamp or YYYY-MM-DD string)
        # We'll use formatting handled in the render phase or ensure it's passed correctly.
        
    def render_with_markers(self, title: str = "Price Action", markers: List[Dict] = [], height: int = 500):
        if self.data.empty:
            st.error("No data to render chart")
            return None

        # Prepare Candle Data
        candle_data = []
        for index, row in self.data.iterrows():
            candle_data.append({
                "time": row['time'].strftime('%Y-%m-%d %H:%M:%S') if pd.api.types.is_datetime64_any_dtype(self.data['time']) else row['time'],
                "open": row['open'],
                "high": row['high'],
                "low": row['low'],
                "close": row['close']
            })

        # Chart Options
        chartOptions = {
            "layout": {
                "textColor": "#d1d4dc",
                "backgroundColor": "#131722",
                "fontFamily": "Inter"
            },
            "grid": {
                "vertLines": {"color": "rgba(42, 46, 57, 0.2)"},
                "horzLines": {"color": "rgba(42, 46, 57, 0.2)"}
            },
            "height": height,
            "rightPriceScale": {
                "scaleMargins": {
                    "top": 0.3,
                    "bottom": 0.25,
                },
                "borderVisible": False,
            },
        }
        
        series = [
            {
                "type": "Candlestick",
                "data": candle_data,
                "options": {
                    "upColor": "#26a69a",
                    "downColor": "#ef5350",
                    "borderVisible": False,
                    "wickUpColor": "#26a69a",
                    "wickDownColor": "#ef5350"
                },
                "markers": markers  # Inject markers here
            }
        ]

        return renderLightweightCharts([
            {
                "chart": chartOptions,
                "series": series
            }
        ], key=f"chart_{title}")

    def add_markers(self, trades: pd.DataFrame):
        """
        Adds Buy/Sell markers to the chart series.
        This would be an enhancement to the series configuration object before rendering.
        """
        markers = []
        for _, trade in trades.iterrows():
            # ENTRY Marker
            markers.append({
                "time": trade['entry_time'].strftime('%Y-%m-%d %H:%M:%S'),
                "position": "belowBar" if trade['direction'] == "BUY" else "aboveBar",
                "color": "#2196F3" if trade['direction'] == "BUY" else "#E91E63",
                "shape": "arrowUp" if trade['direction'] == "BUY" else "arrowDown",
                "text": f"ENTRY {trade['ticket']}"
            })
            
            # EXIT Marker
            markers.append({
                "time": trade['exit_time'].strftime('%Y-%m-%d %H:%M:%S'),
                "position": "aboveBar" if trade['direction'] == "BUY" else "belowBar",
                "color": "#FF9800",
                "shape": "circle",
                "text": f"EXIT {trade['profit']:.2f}"
            })
        return markers


def render_equity_curve(equity_df: pd.DataFrame):
    """
    Render equity curve with drawdown overlay.

    Args:
        equity_df: DataFrame with columns: timestamp, equity, drawdown, drawdown_pct
    """
    if equity_df.empty:
        st.warning("No equity data available")
        return

    fig = go.Figure()

    # Equity line
    fig.add_trace(go.Scatter(
        x=equity_df['timestamp'],
        y=equity_df['equity'],
        mode='lines',
        name='Equity',
        line=dict(color='#2196F3', width=2),
        fill='tonexty',
        fillcolor='rgba(33, 150, 243, 0.1)'
    ))

    # Peak equity line
    fig.add_trace(go.Scatter(
        x=equity_df['timestamp'],
        y=equity_df['peak_equity'],
        mode='lines',
        name='Peak Equity',
        line=dict(color='#4CAF50', width=1, dash='dot'),
        opacity=0.6
    ))

    fig.update_layout(
        title='Equity Curve',
        xaxis_title='Date',
        yaxis_title='Equity ($)',
        template='plotly_dark',
        height=400,
        hovermode='x unified',
        showlegend=True,
        legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1)
    )

    st.plotly_chart(fig, use_container_width=True)


def render_drawdown_chart(equity_df: pd.DataFrame):
    """
    Render underwater equity curve (drawdown chart).

    Args:
        equity_df: DataFrame with columns: timestamp, drawdown, drawdown_pct
    """
    if equity_df.empty:
        st.warning("No drawdown data available")
        return

    fig = go.Figure()

    fig.add_trace(go.Scatter(
        x=equity_df['timestamp'],
        y=-equity_df['drawdown_pct'],
        mode='lines',
        name='Drawdown %',
        line=dict(color='#ef5350', width=2),
        fill='tozeroy',
        fillcolor='rgba(239, 83, 80, 0.3)'
    ))

    fig.update_layout(
        title='Drawdown (Underwater Equity)',
        xaxis_title='Date',
        yaxis_title='Drawdown (%)',
        template='plotly_dark',
        height=300,
        hovermode='x unified',
        showlegend=False
    )

    # Add zero line
    fig.add_hline(y=0, line_dash="dash", line_color="gray", opacity=0.5)

    st.plotly_chart(fig, use_container_width=True)


def render_profit_distribution(distribution_df: pd.DataFrame):
    """
    Render profit distribution histogram.

    Args:
        distribution_df: DataFrame with profit_bucket and count columns
    """
    if distribution_df.empty:
        st.warning("No distribution data available")
        return

    fig = px.bar(
        distribution_df,
        x='profit_bucket',
        y='count',
        title='Profit Distribution',
        labels={'profit_bucket': 'Profit Range ($)', 'count': 'Number of Trades'},
        color='count',
        color_continuous_scale='RdYlGn'
    )

    fig.update_layout(
        template='plotly_dark',
        height=350,
        showlegend=False
    )

    st.plotly_chart(fig, use_container_width=True)


def render_symbol_performance(symbol_stats: pd.DataFrame):
    """
    Render symbol performance comparison.

    Args:
        symbol_stats: DataFrame with symbol statistics
    """
    if symbol_stats.empty:
        st.warning("No symbol data available")
        return

    fig = go.Figure()

    # Total PnL bars
    colors = ['#4CAF50' if pnl > 0 else '#ef5350' for pnl in symbol_stats['total_pnl']]

    fig.add_trace(go.Bar(
        x=symbol_stats['symbol'],
        y=symbol_stats['total_pnl'],
        name='Total P&L',
        marker_color=colors,
        text=symbol_stats['total_pnl'].round(2),
        textposition='outside'
    ))

    fig.update_layout(
        title='Performance by Symbol',
        xaxis_title='Symbol',
        yaxis_title='Total P&L ($)',
        template='plotly_dark',
        height=400,
        showlegend=False
    )

    st.plotly_chart(fig, use_container_width=True)


def render_time_analysis(time_stats: Dict[str, pd.DataFrame]):
    """
    Render time-based performance analysis.

    Args:
        time_stats: Dict with 'by_hour' and 'by_day' DataFrames
    """
    col1, col2 = st.columns(2)

    with col1:
        if not time_stats['by_hour'].empty:
            fig = px.bar(
                time_stats['by_hour'],
                x='hour',
                y='total_pnl',
                title='Performance by Hour of Day',
                labels={'hour': 'Hour', 'total_pnl': 'Total P&L ($)'},
                color='total_pnl',
                color_continuous_scale='RdYlGn'
            )
            fig.update_layout(template='plotly_dark', height=350)
            st.plotly_chart(fig, use_container_width=True)

    with col2:
        if not time_stats['by_day'].empty:
            fig = px.bar(
                time_stats['by_day'],
                x='day_of_week',
                y='total_pnl',
                title='Performance by Day of Week',
                labels={'day_of_week': 'Day', 'total_pnl': 'Total P&L ($)'},
                color='total_pnl',
                color_continuous_scale='RdYlGn'
            )
            fig.update_layout(template='plotly_dark', height=350)
            st.plotly_chart(fig, use_container_width=True)


def render_monthly_performance(trades_df: pd.DataFrame):
    """
    Render monthly performance heatmap.

    Args:
        trades_df: DataFrame with trade history
    """
    if trades_df.empty:
        st.warning("No trade data available")
        return

    df = trades_df.copy()
    df['total_profit'] = df['profit'] + df['commission'] + df['swap']
    df['year_month'] = df['exit_time'].dt.to_period('M').astype(str)

    monthly = df.groupby('year_month')['total_profit'].sum().reset_index()

    fig = go.Figure()

    colors = ['#4CAF50' if pnl > 0 else '#ef5350' for pnl in monthly['total_profit']]

    fig.add_trace(go.Bar(
        x=monthly['year_month'],
        y=monthly['total_profit'],
        marker_color=colors,
        text=monthly['total_profit'].round(2),
        textposition='outside'
    ))

    fig.update_layout(
        title='Monthly Performance',
        xaxis_title='Month',
        yaxis_title='P&L ($)',
        template='plotly_dark',
        height=350,
        showlegend=False
    )

    st.plotly_chart(fig, use_container_width=True)
