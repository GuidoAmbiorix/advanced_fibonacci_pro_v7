"""
Chart Manager
Wrapper for lightweight-charts-python with trading-specific features.
"""

from typing import Dict, List, Optional, Any
import pandas as pd
import numpy as np
from datetime import datetime

try:
    from lightweight_charts import Chart
    CHARTS_AVAILABLE = True
except ImportError:
    CHARTS_AVAILABLE = False
    print("Warning: lightweight-charts not installed. Run: pip install lightweight-charts")


class ChartManager:
    """
    Chart manager for trading visualization using lightweight-charts-python.
    
    Features:
    - OHLCV candlestick display
    - Indicator lines (EMA, RSI, etc.)
    - Trade markers (entries, exits)
    - Fibonacci zones
    - Horizontal levels
    """
    
    def __init__(self, title: str = "Trading Chart", toolbox: bool = True):
        """
        Initialize chart manager.
        
        Args:
            title: Chart window title
            toolbox: Enable drawing toolbox
        """
        if not CHARTS_AVAILABLE:
            raise ImportError("lightweight-charts is required")
        
        self.title = title
        self.chart = Chart(toolbox=toolbox)
        self.indicators: Dict[str, Any] = {}
        self.subcharts: Dict[str, Any] = {}
        
        # Configure legend
        self.chart.legend(visible=True, font_size=12)
    
    def set_data(self, df: pd.DataFrame, keep_drawings: bool = False):
        """
        Set OHLCV data on the chart.
        
        Args:
            df: DataFrame with columns: time/date, open, high, low, close, volume
            keep_drawings: Keep any existing drawings
        """
        # Normalize column names
        chart_df = df.copy()
        chart_df.columns = chart_df.columns.str.lower()
        
        # Ensure required columns
        if 'time' not in chart_df.columns and 'date' not in chart_df.columns:
            if chart_df.index.name in ['time', 'date'] or isinstance(chart_df.index, pd.DatetimeIndex):
                chart_df = chart_df.reset_index()
                if 'index' in chart_df.columns:
                    chart_df = chart_df.rename(columns={'index': 'time'})
        
        # Rename date to time if needed
        if 'date' in chart_df.columns and 'time' not in chart_df.columns:
            chart_df = chart_df.rename(columns={'date': 'time'})
        
        self.chart.set(chart_df, keep_drawings=keep_drawings)
    
    def add_line(
        self,
        name: str,
        data: pd.DataFrame,
        color: str = 'blue',
        width: int = 2,
        style: str = 'solid'
    ):
        """
        Add a line indicator to the chart.
        
        Args:
            name: Indicator name
            data: DataFrame with 'time' and value column
            color: Line color
            width: Line width
            style: 'solid', 'dashed', 'dotted'
        """
        line = self.chart.create_line(name=name)
        
        # Configure line style
        line_style = 0 if style == 'solid' else (1 if style == 'dashed' else 2)
        
        self.indicators[name] = line
        line.set(data)
    
    def add_ema(self, prices: pd.Series, period: int, color: str = '#2962FF'):
        """Add EMA indicator line."""
        ema = prices.ewm(span=period, adjust=False).mean()
        
        ema_df = pd.DataFrame({
            'time': prices.index if hasattr(prices, 'index') else range(len(prices)),
            f'EMA {period}': ema
        })
        
        self.add_line(f'EMA {period}', ema_df, color=color)
    
    def add_trade_marker(
        self,
        time: datetime,
        price: float,
        direction: int,
        label: str = "",
        color: str = None
    ):
        """
        Add a trade entry/exit marker.
        
        Args:
            time: Marker time
            price: Price level
            direction: 1 for buy, -1 for sell
            label: Text label
            color: Override color
        """
        if direction == 1:
            shape = 'arrow_up'
            default_color = '#26a69a'  # Green
            position = 'below'
        else:
            shape = 'arrow_down'
            default_color = '#ef5350'  # Red
            position = 'above'
        
        self.chart.marker(
            time=time,
            position=position,
            shape=shape,
            color=color or default_color,
            text=label
        )
    
    def add_horizontal_line(
        self,
        price: float,
        color: str = '#888888',
        label: str = "",
        style: str = 'dashed'
    ):
        """Add a horizontal price line."""
        line_style = 0 if style == 'solid' else (1 if style == 'dashed' else 2)
        
        self.chart.horizontal_line(
            price=price,
            color=color,
            style=line_style,
            text=label
        )
    
    def add_fib_zone(
        self,
        start_time: datetime,
        end_time: datetime,
        high: float,
        low: float,
        colors: Dict[float, str] = None
    ):
        """
        Add Fibonacci retracement zone.
        
        Args:
            start_time: Zone start time
            end_time: Zone end time
            high: Swing high
            low: Swing low
            colors: Custom colors for levels
        """
        default_colors = {
            0.236: '#787b86',
            0.382: '#f3be00',
            0.5: '#f3be00',
            0.618: '#ff5252',
            0.786: '#ff5252',
        }
        
        colors = colors or default_colors
        range_val = high - low
        
        for level, color in colors.items():
            price = high - (range_val * level)
            self.add_horizontal_line(price, color=color, label=f'{level:.3f}', style='dashed')
    
    def add_vertical_span(
        self,
        start_time: datetime,
        end_time: datetime = None,
        color: str = 'rgba(255, 255, 224, 0.3)'
    ):
        """Add a vertical span (e.g., session highlight)."""
        if end_time:
            self.chart.vertical_span(start_time=start_time, end_time=end_time, color=color)
        else:
            self.chart.vertical_span(start_time=start_time, color=color)
    
    def create_rsi_subchart(self, height: float = 0.2, sync: bool = True):
        """
        Create a subchart for RSI indicator.
        
        Args:
            height: Chart height (0-1)
            sync: Sync time axis with main chart
        """
        subchart = self.chart.create_subchart(
            position='bottom',
            height=height,
            sync=sync
        )
        
        # Add overbought/oversold lines
        subchart.horizontal_line(70, color='#ef5350', style=1)
        subchart.horizontal_line(30, color='#26a69a', style=1)
        subchart.horizontal_line(50, color='#888888', style=2)
        
        self.subcharts['rsi'] = subchart
        return subchart
    
    def set_rsi_data(self, rsi_df: pd.DataFrame):
        """Set RSI data on subchart."""
        if 'rsi' not in self.subcharts:
            self.create_rsi_subchart()
        
        line = self.subcharts['rsi'].create_line(name='RSI')
        line.set(rsi_df)
    
    def add_topbar_text(self, name: str, text: str):
        """Add text display to chart topbar."""
        self.chart.topbar.textbox(name, text)
    
    def add_topbar_switcher(
        self,
        name: str,
        options: tuple,
        default: str,
        callback=None
    ):
        """Add a switcher to topbar."""
        self.chart.topbar.switcher(
            name=name,
            options=options,
            default=default,
            func=callback
        )
    
    def show(self, block: bool = True):
        """Display the chart."""
        self.chart.show(block=block)
    
    async def show_async(self):
        """Display chart asynchronously."""
        await self.chart.show_async()
    
    def screenshot(self, path: str):
        """Save chart screenshot."""
        self.chart.screenshot(path)
    
    def clear(self):
        """Clear all data and indicators."""
        self.chart.set(None)
        self.indicators.clear()


def plot_backtest_results(
    df: pd.DataFrame,
    trades: list,
    title: str = "Backtest Results"
):
    """
    Convenience function to plot backtest results.
    
    Args:
        df: OHLCV DataFrame
        trades: List of Trade objects
        title: Chart title
    """
    cm = ChartManager(title=title)
    cm.set_data(df)
    
    # Add trade markers
    for trade in trades:
        # Entry marker
        cm.add_trade_marker(
            time=trade.entry_time,
            price=trade.entry_price,
            direction=trade.direction,
            label="Entry"
        )
        
        # Exit marker
        if trade.direction == 1:
            exit_color = '#26a69a' if trade.profit > 0 else '#ef5350'
        else:
            exit_color = '#26a69a' if trade.profit > 0 else '#ef5350'
        
        cm.add_trade_marker(
            time=trade.exit_time,
            price=trade.exit_price,
            direction=-trade.direction,
            label=f"{'Win' if trade.profit > 0 else 'Loss'}",
            color=exit_color
        )
    
    return cm
