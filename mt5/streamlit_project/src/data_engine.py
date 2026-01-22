import MetaTrader5 as mt5
import pandas as pd
from datetime import datetime, timedelta
from typing import List, Dict
from src.connector import MT5Connector
from src.types import Trade

class DataEngine:
    def __init__(self):
        self.connector = MT5Connector()

    def fetch_trades(self, days: int = 30) -> pd.DataFrame:
        """
        Fetches historical deals and reconstructs them into 'Trades'.
        MT5 stores "Deals" (Entry IN, Exit OUT). We need to merge them.
        """
        if not self.connector.connect():
            return pd.DataFrame()

        from_date = datetime.now() - timedelta(days=days)
        
        # Fetch history deals
        deals_raw = mt5.history_deals_get(from_date, datetime.now())
        
        if deals_raw is None:
             # handle error or empty
            return pd.DataFrame()

        deals_df = pd.DataFrame(list(deals_raw), columns=deals_raw[0]._asdict().keys())
        
        # Convert times
        deals_df['time'] = pd.to_datetime(deals_df['time'], unit='s')
        
        return self._process_deals(deals_df)

    def _process_deals(self, deals_df: pd.DataFrame) -> pd.DataFrame:
        """
        Groups deals by 'position_id' to reconstruct the full trade lifecycle.
        A position usually has:
        - 1 Deal Type 'ENTRY_IN'
        - 1 Deal Type 'ENTRY_OUT' (Close)
        """
        trades: List[Trade] = []
        
        # Group by position ID (The core link between entry and exit)
        grouped = deals_df.groupby('position_id')

        for position_id, group in grouped:
            order_deals = group.sort_values('time')
            
            # We need at least 2 deals (Entry + Exit) to have a closed trade
            # Or simplified: Entry is first, Exit is last.
            
            entry_deal = order_deals.iloc[0]
            exit_deal = order_deals.iloc[-1]
            
            # Simple Filter: ensure strictly different types imply a round trip
            # Entry type in MT5: 0=Buy, 1=Sell // Deal Entry: 0=In, 1=Out
            
            if len(order_deals) < 2:
                continue # Skip open positions for now, or handle separately
            
            # Determine Direction from Entry
            direction = "BUY" if entry_deal['type'] == 0 else "SELL" # 0=ORDER_TYPE_BUY
            
            trade = Trade(
                ticket=int(position_id),
                symbol=entry_deal['symbol'],
                direction=direction,
                entry_time=entry_deal['time'],
                exit_time=exit_deal['time'],
                entry_price=float(entry_deal['price']),
                exit_price=float(exit_deal['price']),
                volume=float(entry_deal['volume']),
                profit=group['profit'].sum(), # Sum all partial closes/swaps if any
                commission=group['commission'].sum(),
                swap=group['swap'].sum(),
                duration_minutes=(exit_deal['time'] - entry_deal['time']).total_seconds() / 60.0,
                comment=entry_deal['comment'],
                magic=int(entry_deal['magic'])
            )
            
            trades.append(trade)

        if not trades:
            return pd.DataFrame()
            
        return pd.DataFrame([t.__dict__ for t in trades])

    def get_open_positions(self) -> pd.DataFrame:
        """Fetches current open positions."""
        if not self.connector.connect():
             return pd.DataFrame()
             
        positions = mt5.positions_get()
        if positions is None:
            return pd.DataFrame()
            
        df = pd.DataFrame(list(positions), columns=positions[0]._asdict().keys())
        df['time'] = pd.to_datetime(df['time'], unit='s')
        return df

    def fetch_ohlc(self, symbol: str, timeframe: int, from_date: datetime, to_date: datetime) -> pd.DataFrame:
        """
        Fetches OHLC bars for a specific range.
        Standardizes column names for lightweight-charts.
        """
        if not self.connector.connect():
            return pd.DataFrame()

        # copy_rates_range takes dates, handles inclusivity
        rates = mt5.copy_rates_range(symbol, timeframe, from_date, to_date)
        
        if rates is None or len(rates) == 0:
            return pd.DataFrame()

        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        
        # Renaissance of column names if needed, but mt5 gives: time, open, high, low, close, tick_volume, spread, real_volume
        return df
