"""
Backtest Engine
Bar-by-bar backtesting engine for multi-symbol portfolio strategies.
"""

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Any, Type
from datetime import datetime, timedelta
import pandas as pd
import numpy as np
import yaml

import sys
sys.path.append('..')

from symbols.base_agent import BaseAgent, Signal, SignalType, Position
from portfolio.governor import PortfolioGovernor, Trade
from portfolio.exposure import ExposureTracker, OpenPosition
from portfolio.metrics import generate_performance_report


@dataclass
class BacktestConfig:
    """Backtest configuration."""
    start_date: datetime
    end_date: datetime
    initial_equity: float = 10000.0
    spread_pips: Dict[str, float] = field(default_factory=dict)
    commission_per_lot: float = 0.0
    slippage_pips: float = 0.0


@dataclass
class BacktestResult:
    """Backtest results container."""
    config: BacktestConfig
    trades: List[Trade]
    equity_curve: np.ndarray
    timestamps: List[datetime]
    metrics: Dict[str, Any]
    symbol_trades: Dict[str, List[Trade]]
    
    def summary(self) -> str:
        """Generate summary string."""
        m = self.metrics
        return f"""
═══════════════════════════════════════════════════
  📊 BACKTEST RESULTS
═══════════════════════════════════════════════════
Period: {self.config.start_date.date()} → {self.config.end_date.date()}
Initial Equity: ${self.config.initial_equity:,.2f}
Final Equity: ${self.equity_curve[-1]:,.2f}
───────────────────────────────────────────────────
Total Trades: {m.get('total_trades', 0)}
Win Rate: {m.get('win_rate', 0):.1f}%
Profit Factor: {m.get('profit_factor', 0):.2f}
Expected Value (R): {m.get('expectancy_r', 0):.2f}
───────────────────────────────────────────────────
Max Drawdown: {m.get('max_drawdown', 0):.2f}%
Sharpe Ratio: {m.get('sharpe_ratio', 0):.2f}
Net Profit: ${m.get('net_profit', 0):,.2f}
───────────────────────────────────────────────────
Largest Win (R): {m.get('largest_win_r', 0):.1f}
Largest Loss (R): {m.get('largest_loss_r', 0):.1f}
Max Consecutive Losses: {m.get('max_consecutive_losses', 0)}
═══════════════════════════════════════════════════
"""


