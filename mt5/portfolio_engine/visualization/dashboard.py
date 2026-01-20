"""
Dashboard
Multi-symbol portfolio dashboard using lightweight-charts.
"""

from typing import Dict, List, Optional, Any
import pandas as pd
import numpy as np
from datetime import datetime
import asyncio

try:
    from lightweight_charts import Chart
    CHARTS_AVAILABLE = True
except ImportError:
    CHARTS_AVAILABLE = False


class Dashboard:
    """
    Multi-symbol portfolio dashboard.
    
    Features:
    - Multiple synchronized charts
    - Portfolio metrics display
    - Trade table
    - Real-time updates (live mode)
    """
    
    def __init__(self, symbols: List[str], layout: str = "2x2"):
        """
        Initialize dashboard.
        
        Args:
            symbols: List of symbols to display
            layout: Layout pattern ('2x2', '3x1', '1x3', etc.)
        """
        if not CHARTS_AVAILABLE:
            raise ImportError("lightweight-charts is required")
        
        self.symbols = symbols
        self.layout = layout
        
        # Parse layout
        rows, cols = self._parse_layout(layout)
        self.rows = rows
        self.cols = cols
        
        # Create main chart (first symbol)
        self.main_chart = Chart(toolbox=True)
        
        # Create subcharts for other symbols
        self.charts: Dict[str, Any] = {}
        self.charts[symbols[0]] = self.main_chart
        
        self._create_layout()
        
        # Metrics display
        self._setup_topbar()
        
        # Table for positions
        self.position_table = None
    
    def _parse_layout(self, layout: str) -> tuple:
        """Parse layout string to rows x cols."""
        parts = layout.lower().split('x')
        if len(parts) == 2:
            return int(parts[0]), int(parts[1])
        return 2, 2  # Default
    
    def _create_layout(self):
        """Create sub-charts based on layout."""
        # Calculate positions for each symbol
        positions = ['right', 'bottom', 'bottom']
        
        for i, symbol in enumerate(self.symbols[1:]):
            if i >= len(positions):
                break
            
            pos = positions[i]
            height = 0.5 if pos == 'bottom' else 1.0
            width = 0.5 if pos == 'right' else 1.0
            
            subchart = self.main_chart.create_subchart(
                position=pos,
                width=width,
                height=height,
                sync=True,  # Sync crosshairs
            )
            
            self.charts[symbol] = subchart
    
    def _setup_topbar(self):
        """Setup topbar with metrics and controls."""
        # Symbol switcher
        self.main_chart.topbar.switcher(
            name='symbol',
            options=tuple(self.symbols),
            default=self.symbols[0],
            func=self._on_symbol_change
        )
        
        # Timeframe switcher
        self.main_chart.topbar.switcher(
            name='timeframe',
            options=('M5', 'M15', 'H1', 'H4', 'D1'),
            default='M15',
            func=self._on_timeframe_change
        )
        
        # Metrics display
        self.main_chart.topbar.textbox('equity', '$0.00')
        self.main_chart.topbar.textbox('dd', 'DD: 0.0%')
        self.main_chart.topbar.textbox('pf', 'PF: 0.00')
        self.main_chart.topbar.textbox('positions', 'Pos: 0')
    
    def _on_symbol_change(self, chart):
        """Handle symbol change from topbar."""
        selected = chart.topbar['symbol'].value
        print(f"Symbol changed to: {selected}")
        # Callback to load new data would go here
    
    def _on_timeframe_change(self, chart):
        """Handle timeframe change from topbar."""
        selected = chart.topbar['timeframe'].value
        print(f"Timeframe changed to: {selected}")
        # Callback to load new data would go here
    
    def set_symbol_data(self, symbol: str, df: pd.DataFrame):
        """
        Set data for a specific symbol chart.
        
        Args:
            symbol: Symbol name
            df: OHLCV DataFrame
        """
        if symbol not in self.charts:
            return
        
        chart = self.charts[symbol]
        
        # Normalize columns
        chart_df = df.copy()
        chart_df.columns = chart_df.columns.str.lower()
        
        if 'time' not in chart_df.columns:
            chart_df = chart_df.reset_index()
            if 'index' in chart_df.columns:
                chart_df = chart_df.rename(columns={'index': 'time'})
            elif 'date' in chart_df.columns:
                chart_df = chart_df.rename(columns={'date': 'time'})
        
        chart.set(chart_df)
        
        # Add legend
        chart.legend(visible=True)
        chart.watermark(symbol, color='rgba(255,255,255,0.1)')
    
    def update_metrics(
        self,
        equity: float,
        dd: float,
        pf: float,
        positions: int
    ):
        """Update metrics display in topbar."""
        self.main_chart.topbar['equity'].set(f'${equity:,.2f}')
        self.main_chart.topbar['dd'].set(f'DD: {dd:.1f}%')
        self.main_chart.topbar['pf'].set(f'PF: {pf:.2f}')
        self.main_chart.topbar['positions'].set(f'Pos: {positions}')
    
    def add_position_table(self):
        """Add a table showing open positions."""
        self.position_table = self.main_chart.create_table(
            width=0.3,
            height=0.3,
            headings=['Symbol', 'Dir', 'Entry', 'P/L'],
            widths=[0.25, 0.15, 0.3, 0.3],
            alignments=['center', 'center', 'right', 'right'],
        )
        return self.position_table
    
    def update_position_table(self, positions: List[Dict]):
        """
        Update positions table.
        
        Args:
            positions: List of position dictionaries
        """
        if self.position_table is None:
            self.add_position_table()
        
        # Clear existing rows
        self.position_table.clear()
        
        # Add position rows
        for pos in positions:
            direction = '🟢' if pos['direction'] == 1 else '🔴'
            pnl_color = 'rgba(38, 166, 154, 1)' if pos['pnl'] >= 0 else 'rgba(239, 83, 80, 1)'
            
            self.position_table.new_row(
                pos['symbol'],
                direction,
                f"{pos['entry_price']:.5f}",
                f"${pos['pnl']:+.2f}"
            )
    
    def add_trade_markers(self, symbol: str, trades: list):
        """Add trade entry/exit markers to a symbol chart."""
        if symbol not in self.charts:
            return
        
        chart = self.charts[symbol]
        
        for trade in trades:
            # Entry
            shape = 'arrow_up' if trade.direction == 1 else 'arrow_down'
            position = 'below' if trade.direction == 1 else 'above'
            
            chart.marker(
                time=trade.entry_time,
                position=position,
                shape=shape,
                color='#2196f3',
                text='Entry'
            )
            
            # Exit
            exit_color = '#26a69a' if trade.profit > 0 else '#ef5350'
            chart.marker(
                time=trade.exit_time,
                position='above' if trade.direction == 1 else 'below',
                shape='arrow_down' if trade.direction == 1 else 'arrow_up',
                color=exit_color,
                text=f'{trade.profit_r:+.1f}R'
            )
    
    def show(self, block: bool = True):
        """Display the dashboard."""
        self.main_chart.show(block=block)
    
    async def show_async(self):
        """Display dashboard asynchronously for live updates."""
        await self.main_chart.show_async()
    
    async def run_live(self, update_callback, interval_seconds: float = 1.0):
        """
        Run dashboard with live updates.
        
        Args:
            update_callback: Async function to get new data
            interval_seconds: Update interval
        """
        async def update_loop():
            while self.main_chart.is_alive:
                await asyncio.sleep(interval_seconds)
                
                try:
                    data = await update_callback()
                    
                    # Update charts with new data
                    for symbol, df in data.get('ohlcv', {}).items():
                        self.set_symbol_data(symbol, df)
                    
                    # Update metrics
                    if 'metrics' in data:
                        m = data['metrics']
                        self.update_metrics(
                            m.get('equity', 0),
                            m.get('dd', 0),
                            m.get('pf', 0),
                            m.get('positions', 0)
                        )
                    
                    # Update positions
                    if 'positions' in data:
                        self.update_position_table(data['positions'])
                        
                except Exception as e:
                    print(f"Update error: {e}")
        
        await asyncio.gather(
            self.main_chart.show_async(),
            update_loop()
        )
