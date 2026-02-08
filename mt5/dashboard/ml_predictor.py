"""
ML Predictor - Machine Learning Performance Prediction
=======================================================
Uses scikit-learn to predict next-day trading performance based on:
- Market conditions (ATR, trend strength, volatility)
- Recent performance metrics
- Regime characteristics
- Session context

Main functions:
- capture_market_conditions(): Extract and store features
- train_model(): Train RandomForestRegressor on historical data
- generate_predictions(): Predict next-day performance
- evaluate_predictions(): Compare predictions vs actuals

Model: RandomForestRegressor (initial implementation)
Target: Next-day Sharpe ratio
"""

import sqlite3
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import Dict, List, Tuple, Optional
import json
import pickle
import os

from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split, cross_val_score
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import mean_squared_error, mean_absolute_error, r2_score
import warnings
warnings.filterwarnings('ignore')


class MLPredictor:
    def __init__(self, db_path: str):
        self.db_path = db_path
        self.model = None
        self.scaler = StandardScaler()
        self.feature_names = []
        self.model_version = "v1.0_RandomForest"

    def get_connection(self):
        """Get database connection"""
        return sqlite3.connect(self.db_path, check_same_thread=False)

    # =========================================================================
    # FEATURE EXTRACTION
    # =========================================================================

    def capture_market_conditions(self, symbol: str, timestamp: int = None):
        """
        Capture current market conditions and store in MarketConditions table.

        Args:
            symbol: Symbol to analyze
            timestamp: Unix timestamp (defaults to now)

        Returns:
            Dict of features captured
        """
        conn = self.get_connection()
        cursor = conn.cursor()

        if timestamp is None:
            timestamp = int(datetime.now().timestamp())

        try:
            # Get recent market data (last 100 bars)
            df_market = pd.read_sql("""
                SELECT * FROM MarketData
                WHERE symbol = ? AND timeframe = 60
                ORDER BY time DESC LIMIT 100
            """, conn, params=(symbol,))

            if df_market.empty:
                print(f"No market data for {symbol}")
                return None

            # Calculate features
            df_market = df_market.sort_values('time')

            # ATR (Average True Range)
            df_market['hl'] = df_market['high'] - df_market['low']
            df_market['hc'] = abs(df_market['high'] - df_market['close'].shift(1))
            df_market['lc'] = abs(df_market['low'] - df_market['close'].shift(1))
            df_market['tr'] = df_market[['hl', 'hc', 'lc']].max(axis=1)
            atr = df_market['tr'].rolling(14).mean().iloc[-1]

            # ATR Percentile (where is ATR vs historical range)
            atr_90d = df_market['tr'].rolling(90).mean()
            atr_percentile = (atr - atr_90d.min()) / (atr_90d.max() - atr_90d.min()) * 100 if atr_90d.max() > atr_90d.min() else 50

            # Trend Strength (ADX-like)
            df_market['price_change'] = df_market['close'].diff()
            trend_strength = abs(df_market['price_change'].rolling(14).mean().iloc[-1]) / atr if atr > 0 else 0

            # Choppiness Index
            atr_sum = df_market['tr'].rolling(14).sum().iloc[-1]
            high_low_range = df_market['high'].rolling(14).max().iloc[-1] - df_market['low'].rolling(14).min().iloc[-1]
            chop_index = 100 * np.log10(atr_sum / high_low_range) / np.log10(14) if high_low_range > 0 else 50

            # Realized Volatility (std of returns)
            df_market['returns'] = df_market['close'].pct_change()
            realized_volatility = df_market['returns'].std() * np.sqrt(252) * 100  # Annualized %

            # Volatility Rank (percentile)
            volatility_90d = df_market['returns'].rolling(90).std()
            vol_rank = (realized_volatility - volatility_90d.min() * np.sqrt(252) * 100) / \
                       ((volatility_90d.max() - volatility_90d.min()) * np.sqrt(252) * 100) * 100 if volatility_90d.max() > volatility_90d.min() else 50

            # RSI
            delta = df_market['close'].diff()
            gain = delta.where(delta > 0, 0).rolling(14).mean()
            loss = -delta.where(delta < 0, 0).rolling(14).mean()
            rs = gain / loss if loss.iloc[-1] > 0 else 100
            rsi = 100 - (100 / (1 + rs.iloc[-1])) if not pd.isna(rs.iloc[-1]) else 50

            # Momentum
            momentum = (df_market['close'].iloc[-1] - df_market['close'].iloc[-20]) / df_market['close'].iloc[-20] * 100 if len(df_market) >= 20 else 0

            # Get regime from recent trades
            df_trades = pd.read_sql("""
                SELECT regime FROM Trades
                WHERE symbol = ? AND entry_time > ?
                ORDER BY entry_time DESC LIMIT 10
            """, conn, params=(symbol, timestamp - 86400))

            regime = df_trades['regime'].mode()[0] if not df_trades.empty else 'UNKNOWN'

            # Count regime duration (how long in this regime)
            regime_duration = len(df_trades[df_trades['regime'] == regime])

            # Get current killzone
            hour = datetime.fromtimestamp(timestamp).hour
            if 0 <= hour < 8:
                killzone = 'Asian'
            elif 8 <= hour < 12:
                killzone = 'London Open'
            elif 12 <= hour < 17:
                killzone = 'NY'
            elif 17 <= hour < 20:
                killzone = 'London Close'
            else:
                killzone = 'NONE'

            # Time of day
            if 6 <= hour < 12:
                time_of_day = 'Morning'
            elif 12 <= hour < 18:
                time_of_day = 'Afternoon'
            else:
                time_of_day = 'Evening'

            # Count recent swings (simple swing detection)
            df_market['swing_high'] = (df_market['high'] > df_market['high'].shift(1)) & \
                                      (df_market['high'] > df_market['high'].shift(-1))
            df_market['swing_low'] = (df_market['low'] < df_market['low'].shift(1)) & \
                                     (df_market['low'] < df_market['low'].shift(-1))
            recent_swing_count = df_market[['swing_high', 'swing_low']].tail(50).sum().sum()

            # Store in MarketConditions table
            cursor.execute("""
                INSERT OR REPLACE INTO MarketConditions (
                    timestamp, symbol, timeframe, atr, atr_percentile,
                    trend_strength, chop_index, regime, regime_duration_bars,
                    realized_volatility, volatility_rank, rsi, momentum,
                    recent_swing_count, killzone, time_of_day
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                timestamp, symbol, 60, atr, atr_percentile,
                trend_strength, chop_index, regime, regime_duration,
                realized_volatility, vol_rank, rsi, momentum,
                recent_swing_count, killzone, time_of_day
            ))

            conn.commit()

            features = {
                'atr': atr,
                'atr_percentile': atr_percentile,
                'trend_strength': trend_strength,
                'chop_index': chop_index,
                'regime': regime,
                'realized_volatility': realized_volatility,
                'volatility_rank': vol_rank,
                'rsi': rsi,
                'momentum': momentum,
                'killzone': killzone
            }

            print(f"✅ Market conditions captured for {symbol}")
            return features

        except Exception as e:
            print(f"❌ Error capturing market conditions: {e}")
            conn.rollback()
            return None
        finally:
            conn.close()

    # =========================================================================
    # MODEL TRAINING
    # =========================================================================

    def prepare_training_data(self, min_samples: int = 30) -> Tuple[pd.DataFrame, pd.Series]:
        """
        Prepare training dataset by joining market conditions with actual performance.

        Returns:
            X (features), y (target Sharpe ratio)
        """
        conn = self.get_connection()

        try:
            # Get market conditions with next-day performance
            query = """
                SELECT
                    mc.*,
                    sp.sharpe_ratio as target_sharpe,
                    sp.win_rate as target_winrate,
                    sp.total_pnl as target_pnl
                FROM MarketConditions mc
                LEFT JOIN SymbolPerformance sp
                    ON mc.symbol = sp.symbol
                    AND DATE(mc.timestamp, 'unixepoch', '+1 day') = sp.date
                WHERE sp.sharpe_ratio IS NOT NULL
            """

            df = pd.read_sql(query, conn)

            if len(df) < min_samples:
                print(f"⚠️ Insufficient data for training: {len(df)} samples (need {min_samples})")
                return None, None

            # Feature engineering
            features = [
                'atr', 'atr_percentile', 'trend_strength', 'chop_index',
                'realized_volatility', 'volatility_rank', 'rsi', 'momentum',
                'recent_swing_count', 'regime_duration_bars'
            ]

            # Encode categorical features
            df['regime_encoded'] = df['regime'].map({
                'TREND': 1, 'RANGE': 2, 'VOLATILE': 3, 'UNKNOWN': 0
            }).fillna(0)

            df['killzone_encoded'] = df['killzone'].map({
                'Asian': 1, 'London Open': 2, 'NY': 3, 'London Close': 4, 'NONE': 0
            }).fillna(0)

            df['time_of_day_encoded'] = df['time_of_day'].map({
                'Morning': 1, 'Afternoon': 2, 'Evening': 3
            }).fillna(0)

            features += ['regime_encoded', 'killzone_encoded', 'time_of_day_encoded']

            # Handle missing values
            X = df[features].fillna(0)
            y = df['target_sharpe']

            self.feature_names = features

            print(f"✅ Training data prepared: {len(X)} samples, {len(features)} features")

            return X, y

        except Exception as e:
            print(f"❌ Error preparing training data: {e}")
            return None, None
        finally:
            conn.close()

    def train_model(self, n_estimators: int = 100, test_size: float = 0.2):
        """
        Train RandomForestRegressor to predict next-day Sharpe ratio.

        Args:
            n_estimators: Number of trees in forest
            test_size: Fraction of data for testing

        Returns:
            Dict with training metrics
        """
        print("\n🔄 Training ML model...")

        # Prepare data
        X, y = self.prepare_training_data()

        if X is None or y is None:
            return None

        # Split train/test
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=test_size, random_state=42
        )

        # Scale features
        X_train_scaled = self.scaler.fit_transform(X_train)
        X_test_scaled = self.scaler.transform(X_test)

        # Train model
        self.model = RandomForestRegressor(
            n_estimators=n_estimators,
            max_depth=10,
            min_samples_split=5,
            min_samples_leaf=2,
            random_state=42,
            n_jobs=-1
        )

        self.model.fit(X_train_scaled, y_train)

        # Evaluate
        y_pred_train = self.model.predict(X_train_scaled)
        y_pred_test = self.model.predict(X_test_scaled)

        train_r2 = r2_score(y_train, y_pred_train)
        test_r2 = r2_score(y_test, y_pred_test)
        train_rmse = np.sqrt(mean_squared_error(y_train, y_pred_train))
        test_rmse = np.sqrt(mean_squared_error(y_test, y_pred_test))
        train_mae = mean_absolute_error(y_train, y_pred_train)
        test_mae = mean_absolute_error(y_test, y_pred_test)

        # Cross-validation
        cv_scores = cross_val_score(self.model, X_train_scaled, y_train, cv=5, scoring='r2')

        # Feature importance
        feature_importance = pd.DataFrame({
            'feature': self.feature_names,
            'importance': self.model.feature_importances_
        }).sort_values('importance', ascending=False)

        metrics = {
            'train_r2': train_r2,
            'test_r2': test_r2,
            'train_rmse': train_rmse,
            'test_rmse': test_rmse,
            'train_mae': train_mae,
            'test_mae': test_mae,
            'cv_mean_r2': cv_scores.mean(),
            'cv_std_r2': cv_scores.std(),
            'n_samples': len(X),
            'n_features': len(self.feature_names),
            'feature_importance': feature_importance.to_dict('records')
        }

        print(f"\n✅ Model trained successfully!")
        print(f"Train R²: {train_r2:.3f} | Test R²: {test_r2:.3f}")
        print(f"Train RMSE: {train_rmse:.3f} | Test RMSE: {test_rmse:.3f}")
        print(f"CV R² (5-fold): {cv_scores.mean():.3f} ± {cv_scores.std():.3f}")

        print(f"\nTop 5 Important Features:")
        for i, row in feature_importance.head(5).iterrows():
            print(f"  {row['feature']:25} {row['importance']:.4f}")

        return metrics

    # =========================================================================
    # PREDICTION
    # =========================================================================

    def generate_predictions(self, date: str = None, symbols: List[str] = None):
        """
        Generate predictions for next-day performance.

        Args:
            date: Prediction date (defaults to tomorrow)
            symbols: List of symbols (defaults to all active symbols)
        """
        if self.model is None:
            print("❌ Model not trained. Call train_model() first.")
            return

        conn = self.get_connection()
        cursor = conn.cursor()

        if date is None:
            date = (datetime.now() + timedelta(days=1)).strftime('%Y-%m-%d')

        try:
            # Get symbols
            if symbols is None:
                symbols = pd.read_sql("SELECT DISTINCT symbol FROM SymbolConfigs", conn)['symbol'].tolist()

            timestamp_now = int(datetime.now().timestamp())

            for symbol in symbols:
                # Capture current market conditions
                features = self.capture_market_conditions(symbol, timestamp_now)

                if features is None:
                    continue

                # Get latest market conditions from DB
                df_conditions = pd.read_sql("""
                    SELECT * FROM MarketConditions
                    WHERE symbol = ?
                    ORDER BY timestamp DESC LIMIT 1
                """, conn, params=(symbol,))

                if df_conditions.empty:
                    continue

                # Prepare features
                X_features = df_conditions[self.feature_names].fillna(0)
                X_scaled = self.scaler.transform(X_features)

                # Predict
                predicted_sharpe = self.model.predict(X_scaled)[0]

                # Simple heuristics for other predictions
                predicted_winrate = 50 + (predicted_sharpe * 10)  # Rough estimate
                predicted_pnl = predicted_sharpe * 100  # Rough estimate

                # Confidence score (based on feature variance)
                confidence_score = min(1.0, max(0.0, (test_r2 if 'test_r2' in locals() else 0.5)))

                # Recommendation
                if predicted_sharpe > 1.0:
                    recommended_action = 'TRADE'
                    risk_multiplier = 1.5
                elif predicted_sharpe > 0.5:
                    recommended_action = 'TRADE'
                    risk_multiplier = 1.0
                elif predicted_sharpe > 0:
                    recommended_action = 'REDUCE_SIZE'
                    risk_multiplier = 0.5
                else:
                    recommended_action = 'PAUSE'
                    risk_multiplier = 0.0

                # Store prediction
                cursor.execute("""
                    INSERT OR REPLACE INTO PredictedPerformance (
                        prediction_date, symbol, predicted_sharpe, predicted_winrate,
                        predicted_pnl, confidence_score, recommended_action,
                        recommended_risk_multiplier, model_version, features_used,
                        created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    date, symbol, predicted_sharpe, predicted_winrate,
                    predicted_pnl, confidence_score, recommended_action,
                    risk_multiplier, self.model_version, json.dumps(self.feature_names),
                    timestamp_now
                ))

                print(f"✅ Prediction for {symbol}: Sharpe={predicted_sharpe:.2f}, Action={recommended_action}")

            conn.commit()
            print(f"\n✅ Predictions generated for {len(symbols)} symbols")

        except Exception as e:
            print(f"❌ Error generating predictions: {e}")
            conn.rollback()
        finally:
            conn.close()

    # =========================================================================
    # EVALUATION
    # =========================================================================

    def evaluate_predictions(self, date: str = None):
        """
        Compare predictions vs actual performance.

        Args:
            date: Date to evaluate (defaults to yesterday)
        """
        if date is None:
            date = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')

        conn = self.get_connection()
        cursor = conn.cursor()

        try:
            # Get predictions with actuals
            df = pd.read_sql("""
                SELECT
                    pp.symbol,
                    pp.predicted_sharpe,
                    pp.predicted_winrate,
                    pp.predicted_pnl,
                    sp.sharpe_ratio as actual_sharpe,
                    sp.win_rate as actual_winrate,
                    sp.total_pnl as actual_pnl
                FROM PredictedPerformance pp
                LEFT JOIN SymbolPerformance sp
                    ON pp.symbol = sp.symbol AND pp.prediction_date = sp.date
                WHERE pp.prediction_date = ?
                AND sp.sharpe_ratio IS NOT NULL
            """, conn, params=(date,))

            if df.empty:
                print(f"No predictions to evaluate for {date}")
                return None

            # Calculate errors
            df['sharpe_error'] = abs(df['predicted_sharpe'] - df['actual_sharpe'])
            df['winrate_error'] = abs(df['predicted_winrate'] - df['actual_winrate'])
            df['pnl_error'] = abs(df['predicted_pnl'] - df['actual_pnl'])

            # Update predictions table with actuals
            for _, row in df.iterrows():
                cursor.execute("""
                    UPDATE PredictedPerformance
                    SET actual_sharpe = ?,
                        actual_winrate = ?,
                        actual_pnl = ?,
                        prediction_error = ?
                    WHERE prediction_date = ? AND symbol = ?
                """, (
                    row['actual_sharpe'], row['actual_winrate'], row['actual_pnl'],
                    row['sharpe_error'], date, row['symbol']
                ))

            conn.commit()

            # Summary metrics
            metrics = {
                'date': date,
                'n_predictions': len(df),
                'mean_sharpe_error': df['sharpe_error'].mean(),
                'mean_winrate_error': df['winrate_error'].mean(),
                'mean_pnl_error': df['pnl_error'].mean(),
                'sharpe_correlation': df[['predicted_sharpe', 'actual_sharpe']].corr().iloc[0, 1]
            }

            print(f"\n📊 Prediction Evaluation for {date}")
            print(f"Predictions evaluated: {len(df)}")
            print(f"Mean Sharpe error: {metrics['mean_sharpe_error']:.3f}")
            print(f"Mean Win Rate error: {metrics['mean_winrate_error']:.1f}%")
            print(f"Sharpe correlation: {metrics['sharpe_correlation']:.3f}")

            return metrics

        except Exception as e:
            print(f"❌ Error evaluating predictions: {e}")
            return None
        finally:
            conn.close()

    # =========================================================================
    # MODEL PERSISTENCE
    # =========================================================================

    def save_model(self, filepath: str = "ml_model.pkl"):
        """Save trained model to disk"""
        if self.model is None:
            print("❌ No model to save")
            return False

        try:
            with open(filepath, 'wb') as f:
                pickle.dump({
                    'model': self.model,
                    'scaler': self.scaler,
                    'feature_names': self.feature_names,
                    'model_version': self.model_version
                }, f)

            print(f"✅ Model saved to {filepath}")
            return True

        except Exception as e:
            print(f"❌ Error saving model: {e}")
            return False

    def load_model(self, filepath: str = "ml_model.pkl"):
        """Load trained model from disk"""
        if not os.path.exists(filepath):
            print(f"❌ Model file not found: {filepath}")
            return False

        try:
            with open(filepath, 'rb') as f:
                data = pickle.load(f)
                self.model = data['model']
                self.scaler = data['scaler']
                self.feature_names = data['feature_names']
                self.model_version = data['model_version']

            print(f"✅ Model loaded from {filepath}")
            return True

        except Exception as e:
            print(f"❌ Error loading model: {e}")
            return False


# Test/Demo
if __name__ == "__main__":
    import os

    print("=" * 70)
    print("ML PREDICTOR - TEST RUN")
    print("=" * 70)

    db_path = os.getenv("DB_PATH", "PortfolioGovernor.sqlite")
    predictor = MLPredictor(db_path)

    # Step 1: Capture market conditions
    print("\n1️⃣ Capturing market conditions...")
    conn = predictor.get_connection()
    symbols = pd.read_sql("SELECT DISTINCT symbol FROM SymbolConfigs LIMIT 3", conn)['symbol'].tolist()
    conn.close()

    for symbol in symbols:
        predictor.capture_market_conditions(symbol)

    # Step 2: Train model
    print("\n2️⃣ Training ML model...")
    metrics = predictor.train_model(n_estimators=50)

    if metrics:
        # Step 3: Generate predictions
        print("\n3️⃣ Generating predictions...")
        predictor.generate_predictions()

        # Step 4: Evaluate previous predictions
        print("\n4️⃣ Evaluating previous predictions...")
        predictor.evaluate_predictions()

        # Step 5: Save model
        print("\n5️⃣ Saving model...")
        predictor.save_model("ml_model.pkl")

    print("\n✅ ML Predictor test complete!")
