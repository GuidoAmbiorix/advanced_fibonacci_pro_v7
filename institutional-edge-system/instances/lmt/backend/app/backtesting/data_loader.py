"""
Data Loader for Backtesting
Load historical OHLCV data from MT5 or CSV files
"""

import pandas as pd
# import MetaTrader5 as mt5 # REMOVED for Docker
import rpyc
from rpyc.utils.classic import obtain
import os
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional, Tuple
from loguru import logger


class DataLoader:
    """Load and validate historical market data"""
    
    # Initialized lazily
    TIMEFRAME_MAP = {} 

    def __init__(self):
        """Initialize data loader"""
        self.mt5_initialized = False

    def load_from_mt5(
        self,
        symbol: str,
        timeframe: str,
        start_date: datetime,
        end_date: datetime
    ) -> Optional[pd.DataFrame]:
        """
        Load historical data from MT5

        Args:
            symbol: Trading symbol (e.g., "EURUSD")
            timeframe: Timeframe string (e.g., "H1")
            start_date: Start date
            end_date: End date

        Returns:
            DataFrame with columns: time, open, high, low, close, volume
        """
        logger.info(f"📥 Loading {symbol} {timeframe} from MT5: {start_date} to {end_date}")

        # Initialize MT5 if needed
        # Initialize MT5 if needed via RPyC
        if not self.mt5_initialized:
            try:
                mt5_host = os.getenv("MT5_HOST", "mt5")
                mt5_port = int(os.getenv("MT5_PORT", 18812))
                logger.info(f"🔌 Connecting to MT5 Service at {mt5_host}:{mt5_port}...")
                
                # Retry logic for slow startups
                max_retries = 5
                conn = None
                for i in range(max_retries):
                    try:
                        conn = rpyc.classic.connect(mt5_host, mt5_port)
                        break
                    except Exception as connection_err:
                        if i < max_retries - 1:
                            logger.warning(f"R Connection attempt {i+1}/{max_retries} failed. Retrying in 2s...")
                            import time
                            time.sleep(2)
                        else:
                            raise connection_err
                            
                logger.info(f"R RPyC connection established")

                global mt5
                mt5 = conn.modules.MetaTrader5
                logger.info(f"📦 MetaTrader5 module loaded via RPyC")

                logger.info(f"🔄 Initializing MT5...")
                if not mt5.initialize():
                    logger.error("❌ MT5 initialization failed")
                    return None
                logger.info(f"R MT5 initialized successfully")

                # Populate TIMEFRAME_MAP dynamically
                self.TIMEFRAME_MAP = {
                    'M1': mt5.TIMEFRAME_M1,
                    'M5': mt5.TIMEFRAME_M5,
                    'M15': mt5.TIMEFRAME_M15,
                    'M30': mt5.TIMEFRAME_M30,
                    'H1': mt5.TIMEFRAME_H1,
                    'H4': mt5.TIMEFRAME_H4,
                    'D1': mt5.TIMEFRAME_D1,
                }

                self.mt5_initialized = True
                logger.info(f"R MT5 DataLoader fully initialized")
            except Exception as e:
                logger.error(f"❌ Failed to connect to MT5 Service: {e}")
                logger.exception("Full exception trace:")
                return None

        # Get timeframe constant
        mt5_timeframe = self.TIMEFRAME_MAP.get(timeframe)
        if not mt5_timeframe:
            logger.error(f"Invalid timeframe: {timeframe}")
            return None

        # Ensure symbol is selected in Market Watch
        # Try with common broker prefixes/suffixes if base symbol fails
        def try_symbol_variants(base_symbol: str) -> str:
            """Try common broker symbol variations and return the first that works."""
            # Common broker prefixes and suffixes
            prefixes = ['', 'm', 'x', '.']
            suffixes = ['', 'm', '.a', '.b', 'pro', 'i', '_SB']
            
            for prefix in prefixes:
                for suffix in suffixes:
                    variant = f"{prefix}{base_symbol}{suffix}"
                    if mt5.symbol_select(variant, True):
                        if variant != base_symbol:
                            logger.info(f"R Symbol {base_symbol} resolved to {variant}")
                        return variant
            return None
        
        resolved_symbol = try_symbol_variants(symbol)
        if resolved_symbol:
            symbol = resolved_symbol
        else:
            logger.error(f"Failed to select symbol {symbol} in MT5 (tried common variants)")
            return None

        # Ensure dates are naive (MT5 preference)
        # MT5 usually expects local time or server time.
        # If we have UTC, we should convert to naive.
        if start_date.tzinfo is not None:
            start_date = start_date.replace(tzinfo=None)
        if end_date.tzinfo is not None:
            end_date = end_date.replace(tzinfo=None)

        # Remove microseconds - MT5 doesn't accept them
        start_date = start_date.replace(microsecond=0)
        end_date = end_date.replace(microsecond=0)

        logger.info(f"R Requesting MT5 data for {symbol} {timeframe} from {start_date} to {end_date}")

        # Fetch data in chunks (monthly) to avoid timeouts/limits
        chunks = []
        current_start = start_date

        while current_start < end_date:
            current_end = min(current_start + timedelta(days=30), end_date)
            logger.info(f"📦 Fetching chunk: {current_start} to {current_end}")
            
            try:
                # Convert datetime objects to Unix timestamps (MT5 requirement)
                start_timestamp = int(current_start.timestamp())
                end_timestamp = int(current_end.timestamp())

                rates = mt5.copy_rates_range(
                    symbol,
                    mt5_timeframe,
                    start_timestamp,
                    end_timestamp
                )

                if rates is not None and len(rates) > 0:
                    logger.info(f"R Chunk received: {len(rates)} bars")
                    # Convert RPyC netref to local numpy array
                    local_rates = obtain(rates)
                    chunks.append(local_rates)
                else:
                    error = mt5.last_error()
                    if error[0] != 1: # 1 = No data, which is fine for some chunks
                        logger.warning(f"R  Chunk failed or empty: {error}")

            except Exception as e:
                logger.error(f"❌ Error fetching chunk: {e}")

            current_start = current_end

        if not chunks:
            logger.error(f"❌ No data received from MT5 for {symbol} after all chunks.")
            return None

        logger.info(f"🔗 Concatenating {len(chunks)} chunks...")
        # Concatenate all chunks into a single numpy structured array
        import numpy as np
        all_rates = np.concatenate(chunks)
        logger.info(f"R Total bars fetched: {len(all_rates)}")

        # Convert to DataFrame (preserves structured array fields as columns)
        df = pd.DataFrame(all_rates)
        
        # Drop duplicates if any (from chunk overlaps if logic wasn't perfect, though here it is)
        df.drop_duplicates(subset=['time'], inplace=True)

        # Convert time to datetime
        df['time'] = pd.to_datetime(df['time'], unit='s')

        # Select and rename columns
        df = df[['time', 'open', 'high', 'low', 'close', 'tick_volume']]
        df.rename(columns={'tick_volume': 'volume'}, inplace=True)
        
        # Sort by time
        df.sort_values('time', inplace=True)
        df.reset_index(drop=True, inplace=True)

        logger.info(f"Loaded {len(df)} bars from MT5 (Total)")
        return df

    def load_from_csv(
        self,
        filepath: str,
        date_column: str = 'time'
    ) -> Optional[pd.DataFrame]:
        """
        Load historical data from CSV file

        Expected CSV format:
        time,open,high,low,close,volume
        2021-01-01 00:00:00,1.2150,1.2160,1.2145,1.2155,1000

        Args:
            filepath: Path to CSV file
            date_column: Name of date/time column

        Returns:
            DataFrame with standardized columns
        """
        logger.info(f"Loading data from CSV: {filepath}")

        try:
            # Read CSV
            df = pd.DataFrame(filepath)

            # Parse time column
            if date_column in df.columns:
                df['time'] = pd.to_datetime(df[date_column])
                if date_column != 'time':
                    df = df.drop(columns=[date_column])

            # Validate required columns
            required_columns = ['time', 'open', 'high', 'low', 'close']
            missing = [col for col in required_columns if col not in df.columns]

            if missing:
                logger.error(f"Missing required columns: {missing}")
                return None

            # Add volume if missing
            if 'volume' not in df.columns:
                logger.warning("Volume column missing, adding placeholder values")
                df['volume'] = 0

            # Ensure correct column order
            df = df[['time', 'open', 'high', 'low', 'close', 'volume']]

            # Sort by time
            df = df.sort_values('time').reset_index(drop=True)

            logger.info(f"Loaded {len(df)} bars from CSV")
            return df

        except Exception as e:
            logger.error(f"Error loading from CSV: {e}")
            return None

    def validate_data(self, df: pd.DataFrame) -> Tuple[bool, list]:
        """
        Validate data quality

        Checks:
        - No missing values in OHLC
        - High >= Low
        - High >= Open, Close
        - Low <= Open, Close
        - No duplicate timestamps
        - No gaps > expected timeframe

        Args:
            df: DataFrame to validate

        Returns:
            (is_valid, list_of_issues)
        """
        issues = []

        # Check for missing values
        missing = df[['open', 'high', 'low', 'close']].isnull().sum()
        if missing.any():
            issues.append(f"Missing values found: {missing.to_dict()}")

        # Check OHLC logic
        invalid_high = (df['high'] < df['low']).sum()
        if invalid_high > 0:
            issues.append(f"{invalid_high} bars where high < low")

        invalid_high_open = (df['high'] < df['open']).sum()
        if invalid_high_open > 0:
            issues.append(f"{invalid_high_open} bars where high < open")

        invalid_high_close = (df['high'] < df['close']).sum()
        if invalid_high_close > 0:
            issues.append(f"{invalid_high_close} bars where high < close")

        invalid_low_open = (df['low'] > df['open']).sum()
        if invalid_low_open > 0:
            issues.append(f"{invalid_low_open} bars where low > open")

        invalid_low_close = (df['low'] > df['close']).sum()
        if invalid_low_close > 0:
            issues.append(f"{invalid_low_close} bars where low > close")

        # Check for duplicates
        duplicates = df['time'].duplicated().sum()
        if duplicates > 0:
            issues.append(f"{duplicates} duplicate timestamps")

        # Check for gaps (basic check)
        time_diffs = df['time'].diff()
        median_diff = time_diffs.median()
        large_gaps = (time_diffs > median_diff * 3).sum()
        if large_gaps > 10:  # Allow some gaps (weekends, holidays)
            issues.append(f"{large_gaps} large time gaps detected (>3x median)")

        is_valid = len(issues) == 0

        if is_valid:
            logger.info("R Data validation passed")
        else:
            logger.warning(f"R Data validation issues: {issues}")

        return is_valid, issues

    def load_and_validate(
        self,
        symbol: str,
        timeframe: str,
        start_date: datetime,
        end_date: datetime,
        source: str = 'mt5',
        csv_path: Optional[str] = None
    ) -> Optional[pd.DataFrame]:
        """
        Load data and validate in one step

        Args:
            symbol: Trading symbol
            timeframe: Timeframe
            start_date: Start date
            end_date: End date
            source: 'mt5' or 'csv'
            csv_path: Path to CSV if source='csv'

        Returns:
            Validated DataFrame or None
        """
        # Load data
        if source == 'mt5':
            df = self.load_from_mt5(symbol, timeframe, start_date, end_date)
        elif source == 'csv':
            if not csv_path:
                logger.error("CSV path required when source='csv'")
                return None
            df = self.load_from_csv(csv_path)
        else:
            logger.error(f"Invalid source: {source}")
            return None

        if df is None:
            return None

        # Validate
        is_valid, issues = self.validate_data(df)

        if not is_valid:
            logger.warning("Data validation failed but returning data anyway")
            logger.warning(f"Issues: {issues}")

        # Filter by date range if from CSV
        if source == 'csv':
            df = df[(df['time'] >= start_date) & (df['time'] <= end_date)]
            logger.info(f"Filtered to {len(df)} bars within date range")

        return df

    def save_to_csv(
        self,
        df: pd.DataFrame,
        filepath: str
    ) -> bool:
        """
        Save DataFrame to CSV for future use

        Args:
            df: DataFrame to save
            filepath: Output path

        Returns:
            Success status
        """
        try:
            # Ensure directory exists
            Path(filepath).parent.mkdir(parents=True, exist_ok=True)

            # Save
            df.to_csv(filepath, index=False)
            logger.info(f"Saved {len(df)} bars to {filepath}")
            return True

        except Exception as e:
            logger.error(f"Error saving to CSV: {e}")
            return False

    def resample_to_higher_tf(self, df: pd.DataFrame, target_tf: str) -> Optional[pd.DataFrame]:
        """
        Resample lower timeframe data to higher timeframe.
        This avoids loading multiple datasets from MT5 for performance.
        
        Example conversions:
        - M1 -> M5: '5min'
        - M1 -> M15: '15min'
        - M5 -> H1: '1h'
        
        Args:
            df: DataFrame with lower timeframe data
            target_tf: Target timeframe string (M5, M15, M30, H1, H4, D1)
            
        Returns:
            Resampled DataFrame or None if invalid target
        """
        resample_map = {
            'M1': '1min',
            'M5': '5min',
            'M15': '15min',
            'M30': '30min',
            'H1': '1h',
            'H4': '4h',
            'D1': '1D'
        }
        
        freq = resample_map.get(target_tf)
        if not freq:
            logger.error(f"Invalid target timeframe for resampling: {target_tf}")
            return None
        
        try:
            # Ensure time column is the index for resampling
            df_copy = df.copy()
            df_copy.set_index('time', inplace=True)
            
            # Resample OHLCV data
            df_resampled = df_copy.resample(freq).agg({
                'open': 'first',
                'high': 'max',
                'low': 'min',
                'close': 'last',
                'volume': 'sum'
            }).dropna()
            
            # Reset index to get time back as a column
            df_resampled.reset_index(inplace=True)
            
            logger.info(f"Resampled {len(df)} bars to {len(df_resampled)} {target_tf} bars")
            return df_resampled
            
        except Exception as e:
            logger.error(f"Error resampling data: {e}")
            return None

    def get_data_info(self, df: pd.DataFrame) -> dict:
        """Get summary info about loaded data"""
        if df is None or len(df) == 0:
            return {}

        return {
            'total_bars': len(df),
            'start_date': df['time'].min(),
            'end_date': df['time'].max(),
            'date_range_days': (df['time'].max() - df['time'].min()).days,
            'price_range': {
                'min': df['low'].min(),
                'max': df['high'].max(),
                'avg': df['close'].mean()
            },
            'missing_values': df.isnull().sum().to_dict(),
        }

    def shutdown(self):
        """Shutdown MT5 connection"""
        if self.mt5_initialized:
            mt5.shutdown()
            self.mt5_initialized = False
            logger.info("MT5 connection closed")
