"""
============================================================================
AI Signal Quality Predictor
============================================================================
Uses XGBoost to predict the probability of a trading signal being profitable
"""

import numpy as np
import pandas as pd
import pickle
import os
from typing import Dict, Optional, Tuple
from datetime import datetime, time as dt_time
from pathlib import Path
from loguru import logger

try:
    import xgboost as xgb
    XGBOOST_AVAILABLE = True
except ImportError:
    XGBOOST_AVAILABLE = False
    logger.warning("XGBoost not installed. AI predictions will be disabled.")


class SignalQualityPredictor:
    """
    ML model that predicts signal success probability
    """

    def __init__(self, model_path: Optional[str] = None):
        """
        Initialize the predictor

        Args:
            model_path: Path to saved model file
        """
        self.model = None
        self.feature_names = None
        self.is_trained = False

        if model_path and os.path.exists(model_path):
            self.load_model(model_path)

        logger.info("Signal Quality Predictor initialized (Trained: {})", self.is_trained)

    def extract_features(self, signal_data: Dict, market_data: Dict) -> pd.DataFrame:
        """
        Extract features from signal and market data for prediction

        Args:
            signal_data: Dictionary with signal information
            market_data: Dictionary with market context

        Returns:
            DataFrame with feature row
        """
        features = {}

        # Signal features
        features['confluence_score'] = signal_data.get('confluence_score', 0)
        features['signal_type'] = 1 if signal_data.get('signal_type') == 'BUY' else 0

        # Score breakdown features
        breakdown = signal_data.get('score_breakdown', {})
        features['trend_score'] = breakdown.get('Trend', 0)
        features['structure_score'] = breakdown.get('Structure', 0)
        features['ob_score'] = breakdown.get('Order Block', 0)
        features['fvg_score'] = breakdown.get('FVG', 0)
        features['liquidity_score'] = breakdown.get('Liquidity', 0)
        features['volume_score'] = breakdown.get('Volume', 0)

        # Market context features
        features['current_price'] = market_data.get('current_price', 0)
        features['atr'] = market_data.get('atr', 0)
        features['volatility_percentile'] = market_data.get('volatility_percentile', 50)

        # Higher timeframe
        htf_trend = market_data.get('higher_tf_trend', 'NEUTRAL')
        features['htf_bullish'] = 1 if htf_trend == 'BULLISH' else 0
        features['htf_bearish'] = 1 if htf_trend == 'BEARISH' else 0

        # Volume profile
        features['near_poc'] = 1 if market_data.get('near_poc', False) else 0
        features['in_value_area'] = 1 if market_data.get('in_value_area', False) else 0
        features['premium_zone'] = 1 if market_data.get('zone') == 'PREMIUM' else 0
        features['discount_zone'] = 1 if market_data.get('zone') == 'DISCOUNT' else 0

        # Time-based features
        current_time = datetime.utcnow().time()
        features['hour'] = current_time.hour
        features['is_london_session'] = 1 if dt_time(8, 0) <= current_time <= dt_time(17, 0) else 0
        features['is_ny_session'] = 1 if dt_time(13, 0) <= current_time <= dt_time(22, 0) else 0
        features['is_overlap'] = 1 if dt_time(13, 0) <= current_time <= dt_time(17, 0) else 0

        # Risk/Reward
        entry = signal_data.get('entry_price', 0)
        sl = signal_data.get('stop_loss', 0)
        tp = signal_data.get('take_profit_1', 0)

        if entry > 0 and sl > 0 and tp > 0:
            risk = abs(entry - sl)
            reward = abs(tp - entry)
            features['risk_reward'] = reward / risk if risk > 0 else 0
        else:
            features['risk_reward'] = 0

        # Active structures
        features['active_obs'] = market_data.get('active_order_blocks', 0)
        features['active_fvgs'] = market_data.get('active_fvgs', 0)

        return pd.DataFrame([features])

    def predict(self, signal_data: Dict, market_data: Dict) -> Tuple[float, str]:
        """
        Predict signal quality

        Args:
            signal_data: Signal information
            market_data: Market context

        Returns:
            Tuple of (confidence score 0-100, recommendation)
        """
        if not XGBOOST_AVAILABLE or not self.is_trained:
            # Fallback: use confluence score as confidence
            confluence = signal_data.get('confluence_score', 0)
            confidence = confluence * 10.0  # Convert 0-10 to 0-100
            recommendation = self._get_recommendation(confidence)
            return confidence, recommendation

        try:
            # Extract features
            X = self.extract_features(signal_data, market_data)

            # Ensure feature order matches training
            if self.feature_names:
                X = X[self.feature_names]

            # Predict probability
            probability = self.model.predict_proba(X)[0][1]  # Probability of success
            confidence = probability * 100.0

            recommendation = self._get_recommendation(confidence)

            logger.info("AI Prediction - Confidence: {:.1f}%, Recommendation: {}",
                       confidence, recommendation)

            return confidence, recommendation

        except Exception as e:
            logger.error("Error in AI prediction: {}", e)
            # Fallback to confluence-based
            confluence = signal_data.get('confluence_score', 0)
            confidence = confluence * 10.0
            return confidence, "UNCERTAIN"

    def _get_recommendation(self, confidence: float) -> str:
        """
        Get trading recommendation based on confidence

        Args:
            confidence: AI confidence score (0-100)

        Returns:
            Recommendation string
        """
        if confidence >= 75:
            return "STRONG_TAKE"
        elif confidence >= 60:
            return "TAKE"
        elif confidence >= 45:
            return "CAUTIOUS"
        elif confidence >= 30:
            return "SKIP"
        else:
            return "STRONG_SKIP"

    def train(self, training_data: pd.DataFrame, target_column: str = 'profitable'):
        """
        Train the model on historical trade data

        Args:
            training_data: DataFrame with features and target
            target_column: Name of target column (1 = profitable, 0 = loss)
        """
        if not XGBOOST_AVAILABLE:
            logger.error("Cannot train: XGBoost not installed")
            return False

        try:
            # Separate features and target
            X = training_data.drop(columns=[target_column])
            y = training_data[target_column]

            # Store feature names for later
            self.feature_names = X.columns.tolist()

            logger.info("Training model with {} samples, {} features", len(X), len(X.columns))

            # Train XGBoost model
            self.model = xgb.XGBClassifier(
                n_estimators=100,
                max_depth=5,
                learning_rate=0.1,
                subsample=0.8,
                colsample_bytree=0.8,
                random_state=42,
                eval_metric='logloss'
            )

            self.model.fit(X, y)
            self.is_trained = True

            # Log feature importance
            importance = pd.DataFrame({
                'feature': self.feature_names,
                'importance': self.model.feature_importances_
            }).sort_values('importance', ascending=False)

            logger.info("Top 5 most important features:")
            for idx, row in importance.head(5).iterrows():
                logger.info("  {}: {:.3f}", row['feature'], row['importance'])

            return True

        except Exception as e:
            logger.exception("Error training model: {}", e)
            return False

    def save_model(self, filepath: str):
        """Save model to disk"""
        if not self.is_trained:
            logger.warning("Cannot save untrained model")
            return False

        try:
            model_data = {
                'model': self.model,
                'feature_names': self.feature_names,
                'trained_at': datetime.utcnow().isoformat()
            }

            with open(filepath, 'wb') as f:
                pickle.dump(model_data, f)

            logger.info("Model saved to {}", filepath)
            return True

        except Exception as e:
            logger.exception("Error saving model: {}", e)
            return False

    def load_model(self, filepath: str):
        """Load model from disk"""
        try:
            with open(filepath, 'rb') as f:
                model_data = pickle.load(f)

            self.model = model_data['model']
            self.feature_names = model_data['feature_names']
            self.is_trained = True

            logger.info("Model loaded from {} (trained at {})",
                       filepath, model_data.get('trained_at', 'unknown'))
            return True

        except Exception as e:
            logger.exception("Error loading model: {}", e)
            return False


# Global predictor instance
_predictor: Optional[SignalQualityPredictor] = None


def get_predictor(model_path: Optional[str] = None) -> SignalQualityPredictor:
    """Get or create global predictor instance"""
    global _predictor

    if _predictor is None:
        if model_path is None:
            # Default model path
            model_dir = Path(__file__).parent / 'models'
            model_dir.mkdir(exist_ok=True)
            model_path = str(model_dir / 'signal_predictor.pkl')

        _predictor = SignalQualityPredictor(model_path)

    return _predictor
