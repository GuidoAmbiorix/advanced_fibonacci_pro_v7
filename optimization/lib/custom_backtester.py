"""
Custom Backtesting Engine using MT5 Python API
Since MT5 Python API doesn't support Strategy Tester automation,
we build our own backtesting engine using historical data from MT5
"""
import MetaTrader5 as mt5
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import Dict, Optional, Callable, List
from pathlib import Path


class CustomBacktester:
    """
    Custom backtesting engine that simulates EA logic
    using historical data from MT5 Python API
    """
    
    def __init__(self):
        """Initialize MT5 connection"""
        if not mt5.initialize():
            raise RuntimeError(f"MT5 initialize() failed: {mt5.last_error()}")
        
        terminal_info = mt5.terminal_info()
        if terminal_info:
            print(f"✅ MT5 API connected: {terminal_info.name}")
    
    def __del__(self):
        """Cleanup"""
        mt5.shutdown()
    
    def get_historical_data(
        self,
        symbol: str,
        timeframe: str,
        date_from: str,
        date_to: str
    ) -> pd.DataFrame:
        """
        Get historical data from MT5
        
        Args:
            symbol: Trading symbol (e.g., "XAUUSD")
            timeframe: Timeframe (e.g., "H1", "D1")
            date_from: Start date "YYYY.MM.DD"
            date_to: End date "YYYY.MM.DD"
        
        Returns:
            DataFrame with OHLCV data
        """
        # Convert timeframe
        tf_map = {
            "M1": mt5.TIMEFRAME_M1,
            "M5": mt5.TIMEFRAME_M5,
            "M15": mt5.TIMEFRAME_M15,
            "M30": mt5.TIMEFRAME_M30,
            "H1": mt5.TIMEFRAME_H1,
            "H4": mt5.TIMEFRAME_H4,
            "D1": mt5.TIMEFRAME_D1,
        }
        
        tf = tf_map.get(timeframe.upper(), mt5.TIMEFRAME_H1)
        
        # Convert dates
        date_from_dt = datetime.strptime(date_from, "%Y.%m.%d")
        date_to_dt = datetime.strptime(date_to, "%Y.%m.%d")
        
        # Get rates
        rates = mt5.copy_rates_range(symbol, tf, date_from_dt, date_to_dt)
        
        if rates is None or len(rates) == 0:
            raise ValueError(f"No data retrieved for {symbol} {timeframe}")
        
        # Convert to DataFrame
        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        
        print(f"📊 Retrieved {len(df)} bars for {symbol} {timeframe}")
        
        return df
    
    def simulate_trades(
        self,
        data: pd.DataFrame,
        ea_logic: Callable,
        parameters: Dict,
        deposit: float = 10000
    ) -> Dict:
        """
        Simulate trading based on EA logic
        
        Args:
            data: Historical price data
            ea_logic: Function that implements EA trading logic
            parameters: EA parameters
            deposit: Initial deposit
        
        Returns:
            Dict with backtest metrics
        """
        balance = deposit
        equity = deposit
        trades = []
        
        # Simulate each bar
        for i in range(len(data)):
            bar = data.iloc[i]
            
            # Call EA logic
            signal = ea_logic(data[:i+1], parameters)
            
            if signal:
                # Simulate trade
                trade = self._execute_simulated_trade(signal, bar, balance)
                if trade:
                    trades.append(trade)
                    balance += trade['profit']
                    equity = balance
        
        # Calculate metrics
        metrics = self._calculate_metrics(trades, deposit, balance)
        
        return metrics
    
    def _execute_simulated_trade(self, signal, bar, balance):
        """Execute a simulated trade"""
        # Simplified simulation
        # In real implementation, would track open positions, SL/TP, etc.
        return None
    
    def _calculate_metrics(self, trades: List, initial_balance: float, final_balance: float) -> Dict:
        """Calculate backtest metrics"""
        
        if not trades:
            return {
                "success": True,
                "profit_factor": 0.0,
                "total_trades": 0,
                "total_net_profit": 0.0,
                "win_rate": 0.0
            }
        
        profits = [t['profit'] for t in trades if t['profit'] > 0]
        losses = [abs(t['profit']) for t in trades if t['profit'] < 0]
        
        gross_profit = sum(profits) if profits else 0.0
        gross_loss = sum(losses) if losses else 0.0
        
        profit_factor = gross_profit / gross_loss if gross_loss > 0 else (gross_profit if gross_profit > 0 else 0.0)
        
        win_rate = (len(profits) / len(trades)) * 100 if trades else 0.0
        
        return {
            "success": True,
            "profit_factor": profit_factor,
            "total_trades": len(trades),
            "total_net_profit": final_balance - initial_balance,
            "gross_profit": gross_profit,
            "gross_loss": gross_loss,
            "win_rate": win_rate,
            "win_rate": win_rate,
            "max_drawdown": self._calculate_max_drawdown(trades, initial_balance)
        }
    
    def _calculate_max_drawdown(self, trades: List, initial_balance: float) -> float:
        """Calculate Max Drawdown % from equity curve"""
        balance = initial_balance
        peak = balance
        max_dd = 0.0
        
        for trade in trades:
            balance += trade['profit']
            if balance > peak:
                peak = balance
            
            dd = (peak - balance) / peak * 100
            if dd > max_dd:
                max_dd = dd
                
        return max_dd
    
    def run_backtest(
        self,
        ea_path: str,
        symbol: str,
        timeframe: str,
        date_from: str,
        date_to: str,
        deposit: float = 10000,
        leverage: int = 500,
        parameters: Optional[Dict] = None,
        progress_callback: Optional[Callable[[str, int], None]] = None
    ) -> Dict:
        """
        Run custom backtest
        
        NOTE: This is a SIMPLIFIED backtester
        For accurate results, still recommend MT5 Strategy Tester GUI
        But this gives automated capability with reasonable accuracy
        """
        if parameters is None:
            parameters = {}
        
        try:
            if progress_callback:
                progress_callback("Fetching historical data...", 10)
            
            # Get data
            data = self.get_historical_data(symbol, timeframe, date_from, date_to)
            
            if progress_callback:
                progress_callback("Running simulation...", 50)
            
            # Run real EA simulation
            from lib.simple_ea_logic import SimpleEALogic
            
            ea = SimpleEALogic(parameters)
            trades = ea.backtest(data, deposit)
            
            if progress_callback:
                progress_callback("Calculating metrics...", 90)
            
            # Calculate metrics
            metrics = self._calculate_metrics(trades, deposit, deposit + sum(t['profit'] for t in trades))
            
            if progress_callback:
                progress_callback("Completed", 100)
            
            return metrics
            
        except Exception as e:
            print(f"❌ Backtest error: {e}")
            return {
                "success": False,
                "profit_factor": 0.0,
                "error": str(e)
            }


# Global instance
_backtester_instance: Optional[CustomBacktester] = None


def get_backtester() -> CustomBacktester:
    """Get global backtester instance"""
    global _backtester_instance
    
    if _backtester_instance is None:
        _backtester_instance = CustomBacktester()
    
    return _backtester_instance
