"""
Prediction Service - Generates ML predictions for allocated portfolio symbols

This service runs in the background and generates predictions every 5 minutes
for all symbols that have active allocations in the selected portfolio.
"""

import logging
import pickle
import pandas as pd
from datetime import datetime, timedelta
from pathlib import Path
import sys

# Add parent directory to path
sys.path.append(str(Path(__file__).parent.parent.parent))
from src.database import DatabaseManager
from src.features import create_talib_features, create_basic_features

class PredictionService:
    """Generates predictions for portfolio-allocated symbols."""

    def __init__(self, db: DatabaseManager, bridge_url: str = "http://localhost:5000"):
        self.db = db
        self.bridge_url = bridge_url
        self.logger = logging.getLogger(__name__)
        
    def generate_predictions_for_portfolio(self, portfolio_id: int):
        """Generate predictions for all allocated symbols in a portfolio."""
        self.logger.info(f"🔵 PORTFOLIO PREDICTION START: portfolio_id={portfolio_id}")

        allocations = self.db.get_allocations(portfolio_id)

        if not allocations:
            self.logger.info(f"No allocations found for portfolio {portfolio_id}")
            return

        self.logger.info(f"🔵 Found {len(allocations)} allocations to process")

        for alloc in allocations:
            if alloc['weight'] <= 0:
                continue

            symbol = alloc['symbol']
            model_id = alloc['model_id']

            self.logger.info(f"🔵 CALLING _generate_prediction for {symbol}, model_id={model_id}")

            try:
                self._generate_prediction(symbol, model_id)
                self.logger.info(f"🔵 COMPLETED _generate_prediction for {symbol}")
            except Exception as e:
                self.logger.error(f"❌ EXCEPTION in _generate_prediction for {symbol}: {type(e).__name__}: {e}", exc_info=True)
    
    def _generate_prediction(self, symbol: str, model_id: int):
        """Generate a single prediction for a symbol using a specific model."""
        self.logger.info(f"🔵 PREDICTION SERVICE v2.0: Generating prediction for {symbol}, model_id={model_id}")

        # Get model metadata
        model_meta = self.db.get_model(model_id)
        if not model_meta:
            self.logger.error(f"🔴 EARLY RETURN: Model {model_id} not found in database")
            return

        model_path = model_meta['file_path']
        timeframe = model_meta.get('timeframe', 'H1')

        self.logger.info(f"🔵 Model metadata loaded: path={model_path}, timeframe={timeframe}")

        # Load model to get features list
        model_file = Path(model_path)
        if not model_file.exists():
            self.logger.warning(f"🟡 Model file not found: {model_path}")
            # Try to find substitute model for same symbol/timeframe
            # Pattern: mlp_optuna_{symbol}_{timeframe}_*.pkl
            try:
                models_dir = Path("/app/models")
                self.logger.info(f"🔵 Searching for substitute in: {models_dir}")
                if models_dir.exists():
                    # Construct pattern based on expected naming convention
                    # We need symbol and timeframe. Metadata from DB has 'hyperparameters' which usually has them
                    # Or we can guess from the filename payload
                    # Let's try to match the prefix of the missing file
                    filename = model_file.name
                    parts = filename.split('_')
                    # e.g. mlp_optuna_EURUSD_M15_2026...
                    if len(parts) >= 4:
                        prefix = "_".join(parts[:4]) # mlp_optuna_EURUSD_M15
                        candidates = list(models_dir.glob(f"{prefix}*.pkl"))
                        if candidates:
                            # Sort by modification time (latest first)
                            candidates.sort(key=lambda x: x.stat().st_mtime, reverse=True)
                            model_file = candidates[0]
                            self.logger.info(f"✅ Found substitute model: {model_file}")
                        else:
                             self.logger.error(f"🔴 EARLY RETURN: No substitute models found for pattern {prefix}")
                             return
                    else:
                        self.logger.error(f"🔴 EARLY RETURN: Cannot parse filename {filename}")
                        return
                else:
                    self.logger.error(f"🔴 EARLY RETURN: Models directory does not exist: {models_dir}")
                    return
            except Exception as e:
                self.logger.error(f"🔴 EARLY RETURN: Error searching for substitute model: {e}")
                return
        
        with open(model_file, 'rb') as f:
            model_data = pickle.load(f)
        
        framework = model_data.get('framework', 'standard')
        
        # Phase 7: Handle Hybrid Ensembles
        if framework == 'hybrid':
            self.logger.info(f"Loading hybrid ensemble for {symbol}")
            ensemble = model_data['ensemble']
            tf_model_paths = model_data.get('tf_model_paths', {})
            
            # Reconstruct TF models in the wrappers
            from tensorflow import keras
            from src.training.ensemble_trainer import TensorFlowWrapper
            
            # Handle ensemble.estimators_ which should be list of (name, estimator) tuples
            # But might be improperly formatted in older models
            try:
                for item in ensemble.estimators_:
                    # Try to unpack as tuple
                    if isinstance(item, tuple) and len(item) == 2:
                        name, est = item
                    else:
                        # Fallback: item is the estimator directly
                        est = item
                        name = type(est).__name__

                    if isinstance(est, TensorFlowWrapper):
                        path = tf_model_paths.get(name) or getattr(est, 'model_path', None)
                        if path and Path(path).exists():
                            self.logger.debug(f"Loading TF model part '{name}' from {path}")
                            # Use custom_objects if needed
                            from src.training.tf_models import AttentionLayer
                            est.model = keras.models.load_model(path, custom_objects={'AttentionLayer': AttentionLayer})
                        else:
                            self.logger.error(f"TF model part '{name}' not found at {path}")
                            return
            except Exception as e:
                self.logger.error(f"Error loading ensemble estimators: {e}")
                return
            
            model = ensemble
            scaler = model_data['scaler']
            features = model_data['features']
        else:
            model = model_data['model']
            scaler = model_data['scaler']
            features = model_data.get('features', [])
            if not features and 'feature_names' in model_data:
                features = model_data['feature_names']
        
        # Auto-detect if TA-Lib features are used
        talib_indicators = ['ADX', 'MACD', 'RSI', 'SMA_', 'EMA_', 'ATR', 'BBANDS', 'STOCH', 'WILLR', 'ROC', 'CCI', 'OBV', 'MFI', 'AD']
        use_talib = any(any(indicator in feat for indicator in talib_indicators) for feat in features)
        
        self.logger.info(f"Generating prediction for {symbol} using {'TA-Lib' if use_talib else 'basic'} features")
        
        # Get market data (need more bars for TA-Lib indicators + LSTM sequences)
        # Minimum needed: max(100 for TA-Lib, sequence_length + 50 for warmup)
        sequence_length = model_data.get('sequence_length', 30)
        bars_needed = max(100 if use_talib else 50, sequence_length + 70)  # Extra for dropna

        self.logger.debug(f"Need {bars_needed} bars for {symbol} (use_talib={use_talib}, seq_len={sequence_length})")

        query = """
            SELECT timestamp, open, high, low, close, tick_volume, spread, real_volume
            FROM market_data
            WHERE symbol = %s AND timeframe = %s
            ORDER BY timestamp DESC
            LIMIT %s
        """
        with self.db.get_connection() as conn:
            cursor = conn.execute(query, (symbol, timeframe, bars_needed))
            rows = cursor.fetchall()
            if rows:
                df = pd.DataFrame([dict(row) for row in rows])
            else:
                df = pd.DataFrame()

        self.logger.info(f"📊 Fetched {len(df)} bars from DB for {symbol} (need {bars_needed})")

        # AUTO-FETCH: If not enough data, fetch from MT5 bridge
        if len(df) < bars_needed:
            self.logger.warning(f"⚠️  Only {len(df)} bars in DB, need {bars_needed}. Auto-fetching from MT5...")
            try:
                import requests

                fetch_count = bars_needed + 50  # Extra for safety
                self.logger.info(f"🔄 Requesting {fetch_count} bars from bridge: {self.bridge_url}")

                # Fetch historical data from MT5
                response = requests.post(
                    f"{self.bridge_url}/fetch_data",
                    json={
                        "symbol": symbol,
                        "timeframe": timeframe,
                        "count": fetch_count
                    },
                    timeout=30
                )

                self.logger.debug(f"Bridge response status: {response.status_code}")

                if response.status_code == 200:
                    result = response.json()
                    self.logger.debug(f"Bridge response: {result}")

                    if result.get('status') == 'success':
                        bars_saved = result.get('bars_saved', 0)
                        self.logger.info(f"✅ Fetched and saved {bars_saved} bars from MT5")

                        # Re-query database
                        with self.db.get_connection() as conn:
                            cursor = conn.execute(query, (symbol, timeframe, bars_needed))
                            rows = cursor.fetchall()
                            if rows:
                                df = pd.DataFrame([dict(row) for row in rows])
                                self.logger.info(f"✅ Re-queried DB: now have {len(df)} bars")
                            else:
                                self.logger.error("❌ Re-query returned no data!")
                    else:
                        self.logger.error(f"❌ Bridge fetch failed: {result.get('message', 'Unknown error')}")
                else:
                    self.logger.error(f"❌ Bridge HTTP error: {response.status_code}")
                    try:
                        self.logger.error(f"Response: {response.text[:200]}")
                    except:
                        pass
            except requests.exceptions.ConnectionError as e:
                self.logger.error(f"❌ Cannot connect to MT5 bridge at {self.bridge_url}: {e}")
            except Exception as e:
                self.logger.error(f"❌ Error auto-fetching data: {type(e).__name__}: {e}", exc_info=True)

        if len(df) < 50:
            self.logger.warning(f"Not enough data for {symbol} (got {len(df)} bars after fetch)")
            return
        
        # Create features
        df = df.sort_values('timestamp')
        
        if use_talib:
            df = create_talib_features(df)
        else:
            df = create_basic_features(df)
        
        df = df.dropna()
        
        if len(df) == 0:
            self.logger.warning(f"No data after feature creation for {symbol}")
            return
        
        # Get latest features
        # CRITICAL FIX: For LSTM models in ensemble, we need sequence_length rows, not just 1
        # Get the sequence_length from model_data if available
        sequence_length = model_data.get('sequence_length', 30)  # Default to 30

        # Check for missing features
        missing_features = [f for f in features if f not in df.columns]
        if missing_features:
            self.logger.error(f"Missing features for {symbol}: {missing_features[:5]}")
            return

        # Prepare input with enough rows for LSTM sequences
        # Take the last sequence_length rows to create sequences
        if len(df) < sequence_length:
            self.logger.warning(f"Not enough data for LSTM sequences: need {sequence_length}, have {len(df)}")
            return

        # Prepare input as DataFrame with last sequence_length rows
        X = df[features].iloc[-sequence_length:]
        X_scaled = scaler.transform(X)
        
        # Make prediction
        # For ensemble with LSTM, predictions are padded. We want the LAST prediction (most recent)
        predictions = model.predict(X_scaled)
        probabilities = model.predict_proba(X_scaled)

        # Take the last prediction (for the most recent data point)
        prediction = predictions[-1]
        confidence = probabilities[-1].max()

        direction = "BUY" if prediction == 1 else "SELL"

        # Save to database
        # Prediction is for 24 bars ahead (24 hours for H1) - updated from 12 in Phase 3
        latest_timestamp = df.iloc[-1]['timestamp']
        window_start = pd.to_datetime(latest_timestamp)
        prediction_horizon = 24  # Matches training target (shift(-24))
        window_end = window_start + timedelta(hours=prediction_horizon)

        self.db.insert_prediction(
            model_id=model_id,
            symbol=symbol,
            prediction_direction=direction,
            confidence=confidence,
            window_start=window_start,
            window_end=window_end,
            prediction_horizon=prediction_horizon
        )
        
        self.logger.info(f"✅ Generated prediction for {symbol}: {direction} ({confidence:.1%})")