class BacktestEngine:
    """
    Multi-symbol portfolio backtesting engine.
    
    Features:
    - Bar-by-bar simulation
    - Portfolio-level risk management
    - Correlation group tracking
    - Partial closes and trailing
    """
    
    def __init__(
        self,
        agents: Dict[str, BaseAgent],
        governor: PortfolioGovernor,
        config: BacktestConfig
    ):
        """
        Initialize backtest engine.
        
        Args:
            agents: Dictionary of symbol -> agent
            governor: Portfolio governor instance
            config: Backtest configuration
        """
        self.agents = agents
        self.governor = governor
        self.config = config
        
        # Data storage
        self.data: Dict[str, pd.DataFrame] = {}
        
        # State
        self.current_time: Optional[datetime] = None
        self.equity = config.initial_equity
        self.equity_curve: List[float] = []
        self.timestamps: List[datetime] = []
        
        # Trade tracking
        self.open_positions: Dict[int, dict] = {}  # ticket -> position data
        self.closed_trades: List[Trade] = []
        self.next_ticket = 1
        
        # Risk config
        self.risk_config = self._load_risk_config()
    
    def _load_risk_config(self) -> Dict[str, Any]:
        """Load risk configuration."""
        try:
            with open('config/risk.yaml', 'r') as f:
                return yaml.safe_load(f)
        except:
            return {
                'exit_strategy': {
                    'partial_tp_r': 1.5,
                    'partial_close_pct': 40,
                    'be_threshold_r': 1.8,
                    'trail_start_r': 2.0,
                    'trail_atr_mult': 1.2,
                }
            }
    
    def load_data(self, symbol: str, df: pd.DataFrame):
        """
        Load historical data for a symbol.
        
        Args:
            symbol: Symbol name
            df: DataFrame with OHLCV data
        """
        # Ensure datetime index
        if 'time' in df.columns:
            df = df.set_index('time')
        elif 'date' in df.columns:
            df = df.set_index('date')
        
        # Normalize column names
        df.columns = df.columns.str.lower()
        
        self.data[symbol] = df.sort_index()
    
    def run(self) -> BacktestResult:
        """
        Run the backtest.
        
        Returns:
            BacktestResult with trades, equity curve, and metrics
        """
        # Build unified timeline
        timeline = self._build_timeline()
        
        print(f"🚀 Starting backtest: {len(timeline)} bars across {len(self.data)} symbols")
        
        # Initialize equity
        self.equity = self.config.initial_equity
        self.governor.set_equity(self.equity)
        
        # Bar-by-bar simulation
        for timestamp in timeline:
            self.current_time = timestamp
            
            # Update each symbol
            for symbol, agent in self.agents.items():
                if symbol not in self.data:
                    continue
                
                df = self.data[symbol]
                if timestamp not in df.index:
                    continue
                
                row = df.loc[timestamp]
                
                # Update agent with new bar
                signal = agent.on_bar(row, timestamp)
                
                # Process signal through governor
                if signal is not None:
                    self._process_signal(signal, symbol)
            
            # Manage open positions
            self._manage_positions()
            
            # Record equity
            self.equity_curve.append(self.equity)
            self.timestamps.append(timestamp)
            
            # Update governor
            self.governor.set_equity(self.equity)
        
        # Close remaining positions at end
        self._close_all_positions()
        
        # Generate results
        return self._generate_results()
    
    def _build_timeline(self) -> List[datetime]:
        """Build unified timeline from all data sources."""
        all_times = set()
        
        for symbol, df in self.data.items():
            # Filter by date range
            mask = (df.index >= self.config.start_date) & (df.index <= self.config.end_date)
            times = df[mask].index.tolist()
            all_times.update(times)
        
        return sorted(all_times)
    
    def _process_signal(self, signal: Signal, symbol: str):
        """Process a trading signal through the governor."""
        # Get current positions for this symbol
        symbol_positions = self.agents[symbol].get_position_count()
        
        # Ask governor for permission
        allowed, approved_risk, reason = self.governor.can_open_trade(
            symbol, signal.risk_percent, symbol_positions
        )
        
        if not allowed:
            return
        
        # Execute trade
        self._open_position(signal, approved_risk, symbol)
    
    def _open_position(self, signal: Signal, risk_percent: float, symbol: str):
        """Open a new position."""
        ticket = self.next_ticket
        self.next_ticket += 1
        
        # Apply spread/slippage
        spread = self.config.spread_pips.get(symbol, 2) * 0.00001
        slippage = self.config.slippage_pips * 0.00001
        
        if signal.type == SignalType.BUY:
            entry_price = signal.price + spread + slippage
        else:
            entry_price = signal.price - spread - slippage
        
        # Calculate position size
        risk_amount = self.equity * (risk_percent / 100)
        sl_distance = abs(entry_price - signal.stop_loss)
        
        # Simplified lot calculation (1 lot = 100k units, 1 pip = $10)
        if sl_distance > 0:
            volume = risk_amount / (sl_distance * 100000)
        else:
            volume = 0.01
        
        volume = max(0.01, min(volume, 10.0))  # Clamp
        
        # Store position
        position_data = {
            'ticket': ticket,
            'symbol': symbol,
            'direction': signal.direction,
            'entry_price': entry_price,
            'stop_loss': signal.stop_loss,
            'take_profit': 0,
            'volume': volume,
            'risk_percent': risk_percent,
            'initial_risk': sl_distance,
            'entry_time': signal.timestamp,
            'label': signal.label,
            'partial_closed': False,
            'be_moved': False,
            'trailing_active': False,
            'confluence_score': signal.confluence_score,
        }
        
        self.open_positions[ticket] = position_data
        
        # Update agent state
        agent_pos = Position(
            ticket=ticket,
            symbol=symbol,
            direction=signal.direction,
            entry_price=entry_price,
            stop_loss=signal.stop_loss,
            volume=volume,
            entry_time=signal.timestamp,
            initial_risk=sl_distance,
            label=signal.label,
        )
        self.agents[symbol].add_position(agent_pos)
        
        # Update exposure tracker
        from portfolio.correlation import CorrelationManager
        cm = CorrelationManager()
        
        open_pos = OpenPosition(
            ticket=ticket,
            symbol=symbol,
            direction=signal.direction,
            entry_price=entry_price,
            stop_loss=signal.stop_loss,
            volume=volume,
            risk_percent=risk_percent,
            group=cm.get_group(symbol),
            entry_time=signal.timestamp,
        )
        self.governor.exposure.add_position(open_pos)
    
    def _manage_positions(self):
        """Manage open positions (trailing, BE, partials, stops)."""
        exit_cfg = self.risk_config.get('exit_strategy', {})
        
        to_close = []
        
        for ticket, pos in self.open_positions.items():
            symbol = pos['symbol']
            
            if symbol not in self.data or self.current_time not in self.data[symbol].index:
                continue
            
            current_bar = self.data[symbol].loc[self.current_time]
            current_price = current_bar['close']
            high = current_bar['high']
            low = current_bar['low']
            
            # Calculate profit in R
            if pos['direction'] == 1:
                profit_price = current_price - pos['entry_price']
            else:
                profit_price = pos['entry_price'] - current_price
            
            profit_r = profit_price / pos['initial_risk'] if pos['initial_risk'] > 0 else 0
            
            # Check stop loss hit
            if pos['direction'] == 1 and low <= pos['stop_loss']:
                to_close.append((ticket, pos['stop_loss'], 'SL'))
                continue
            elif pos['direction'] == -1 and high >= pos['stop_loss']:
                to_close.append((ticket, pos['stop_loss'], 'SL'))
                continue
            
            # Partial close
            if not pos['partial_closed'] and profit_r >= exit_cfg.get('partial_tp_r', 1.5):
                close_pct = exit_cfg.get('partial_close_pct', 40) / 100
                self._partial_close(ticket, close_pct)
            
            # Move to break-even
            if not pos['be_moved'] and profit_r >= exit_cfg.get('be_threshold_r', 1.8):
                pos['stop_loss'] = pos['entry_price']
                pos['be_moved'] = True
            
            # Trailing stop
            if profit_r >= exit_cfg.get('trail_start_r', 2.0):
                agent = self.agents.get(symbol)
                if agent and agent.atr > 0:
                    trail_dist = agent.atr * exit_cfg.get('trail_atr_mult', 1.2)
                    
                    if pos['direction'] == 1:
                        new_sl = current_price - trail_dist
                        if new_sl > pos['stop_loss']:
                            pos['stop_loss'] = new_sl
                    else:
                        new_sl = current_price + trail_dist
                        if new_sl < pos['stop_loss']:
                            pos['stop_loss'] = new_sl
                    
                    pos['trailing_active'] = True
        
        # Close stopped-out positions
        for ticket, exit_price, reason in to_close:
            self._close_position(ticket, exit_price, reason)
    
    def _partial_close(self, ticket: int, close_percent: float):
        """Close partial position."""
        pos = self.open_positions.get(ticket)
        if not pos:
            return
        
        close_volume = pos['volume'] * close_percent
        remaining_volume = pos['volume'] - close_volume
        
        if remaining_volume < 0.01:
            return  # Can't close if remainder too small
        
        # Calculate partial profit
        if pos['direction'] == 1:
            exit_price = self.data[pos['symbol']].loc[self.current_time]['close']
            profit = (exit_price - pos['entry_price']) * close_volume * 100000
        else:
            exit_price = self.data[pos['symbol']].loc[self.current_time]['close']
            profit = (pos['entry_price'] - exit_price) * close_volume * 100000
        
        # Update equity
        self.equity += profit
        
        # Update position
        pos['volume'] = remaining_volume
        pos['partial_closed'] = True
        
        # Update risk percent proportionally
        pos['risk_percent'] *= (1 - close_percent)
    
    def _close_position(self, ticket: int, exit_price: float, reason: str = ""):
        """Close a position and record trade."""
        pos = self.open_positions.pop(ticket, None)
        if not pos:
            return
        
        # Calculate profit
        if pos['direction'] == 1:
            profit = (exit_price - pos['entry_price']) * pos['volume'] * 100000
        else:
            profit = (pos['entry_price'] - exit_price) * pos['volume'] * 100000
        
        # Apply commission
        profit -= self.config.commission_per_lot * pos['volume'] * 2  # Entry + Exit
        
        # Profit in R
        profit_r = (exit_price - pos['entry_price']) / pos['initial_risk'] if pos['initial_risk'] > 0 else 0
        if pos['direction'] == -1:
            profit_r = -profit_r
        
        # Update equity
        self.equity += profit
        
        # Record trade
        trade = Trade(
            symbol=pos['symbol'],
            direction=pos['direction'],
            entry_price=pos['entry_price'],
            exit_price=exit_price,
            entry_time=pos['entry_time'],
            exit_time=self.current_time,
            profit=profit,
            profit_r=profit_r,
            risk_percent=pos['risk_percent'],
        )
        self.closed_trades.append(trade)
        self.governor.record_trade(trade)
        
        # Update agent
        if pos['symbol'] in self.agents:
            self.agents[pos['symbol']].remove_position(ticket)
        
        # Update exposure
        self.governor.exposure.remove_position(ticket)
    
    def _close_all_positions(self):
        """Close all remaining positions at current prices."""
        for ticket in list(self.open_positions.keys()):
            pos = self.open_positions[ticket]
            symbol = pos['symbol']
            
            if symbol in self.data and len(self.data[symbol]) > 0:
                exit_price = self.data[symbol].iloc[-1]['close']
            else:
                exit_price = pos['entry_price']
            
            self._close_position(ticket, exit_price, "End of backtest")
    
    def _generate_results(self) -> BacktestResult:
        """Generate backtest results."""
        equity_array = np.array(self.equity_curve)
        
        # Generate metrics
        metrics = generate_performance_report(self.closed_trades, equity_array)
        
        # Group trades by symbol
        symbol_trades = {}
        for trade in self.closed_trades:
            if trade.symbol not in symbol_trades:
                symbol_trades[trade.symbol] = []
            symbol_trades[trade.symbol].append(trade)
        
        return BacktestResult(
            config=self.config,
            trades=self.closed_trades,
            equity_curve=equity_array,
            timestamps=self.timestamps,
            metrics=metrics,
            symbol_trades=symbol_trades,
        )
