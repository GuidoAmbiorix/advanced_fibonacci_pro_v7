
from typing import List, Dict, Optional
from dataclasses import dataclass, field
from datetime import datetime
import copy

from app.backtesting.models import BacktestTrade, BacktestResults, BacktestMetrics, BacktestConfig, SimulatedSlaveConfig

class VirtualCopyTrader:
    """
    Simulates the replication of trades from a Master Strategy to multiple Slave Accounts.
    Used during backtesting to see how different risk settings would perform.
    """
    
    def __init__(self, slave_configs: List[SimulatedSlaveConfig]):
        self.slave_configs = slave_configs
        
        # State tracking
        self.slave_trades: Dict[str, List[BacktestTrade]] = {s.name: [] for s in slave_configs}
        self.slave_balances: Dict[str, float] = {s.name: s.initial_balance for s in slave_configs}
        self.active_trades: Dict[str, Dict[int, BacktestTrade]] = {s.name: {} for s in slave_configs}
        
    def on_master_signal(self, master_trade: BacktestTrade) -> None:
        """
        Receive a signal from the Master logic and propagate to slaves
        """
        for slave in self.slave_configs:
            # 1. Check Filters
            if slave.include_symbols and master_trade.symbol not in slave.include_symbols:
                continue
            if master_trade.symbol in slave.exclude_symbols:
                continue
                
            # 2. Calculate Volume
            volume = self._calculate_volume(slave, master_trade)
            if volume <= 0:
                continue
                
            # 3. Simulate Entry Price (Slippage)
            entry_slippage = slave.slippage_pips * 0.0001 # Assuming standard pairs
            if master_trade.signal_type == "BUY":
                entry_price = master_trade.entry_price + entry_slippage
            else:
                entry_price = master_trade.entry_price - entry_slippage
                
            # 4. Create Slave Trade
            slave_trade = copy.deepcopy(master_trade)
            slave_trade.ticket = id(slave_trade) # New unique ID
            slave_trade.volume = volume
            slave_trade.entry_price = entry_price
            slave_trade.commission = volume * slave.commission_per_lot
            slave_trade.slippage_pips += slave.slippage_pips
            
            # Handle Reverse Copy
            if slave.reverse_copy:
                slave_trade.signal_type = "SELL" if master_trade.signal_type == "BUY" else "BUY"
                # TODO: Re-calculate SL/TP for reverse logic if needed, 
                # strictly simple signal reversal often needs SL/TP swap logic which is complex.
                # For now assuming simple visual backtest or manual intervention for reverse.
            
            # Track
            self.slave_trades[slave.name].append(slave_trade)
            self.active_trades[slave.name][master_trade.ticket] = slave_trade
            
    def on_master_close(self, master_trade: BacktestTrade) -> None:
        """
        Master closed a trade, close specific slave copies
        """
        for slave in self.slave_configs:
            if master_trade.ticket in self.active_trades[slave.name]:
                slave_trade = self.active_trades[slave.name][master_trade.ticket]
                
                # Simulate Exit Price (Slippage)
                exit_slippage = slave.slippage_pips * 0.0001
                if slave_trade.signal_type == "BUY":
                    exit_price = master_trade.exit_price - exit_slippage
                else:
                    exit_price = master_trade.exit_price + exit_slippage
                
                # Close Trade
                slave_trade.close(
                    exit_time=master_trade.exit_time,
                    exit_price=exit_price,
                    exit_reason=master_trade.exit_reason
                )
                
                # Update Balance
                self.slave_balances[slave.name] += slave_trade.pnl
                
                # Clean up active list
                del self.active_trades[slave.name][master_trade.ticket]

    def _calculate_volume(self, slave: SimulatedSlaveConfig, master_trade: BacktestTrade) -> float:
        """Determines lot size based on slave configuration"""
        
        if slave.mode == "FIXED_LOT":
            return slave.fixed_lot_size
            
        elif slave.mode == "MULTIPLIER":
            # Simple multiplier of master's volume
            return round(master_trade.volume * slave.risk_multiplier, 2)
            
        elif slave.mode == "RISK_PERCENT":
            # Recalculate based on Slave's current balance and risk %
            # Risk = ABS(Entry - SL) * Volume * TickValue
            # Volume = (Balance * Risk%) / (ABS(Entry - SL) * TickValue)
            
            risk_amount = self.slave_balances[slave.name] * (slave.max_risk_percent / 100.0)
            sl_distance = abs(master_trade.entry_price - master_trade.stop_loss)
            
            if sl_distance == 0:
                return 0.01
                
            # Assuming standard FX 100k contract & approx $10 per pip for simple calc
            # A more robust engine would use symbol tick value
            tick_value = 10.0 # Standard lot pip value approx $10
            # SL distance in pips
            pips_risk = sl_distance / 0.0001 
            
            if pips_risk == 0: 
                return 0.01

            raw_volume = risk_amount / (pips_risk * tick_value)
            return round(raw_volume, 2)
            
        return master_trade.volume

    def get_results(self, slave_name: str) -> BacktestResults:
        """Generate standard results object for a simulated slave"""
        trades = self.slave_trades.get(slave_name, [])
        config = BacktestConfig(initial_balance=0) # Dummy config for report
        
        # Calculate metrics manually or reuse Metrics class logic
        metrics = BacktestMetrics() 
        metrics.total_trades = len(trades)
        
        if trades:
             metrics.total_profit = sum(t.pnl for t in trades if t.pnl > 0)
             metrics.total_loss = sum(t.pnl for t in trades if t.pnl < 0)
             metrics.net_profit = metrics.total_profit + metrics.total_loss
             metrics.win_rate = len([t for t in trades if t.pnl > 0]) / len(trades) if trades else 0
        
        return BacktestResults(
            config=config,
            metrics=metrics,
            trades=trades,
            start_date=trades[0].entry_time if trades else None,
            end_date=trades[-1].exit_time if trades else None
        )
