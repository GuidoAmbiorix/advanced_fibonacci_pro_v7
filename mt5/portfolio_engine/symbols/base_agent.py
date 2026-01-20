"""
Base Agent
Abstract base class for symbol trading agents.
Implements the Confluence Ladder system.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional, Dict, List, Any
import numpy as np
import pandas as pd
from datetime import datetime

import sys
sys.path.append('..')
from indicators import (
    find_swing_points_simple,
    is_in_golden_zone,
    is_valid_structure,
    check_displacement,
    calculate_rsi_numpy,
    get_rsi_signal,
    calculate_ema_numpy,
    calculate_ema_slope,
    is_trend_valid,
    calculate_atr_numpy,
    calculate_atr_ma,
    is_choppy,
    get_range_efficiency,
)


class SignalType(Enum):
    """Trade signal types."""
    NONE = 0
    BUY = 1
    SELL = -1


@dataclass
class Signal:
    """Trade signal with metadata."""
    type: SignalType
    symbol: str
    timestamp: datetime
    price: float
    stop_loss: float
    risk_percent: float
    confluence_score: int
    label: str = "Entry"
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    @property
    def direction(self) -> int:
        return self.type.value
    
    @property
    def sl_distance(self) -> float:
        return abs(self.price - self.stop_loss)


@dataclass
class Position:
    """Open position tracking."""
    ticket: int
    symbol: str
    direction: int
    entry_price: float
    stop_loss: float
    volume: float
    entry_time: datetime
    initial_risk: float
    label: str = ""
    partial_closed: bool = False


class BaseAgent(ABC):
    """
    Base class for symbol trading agents.
    Implements the Confluence Ladder system.
    """
    
    def __init__(self, symbol: str, config: Dict[str, Any]):
        """
        Initialize agent with symbol and configuration.
        
        Args:
            symbol: Trading symbol (e.g., 'XAUUSD')
            config: Symbol-specific configuration from symbols.yaml
        """
        self.symbol = symbol
        self.config = config
        
        # State
        self.positions: List[Position] = []
        self.signals: List[Signal] = []
        self.current_direction: int = 0
        self.addon1_triggered: bool = False
        self.addon2_triggered: bool = False
        
        # Cached indicator values
        self.atr: float = 0
        self.atr_ma: float = 0
        self.rsi: float = 0
        self.rsi_prev: float = 0
        self.ema: float = 0
        self.ema_prev: float = 0
        self.ema_slope: float = 0
        
        # Price data cache
        self.opens: np.ndarray = np.array([])
        self.highs: np.ndarray = np.array([])
        self.lows: np.ndarray = np.array([])
        self.closes: np.ndarray = np.array([])
        
        # Load config
        self._load_config()
    
    def _load_config(self):
        """Load configuration parameters."""
        c = self.config
        
        # Fibonacci
        self.swing_lookback = c.get('swing_lookback', 20)
        self.fib_level_low = c.get('fib_level_low', 0.618)
        self.fib_level_high = c.get('fib_level_high', 0.786)
        self.zone_tolerance = c.get('zone_tolerance', 0.25)
        
        # RSI
        self.rsi_period = c.get('rsi_period', 14)
        self.rsi_oversold = c.get('rsi_oversold', 45)
        self.rsi_overbought = c.get('rsi_overbought', 55)
        self.rsi_momentum = c.get('rsi_momentum', True)
        
        # EMA
        self.ema_period = c.get('ema_period', 200)
        self.ema_min_slope = c.get('ema_min_slope', 0.1)
        
        # Displacement
        self.use_displacement = c.get('use_displacement', True)
        self.displacement_atr = c.get('displacement_atr', 1.2)
        self.displacement_lookback = c.get('displacement_lookback', 5)
        
        # Chop filter
        self.use_chop_filter = c.get('use_chop_filter', True)
        self.chop_threshold = c.get('chop_threshold', 0.75)
        self.atr_ma_period = c.get('atr_ma_period', 20)
        self.min_range_efficiency = c.get('min_range_efficiency', 0.4)
        
        # Confluence
        self.min_confluence_entry = c.get('min_confluence_entry', 4)
    
    def reset_state(self):
        """Reset trading state (called when no positions)."""
        self.current_direction = 0
        self.addon1_triggered = False
        self.addon2_triggered = False
    
    def update_data(self, df: pd.DataFrame):
        """
        Update price data cache from DataFrame.
        
        Args:
            df: DataFrame with OHLC columns
        """
        self.opens = df['open'].values
        self.highs = df['high'].values
        self.lows = df['low'].values
        self.closes = df['close'].values
    
    def update_indicators(self):
        """Calculate all indicators from cached price data."""
        if len(self.closes) < max(self.ema_period, self.rsi_period, 50):
            return
        
        # ATR
        atr_array = calculate_atr_numpy(self.highs, self.lows, self.closes, 14)
        self.atr = atr_array[-1] if not np.isnan(atr_array[-1]) else 0
        
        # ATR MA
        if self.use_chop_filter:
            atr_ma_array = calculate_atr_ma(atr_array, self.atr_ma_period)
            self.atr_ma = atr_ma_array[-1] if not np.isnan(atr_ma_array[-1]) else self.atr
        
        # RSI
        rsi_array = calculate_rsi_numpy(self.closes, self.rsi_period)
        self.rsi = rsi_array[-1] if not np.isnan(rsi_array[-1]) else 50
        self.rsi_prev = rsi_array[-2] if len(rsi_array) > 1 and not np.isnan(rsi_array[-2]) else self.rsi
        
        # EMA
        ema_array = calculate_ema_numpy(self.closes, self.ema_period)
        self.ema = ema_array[-1] if not np.isnan(ema_array[-1]) else self.closes[-1]
        self.ema_prev = ema_array[-2] if len(ema_array) > 1 and not np.isnan(ema_array[-2]) else self.ema
        self.ema_slope = self.ema - self.ema_prev
    
    def calculate_confluence_score(self, direction: int) -> int:
        """
        Calculate confluence score (0-6) for a trade direction.
        
        Components:
        1. Trend aligned (EMA + slope)
        2. Structure valid (swing order)
        3. Fib golden zone
        4. RSI confirmation
        5. RSI momentum
        6. Displacement present
        
        Args:
            direction: 1 for BUY, -1 for SELL
            
        Returns:
            Score from 0 to 6
        """
        score = 0
        current_price = self.closes[-1]
        
        # 1. TREND ALIGNED
        if is_trend_valid(current_price, self.ema, self.ema_slope, self.atr, direction, self.ema_min_slope):
            score += 1
        
        # 2. STRUCTURE VALID
        swing_high, swing_low, high_bar, low_bar = find_swing_points_simple(
            self.highs, self.lows, self.swing_lookback
        )
        if is_valid_structure(high_bar, low_bar, direction):
            score += 1
        
        # 3. FIB GOLDEN ZONE
        if not np.isnan(swing_high) and not np.isnan(swing_low):
            if is_in_golden_zone(
                current_price, swing_high, swing_low,
                self.fib_level_low, self.fib_level_high,
                self.zone_tolerance, self.atr
            ):
                score += 1
        
        # 4. RSI CONFIRMATION
        if get_rsi_signal(
            self.rsi, self.rsi_prev, direction,
            self.rsi_oversold, self.rsi_overbought, False  # Without momentum
        ):
            score += 1
        
        # 5. RSI MOMENTUM
        if self.rsi_momentum:
            if (direction == 1 and self.rsi > self.rsi_prev) or \
               (direction == -1 and self.rsi < self.rsi_prev):
                score += 1
        else:
            score += 1  # Give point if momentum not required
        
        # 6. DISPLACEMENT
        if check_displacement(
            self.closes, self.opens, self.atr, direction,
            self.displacement_atr, self.displacement_lookback
        ):
            score += 1
        
        return score
    
    def check_filters(self) -> bool:
        """
        Check pre-entry filters.
        
        Returns:
            True if all filters pass
        """
        # Chop filter
        if self.use_chop_filter:
            if is_choppy(self.atr, self.atr_ma, self.chop_threshold):
                return False
            
            # Range efficiency
            if len(self.opens) > 0:
                efficiency = get_range_efficiency(
                    self.opens[-1], self.closes[-1],
                    self.highs[-1], self.lows[-1]
                )
                if efficiency < self.min_range_efficiency:
                    return False
        
        # Session filter (to be overridden by subclass)
        if not self.check_session():
            return False
        
        return True
    
    @abstractmethod
    def check_session(self) -> bool:
        """
        Check if current time is within trading session.
        Must be implemented by subclass.
        
        Returns:
            True if session is valid for trading
        """
        pass
    
    def on_bar(self, row: pd.Series, timestamp: datetime) -> Optional[Signal]:
        """
        Process a new bar and generate signal if conditions met.
        
        Args:
            row: OHLC bar data
            timestamp: Bar timestamp
            
        Returns:
            Signal if conditions met, None otherwise
        """
        # Append new data
        self.opens = np.append(self.opens, row['open'])
        self.highs = np.append(self.highs, row['high'])
        self.lows = np.append(self.lows, row['low'])
        self.closes = np.append(self.closes, row['close'])
        
        # Update indicators
        self.update_indicators()
        
        # Check filters
        if not self.check_filters():
            return None
        
        # No position? Check for entry
        if len(self.positions) == 0:
            self.reset_state()
            return self._check_entry(timestamp)
        
        # Have positions? Check for add-ons
        else:
            return self._check_addon(timestamp)
    
    def _check_entry(self, timestamp: datetime) -> Optional[Signal]:
        """Check for new entry signal."""
        current_price = self.closes[-1]
        
        # Calculate confluence for both directions
        buy_score = self.calculate_confluence_score(1)
        sell_score = self.calculate_confluence_score(-1)
        
        # Check BUY
        if buy_score >= self.min_confluence_entry:
            sl = current_price - (self.atr * 1.0)  # 1 ATR stop
            
            self.current_direction = 1
            
            return Signal(
                type=SignalType.BUY,
                symbol=self.symbol,
                timestamp=timestamp,
                price=current_price,
                stop_loss=sl,
                risk_percent=0.25,  # Base risk
                confluence_score=buy_score,
                label="Entry",
                metadata={'atr': self.atr, 'rsi': self.rsi}
            )
        
        # Check SELL
        if sell_score >= self.min_confluence_entry:
            sl = current_price + (self.atr * 1.0)
            
            self.current_direction = -1
            
            return Signal(
                type=SignalType.SELL,
                symbol=self.symbol,
                timestamp=timestamp,
                price=current_price,
                stop_loss=sl,
                risk_percent=0.25,
                confluence_score=sell_score,
                label="Entry",
                metadata={'atr': self.atr, 'rsi': self.rsi}
            )
        
        return None
    
    def _check_addon(self, timestamp: datetime) -> Optional[Signal]:
        """Check for add-on opportunity."""
        if self.current_direction == 0:
            return None
        
        # Calculate current R profit
        total_profit_r = self._calculate_profit_r()
        
        # Calculate confluence for current direction
        current_score = self.calculate_confluence_score(self.current_direction)
        
        current_price = self.closes[-1]
        
        # Add-on #1: +1.5R and score >= 4
        if not self.addon1_triggered and len(self.positions) < 3:
            if total_profit_r >= 1.5 and current_score >= 4:
                sl = current_price - (self.atr * 1.0) if self.current_direction == 1 else current_price + (self.atr * 1.0)
                
                self.addon1_triggered = True
                
                return Signal(
                    type=SignalType.BUY if self.current_direction == 1 else SignalType.SELL,
                    symbol=self.symbol,
                    timestamp=timestamp,
                    price=current_price,
                    stop_loss=sl,
                    risk_percent=0.15,  # Reduced risk for add-on
                    confluence_score=current_score,
                    label="Add1",
                    metadata={'profit_r': total_profit_r}
                )
        
        # Add-on #2: +2.5R and score >= 5
        if not self.addon2_triggered and self.addon1_triggered and len(self.positions) < 3:
            if total_profit_r >= 2.5 and current_score >= 5:
                sl = current_price - (self.atr * 1.0) if self.current_direction == 1 else current_price + (self.atr * 1.0)
                
                self.addon2_triggered = True
                
                return Signal(
                    type=SignalType.BUY if self.current_direction == 1 else SignalType.SELL,
                    symbol=self.symbol,
                    timestamp=timestamp,
                    price=current_price,
                    stop_loss=sl,
                    risk_percent=0.10,  # Even less risk for second add-on
                    confluence_score=current_score,
                    label="Add2",
                    metadata={'profit_r': total_profit_r}
                )
        
        return None
    
    def _calculate_profit_r(self) -> float:
        """Calculate total profit in R terms across all positions."""
        if len(self.positions) == 0:
            return 0
        
        total_r = 0
        current_price = self.closes[-1]
        
        for pos in self.positions:
            if pos.direction == 1:
                profit = current_price - pos.entry_price
            else:
                profit = pos.entry_price - current_price
            
            if pos.initial_risk > 0:
                total_r += profit / pos.initial_risk
        
        return total_r
    
    def add_position(self, position: Position):
        """Add a new position to tracking."""
        self.positions.append(position)
    
    def remove_position(self, ticket: int):
        """Remove a position by ticket."""
        self.positions = [p for p in self.positions if p.ticket != ticket]
        
        if len(self.positions) == 0:
            self.reset_state()
    
    def get_position_count(self) -> int:
        """Get number of open positions."""
        return len(self.positions)
