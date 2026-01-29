"""
V3 Trading System - HMM Regime Detection Service
Detects market regimes using Hidden Markov Models
"""

import asyncio
import json
import pickle
from datetime import datetime, timedelta
from typing import List, Dict, Optional, Tuple
import numpy as np
import pandas as pd
from hmmlearn import hmm
import redis.asyncio as redis
import structlog
import os

# Configure logging
log = structlog.get_logger()

# ==================== Configuration ====================

REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))
N_STATES = 8  # Number of market regimes

# Regime labels
REGIME_LABELS = [
    "REGIME_LOW_VOL_BULL",
    "REGIME_LOW_VOL_BEAR",
    "REGIME_HIGH_VOL_BULL",
    "REGIME_HIGH_VOL_BEAR",
    "REGIME_SIDEWAYS_TIGHT",
    "REGIME_SIDEWAYS_WIDE",
    "REGIME_BREAKOUT",
    "REGIME_CRISIS"
]

# ==================== Feature Extraction ====================

class MarketFeatures:
    """Extract features from price data for HMM"""

    @staticmethod
    def calculate_features(prices: pd.DataFrame) -> np.ndarray:
        """
        Calculate observation features for HMM
        Input: DataFrame with columns [open, high, low, close, volume]
        Output: numpy array of shape (n_samples, n_features)
        """
        features = []

        # 1. Log Returns
        returns = np.log(prices['close'] / prices['close'].shift(1))
        features.append(returns)

        # 2. Realized Volatility (20-period rolling std)
        volatility = returns.rolling(20).std()
        features.append(volatility)

        # 3. Normalized Volume
        vol_ma = prices['volume'].rolling(20).mean()
        norm_volume = prices['volume'] / vol_ma
        features.append(norm_volume)

        # 4. Bid-Ask Spread Proxy (high-low range)
        spread = (prices['high'] - prices['low']) / prices['close']
        features.append(spread)

        # 5. Momentum (RSI-like)
        delta = prices['close'].diff()
        gain = delta.where(delta > 0, 0).rolling(14).mean()
        loss = -delta.where(delta < 0, 0).rolling(14).mean()
        rs = gain / loss
        momentum = 100 - (100 / (1 + rs))
        features.append(momentum)

        # Combine features
        feature_array = np.column_stack(features)

        # Remove NaN rows
        feature_array = feature_array[~np.isnan(feature_array).any(axis=1)]

        return feature_array

    @staticmethod
    def normalize_features(features: np.ndarray) -> np.ndarray:
        """Z-score normalization"""
        mean = np.mean(features, axis=0)
        std = np.std(features, axis=0)
        return (features - mean) / (std + 1e-8)

# ==================== HMM Regime Detector ====================

class HMMRegimeDetector:
    """Hidden Markov Model for regime detection"""

    def __init__(self, n_states: int = 8):
        self.n_states = n_states
        self.model = None
        self.feature_mean = None
        self.feature_std = None

    def train(self, observations: np.ndarray, n_iter: int = 100) -> None:
        """
        Train HMM on historical observations
        observations: (n_samples, n_features)
        """
        log.info("hmm_training_start", n_samples=len(observations), n_states=self.n_states)

        # Normalize features
        self.feature_mean = np.mean(observations, axis=0)
        self.feature_std = np.std(observations, axis=0)
        normalized_obs = (observations - self.feature_mean) / (self.feature_std + 1e-8)

        # Initialize HMM
        self.model = hmm.GaussianHMM(
            n_components=self.n_states,
            covariance_type="full",
            n_iter=n_iter,
            random_state=42
        )

        # Fit model
        self.model.fit(normalized_obs)

        log.info("hmm_training_complete", converged=self.model.monitor_.converged)

    def predict(self, observations: np.ndarray) -> Tuple[int, np.ndarray]:
        """
        Predict current regime
        Returns: (most_likely_state, state_probabilities)
        """
        if self.model is None:
            raise ValueError("Model not trained")

        # Normalize
        normalized_obs = (observations - self.feature_mean) / (self.feature_std + 1e-8)

        # Get state probabilities
        log_prob, state_sequence = self.model.decode(normalized_obs, algorithm="viterbi")

        # Get current state (last observation)
        current_state = state_sequence[-1]

        # Get probabilities of being in each state (forward algorithm)
        posteriors = self.model.predict_proba(normalized_obs)
        current_probs = posteriors[-1]  # Probabilities for last observation

        return current_state, current_probs

    def save(self, filepath: str) -> None:
        """Save trained model to disk"""
        model_data = {
            "model": self.model,
            "feature_mean": self.feature_mean,
            "feature_std": self.feature_std,
            "n_states": self.n_states
        }
        with open(filepath, 'wb') as f:
            pickle.dump(model_data, f)
        log.info("hmm_model_saved", filepath=filepath)

    def load(self, filepath: str) -> None:
        """Load trained model from disk"""
        with open(filepath, 'rb') as f:
            model_data = pickle.load(f)
        self.model = model_data["model"]
        self.feature_mean = model_data["feature_mean"]
        self.feature_std = model_data["feature_std"]
        self.n_states = model_data["n_states"]
        log.info("hmm_model_loaded", filepath=filepath)

# ==================== Regime Service ====================

