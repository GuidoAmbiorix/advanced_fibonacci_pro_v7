import MetaTrader5 as mt5
import pandas as pd
import logging
from datetime import datetime, timedelta
from typing import List, Dict, Optional
from src.connector_wrapper import MT5Connector
from src.types import Trade
from src.logger import get_logger, log_mt5_error, LogContext, log_data_quality
from src.config import config

logger = get_logger(__name__)


class DataEngine:
    """Data engine for fetching and processing MT5 data with comprehensive error handling."""

    def __init__(self):
        self.connector = MT5Connector()
        logger.info("DataEngine initialized")

    def fetch_trades(self, days: int = 30) -> pd.DataFrame:
        """
        Fetches historical deals and reconstructs them into 'Trades'.
        MT5 stores "Deals" (Entry IN, Exit OUT). We need to merge them.

        Args:
            days: Number of days of history to fetch

        Returns:
            DataFrame of reconstructed trades
        """
        try:
            with LogContext(logger, f"fetch_trades (last {days} days)"):
                if not self.connector.connect():
                    logger.error("Cannot fetch trades - MT5 not connected")
                    return pd.DataFrame()

                # Limit days to configured maximum
                days = min(days, config.MAX_HISTORY_DAYS)
                from_date = datetime.now() - timedelta(days=days)

                # Fetch history deals
                deals_raw = mt5.history_deals_get(from_date, datetime.now())

                if deals_raw is None:
                    error_code, error_msg = mt5.last_error()
                    log_mt5_error(logger, "history_deals_get", error_code, error_msg)
                    return pd.DataFrame()

                if len(deals_raw) == 0:
                    logger.warning(f"No deals found in the last {days} days")
                    return pd.DataFrame()

                logger.info(f"Fetched {len(deals_raw)} deals from MT5")

                # Convert to DataFrame
                deals_df = pd.DataFrame(list(deals_raw), columns=deals_raw[0]._asdict().keys())

                # Data quality check
                log_data_quality(logger, "deals_fetch", True, f"{len(deals_df)} deals retrieved")

                # Convert times
                deals_df['time'] = pd.to_datetime(deals_df['time'], unit='s')

                # Process into trades
                trades_df = self._process_deals(deals_df)

                logger.info(f"Processed {len(trades_df)} trades from {len(deals_df)} deals")
                return trades_df

        except Exception as e:
            logger.error(f"Unexpected error fetching trades: {e}", exc_info=True)
            return pd.DataFrame()

    def _process_deals(self, deals_df: pd.DataFrame) -> pd.DataFrame:
        """
        Groups deals by 'position_id' to reconstruct the full trade lifecycle.
        A position usually has:
        - 1 Deal Type 'ENTRY_IN'
        - 1 Deal Type 'ENTRY_OUT' (Close)

        Args:
            deals_df: DataFrame of raw MT5 deals

        Returns:
            DataFrame of reconstructed trades
        """
        try:
            trades: List[Trade] = []
            skipped_count = 0

            # Group by position ID (The core link between entry and exit)
            grouped = deals_df.groupby('position_id')

            for position_id, group in grouped:
                try:
                    order_deals = group.sort_values('time')

                    # We need at least 2 deals (Entry + Exit) to have a closed trade
                    if len(order_deals) < 2:
                        skipped_count += 1
                        continue  # Skip open positions

                    entry_deal = order_deals.iloc[0]
                    exit_deal = order_deals.iloc[-1]

                    # Determine Direction from Entry
                    # Entry type in MT5: 0=Buy, 1=Sell
                    direction = "BUY" if entry_deal['type'] == 0 else "SELL"

                    # Validate data integrity
                    if pd.isna(entry_deal['price']) or pd.isna(exit_deal['price']):
                        logger.warning(f"Invalid price data for position {position_id}, skipping")
                        skipped_count += 1
                        continue

                    # Calculate duration
                    duration_seconds = (exit_deal['time'] - entry_deal['time']).total_seconds()
                    if duration_seconds < 0:
                        logger.warning(f"Negative duration for position {position_id}, skipping")
                        skipped_count += 1
                        continue

                    trade = Trade(
                        ticket=int(position_id),
                        symbol=entry_deal['symbol'],
                        direction=direction,
                        entry_time=entry_deal['time'],
                        exit_time=exit_deal['time'],
                        entry_price=float(entry_deal['price']),
                        exit_price=float(exit_deal['price']),
                        volume=float(entry_deal['volume']),
                        profit=group['profit'].sum(),
                        commission=group['commission'].sum(),
                        swap=group['swap'].sum(),
                        duration_minutes=duration_seconds / 60.0,
                        comment=entry_deal['comment'],
                        magic=int(entry_deal['magic'])
                    )

                    trades.append(trade)

                except Exception as e:
                    logger.warning(f"Error processing position {position_id}: {e}")
                    skipped_count += 1
                    continue

            if skipped_count > 0:
                logger.info(f"Skipped {skipped_count} incomplete/invalid positions")

            if not trades:
                logger.warning("No valid trades after processing deals")
                return pd.DataFrame()

            trades_df = pd.DataFrame([t.__dict__ for t in trades])

            # Data quality checks
            log_data_quality(
                logger,
                "trades_reconstruction",
                True,
                f"{len(trades_df)} valid trades from {len(grouped)} positions"
            )

            return trades_df

        except Exception as e:
            logger.error(f"Error processing deals: {e}", exc_info=True)
            return pd.DataFrame()

    def get_open_positions(self) -> pd.DataFrame:
        """
        Fetches current open positions.

        Returns:
            DataFrame of open positions or empty DataFrame if error/none
        """
        try:
            with LogContext(logger, "get_open_positions", logging.DEBUG):
                if not self.connector.connect():
                    logger.error("Cannot fetch positions - MT5 not connected")
                    return pd.DataFrame()

                positions = mt5.positions_get()

                if positions is None:
                    error_code, error_msg = mt5.last_error()
                    if error_code != 1:  # 1 = success but no positions
                        log_mt5_error(logger, "positions_get", error_code, error_msg)
                    return pd.DataFrame()

                if len(positions) == 0:
                    logger.debug("No open positions")
                    return pd.DataFrame()

                df = pd.DataFrame(list(positions), columns=positions[0]._asdict().keys())
                df['time'] = pd.to_datetime(df['time'], unit='s')

                logger.info(f"Retrieved {len(df)} open positions")
                return df

        except Exception as e:
            logger.error(f"Error fetching open positions: {e}", exc_info=True)
            return pd.DataFrame()

    def fetch_ohlc(
        self,
        symbol: str,
        timeframe: int,
        from_date: datetime,
        to_date: datetime
    ) -> pd.DataFrame:
        """
        Fetches OHLC bars for a specific range.
        Standardizes column names for lightweight-charts.

        Args:
            symbol: Symbol name (e.g., "EURUSD")
            timeframe: MT5 timeframe constant
            from_date: Start date
            to_date: End date

        Returns:
            DataFrame with OHLC data
        """
        try:
            with LogContext(logger, f"fetch_ohlc {symbol}", logging.DEBUG):
                if not self.connector.connect():
                    logger.error("Cannot fetch OHLC - MT5 not connected")
                    return pd.DataFrame()

                # Fetch rates
                rates = mt5.copy_rates_range(symbol, timeframe, from_date, to_date)

                if rates is None:
                    error_code, error_msg = mt5.last_error()
                    log_mt5_error(logger, f"copy_rates_range for {symbol}", error_code, error_msg)
                    return pd.DataFrame()

                if len(rates) == 0:
                    logger.warning(f"No OHLC data for {symbol} in specified range")
                    return pd.DataFrame()

                df = pd.DataFrame(rates)
                df['time'] = pd.to_datetime(df['time'], unit='s')

                logger.debug(f"Fetched {len(df)} bars for {symbol}")

                # Data quality check
                if df.isnull().any().any():
                    null_count = df.isnull().sum().sum()
                    logger.warning(f"OHLC data for {symbol} contains {null_count} null values")

                return df

        except Exception as e:
            logger.error(f"Error fetching OHLC for {symbol}: {e}", exc_info=True)
            return pd.DataFrame()