class RegimeService:
    """Main regime detection service"""

    def __init__(self):
        self.detectors: Dict[str, HMMRegimeDetector] = {}
        self.redis_client: Optional[redis.Redis] = None

    async def connect_redis(self):
        """Connect to Redis"""
        self.redis_client = await redis.from_url(
            f"redis://{REDIS_HOST}:{REDIS_PORT}",
            encoding="utf-8",
            decode_responses=True
        )
        await self.redis_client.ping()
        log.info("redis_connected", host=REDIS_HOST, port=REDIS_PORT)

    def initialize_detectors(self, symbols: List[str]):
        """Initialize HMM detectors for symbols"""
        for symbol in symbols:
            self.detectors[symbol] = HMMRegimeDetector(n_states=N_STATES)
            log.info("detector_initialized", symbol=symbol)

    async def fetch_historical_data(self, symbol: str, timeframe: str, bars: int = 1000) -> pd.DataFrame:
        """
        Fetch historical price data from Redis
        In production, would query PostgreSQL or external API
        """
        # Mock data for now (in production, fetch from database)
        log.warning("using_mock_data", symbol=symbol)

        dates = pd.date_range(end=datetime.now(), periods=bars, freq='H')
        np.random.seed(42)

        # Generate synthetic OHLCV data
        base_price = 1.0500 if "USD" in symbol else 1500.0 if "XAU" in symbol else 110.0

        close_prices = base_price + np.cumsum(np.random.randn(bars) * 0.0005)
        high_prices = close_prices + np.abs(np.random.randn(bars) * 0.0003)
        low_prices = close_prices - np.abs(np.random.randn(bars) * 0.0003)
        open_prices = close_prices + np.random.randn(bars) * 0.0002
        volumes = np.abs(np.random.randn(bars) * 1000 + 5000)

        df = pd.DataFrame({
            'timestamp': dates,
            'open': open_prices,
            'high': high_prices,
            'low': low_prices,
            'close': close_prices,
            'volume': volumes
        })

        return df

    async def train_detector(self, symbol: str, timeframe: str = "H1"):
        """Train HMM detector for symbol"""
        log.info("training_detector", symbol=symbol, timeframe=timeframe)

        # Fetch historical data
        df = await self.fetch_historical_data(symbol, timeframe, bars=2000)

        # Extract features
        features = MarketFeatures.calculate_features(df)

        # Train model
        detector = self.detectors[symbol]
        detector.train(features)

        # Save model
        model_path = f"/app/models/{symbol}_{timeframe}_hmm.pkl"
        os.makedirs("/app/models", exist_ok=True)
        detector.save(model_path)

        log.info("training_complete", symbol=symbol)

    async def detect_regime(self, symbol: str, timeframe: str = "H1") -> Dict:
        """
        Detect current market regime for symbol
        """
        if symbol not in self.detectors:
            log.error("detector_not_found", symbol=symbol)
            return self._default_regime(symbol)

        try:
            # Fetch recent data (last 100 bars)
            df = await self.fetch_historical_data(symbol, timeframe, bars=100)

            # Extract features
            features = MarketFeatures.calculate_features(df)

            # Predict regime
            detector = self.detectors[symbol]
            current_state, probabilities = detector.predict(features)

            # Map state to regime label
            regime_label = REGIME_LABELS[current_state]
            confidence = float(probabilities[current_state])

            # Create probabilities dict
            probs_dict = {
                label: float(prob) for label, prob in zip(REGIME_LABELS, probabilities)
            }

            result = {
                "symbol": symbol,
                "timeframe": timeframe,
                "regime": regime_label,
                "probabilities": probs_dict,
                "confidence": round(confidence, 4),
                "timestamp": datetime.utcnow().isoformat()
            }

            # Cache in Redis (4-hour TTL)
            cache_key = f"regime:{symbol}:{timeframe}"
            await self.redis_client.setex(
                cache_key,
                14400,
                json.dumps(result)
            )

            log.info("regime_detected", symbol=symbol, regime=regime_label, confidence=confidence)

            return result

        except Exception as e:
            log.error("regime_detection_failed", symbol=symbol, error=str(e))
            return self._default_regime(symbol)

    def _default_regime(self, symbol: str) -> Dict:
        """Default regime (fallback)"""
        return {
            "symbol": symbol,
            "regime": "REGIME_LOW_VOL_BULL",
            "probabilities": {label: 0.125 for label in REGIME_LABELS},
            "confidence": 0.0,
            "timestamp": datetime.utcnow().isoformat()
        }

    async def update_all_regimes(self):
        """Update regimes for all symbols (background task)"""
        symbols = list(self.detectors.keys())

        for symbol in symbols:
            try:
                await self.detect_regime(symbol, "H1")
            except Exception as e:
                log.error("regime_update_failed", symbol=symbol, error=str(e))

    async def run_periodic_updates(self):
        """Run regime updates every 4 hours"""
        while True:
            try:
                log.info("periodic_regime_update_start")
                await self.update_all_regimes()
                log.info("periodic_regime_update_complete")
            except Exception as e:
                log.error("periodic_regime_update_failed", error=str(e))

            # Wait 4 hours
            await asyncio.sleep(14400)

    async def heartbeat(self):
        """Send heartbeat to Redis"""
        while True:
            try:
                await self.redis_client.setex("heartbeat:hmm", 120, "alive")
            except Exception as e:
                log.error("heartbeat_failed", error=str(e))

            await asyncio.sleep(60)

# ==================== Main ====================

async def main():
    """Main entry point"""
    log.info("hmm_service_starting")

    service = RegimeService()
    await service.connect_redis()

    # Initialize detectors for common symbols
    symbols = ["EURUSD", "GBPUSD", "USDJPY", "USDCAD", "XAUUSD"]
    service.initialize_detectors(symbols)

    # Train models on startup
    for symbol in symbols:
        await service.train_detector(symbol)

    # Start background tasks
    tasks = [
        asyncio.create_task(service.run_periodic_updates()),
        asyncio.create_task(service.heartbeat())
    ]

    log.info("hmm_service_running")

    # Wait for tasks
    await asyncio.gather(*tasks)

if __name__ == "__main__":
    asyncio.run(main())
