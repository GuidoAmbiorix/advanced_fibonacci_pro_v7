"""
============================================================================
Model Training Script
============================================================================
Trains the AI signal quality predictor using historical trade data
"""

import sys
import os
from pathlib import Path
import pandas as pd
import numpy as np
from datetime import datetime, time as dt_time
from loguru import logger

# Add parent directory to path
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))

from app.ml.signal_predictor import SignalQualityPredictor
from app.models.database import Trade, Signal, BotConfig
from app.api.database import SessionLocal, engine
from sqlalchemy import text


def prepare_training_data() -> pd.DataFrame:
    """
    Prepare training data from historical trades and signals

    Returns:
        DataFrame with features and target (profitable=1/0)
    """
    logger.info("=" * 70)
    logger.info("Preparing training data from database")
    logger.info("=" * 70)

    db = SessionLocal()
    training_data = []

    try:
        # Get all signals
        signals = db.query(Signal).all()
        logger.info("Found {} total signals", len(signals))

        # For each signal, check if it was executed and profitable
        for signal in signals:
            # Find corresponding trade (if executed)
            trade = None
            if signal.trade_id:
                trade = db.query(Trade).filter(Trade.id == signal.trade_id).first()
            else:
                # Try to match by symbol, type, and time (within 5 minutes)
                trades = db.query(Trade).filter(
                    Trade.symbol == signal.symbol,
                    Trade.trade_type == signal.signal_type,
                    Trade.opened_at >= signal.created_at,
                    Trade.opened_at <= signal.created_at + pd.Timedelta(minutes=5)
                ).all()

                if trades:
                    trade = trades[0]

            # Determine if signal was profitable
            profitable = 0
            if trade and trade.status == 'CLOSED':
                profitable = 1 if (trade.profit_loss or 0) > 0 else 0
            elif not trade:
                # Signal wasn't executed - could mean it was skipped (bad signal)
                # For training, we'll exclude these for now
                continue

            # Extract features
            features = extract_signal_features(signal, trade)
            features['profitable'] = profitable

            training_data.append(features)

        logger.info("Prepared {} training samples", len(training_data))

        if len(training_data) < 20:
            logger.warning("Not enough training data! Need at least 20 samples.")
            logger.warning("Current: {} samples", len(training_data))
            logger.warning("Continue trading to collect more data, then retrain.")

            # Generate synthetic data for initial training
            logger.info("Generating synthetic data for initial training...")
            training_data = generate_synthetic_data(100)

        df = pd.DataFrame(training_data)

        # Show class distribution
        if 'profitable' in df.columns:
            win_rate = df['profitable'].mean() * 100
            logger.info("Win rate in training data: {:.1f}%", win_rate)
            logger.info("Profitable: {}, Unprofitable: {}",
                       df['profitable'].sum(),
                       len(df) - df['profitable'].sum())

        return df

    except Exception as e:
        logger.exception("Error preparing training data: {}", e)
        return pd.DataFrame()
    finally:
        db.close()


def extract_signal_features(signal: Signal, trade: Trade = None) -> dict:
    """Extract features from signal for training"""
    features = {}

    # Signal features
    features['confluence_score'] = signal.confluence_score
    features['signal_type'] = 1 if signal.signal_type == 'BUY' else 0

    # Score breakdown
    breakdown = signal.score_breakdown or {}
    features['trend_score'] = breakdown.get('Trend', 0)
    features['structure_score'] = breakdown.get('Structure', 0)
    features['ob_score'] = breakdown.get('Order Block', 0)
    features['fvg_score'] = breakdown.get('FVG', 0)
    features['liquidity_score'] = breakdown.get('Liquidity', 0)
    features['volume_score'] = breakdown.get('Volume', 0)

    # Market context
    features['current_price'] = signal.price
    features['atr'] = abs(signal.stop_loss - signal.price) / 1.5  # Approximate ATR

    # Higher timeframe (if available)
    features['htf_bullish'] = 1 if signal.trend == 'BULLISH' else 0
    features['htf_bearish'] = 1 if signal.trend == 'BEARISH' else 0

    # Volume profile
    features['near_poc'] = 1 if signal.poc_level and abs(signal.price - signal.poc_level) < features['atr'] else 0
    features['in_value_area'] = 0  # Would need VAH/VAL data
    features['premium_zone'] = 1 if signal.zone == 'PREMIUM' else 0
    features['discount_zone'] = 1 if signal.zone == 'DISCOUNT' else 0

    # Time-based
    signal_time = signal.created_at.time() if signal.created_at else datetime.utcnow().time()
    features['hour'] = signal_time.hour
    features['is_london_session'] = 1 if dt_time(8, 0) <= signal_time <= dt_time(17, 0) else 0
    features['is_ny_session'] = 1 if dt_time(13, 0) <= signal_time <= dt_time(22, 0) else 0
    features['is_overlap'] = 1 if dt_time(13, 0) <= signal_time <= dt_time(17, 0) else 0

    # Risk/Reward
    entry = signal.price
    sl = signal.stop_loss
    tp = signal.take_profit

    if entry and sl and tp:
        risk = abs(entry - sl)
        reward = abs(tp - entry)
        features['risk_reward'] = reward / risk if risk > 0 else 0
    else:
        features['risk_reward'] = 0

    # Placeholder features (would be calculated from full market data)
    features['volatility_percentile'] = 50
    features['active_obs'] = 2
    features['active_fvgs'] = 1

    return features


def generate_synthetic_data(n_samples: int = 100) -> list:
    """
    Generate synthetic training data for initial model training
    Based on trading logic assumptions
    """
    logger.info("Generating {} synthetic training samples", n_samples)

    np.random.seed(42)
    data = []

    for _ in range(n_samples):
        # Generate random features
        confluence = np.random.randint(4, 11)
        signal_type = np.random.choice([0, 1])

        # Trend alignment increases win probability
        htf_bullish = np.random.choice([0, 1])
        htf_bearish = 1 - htf_bullish

        # Higher confluence = higher win rate
        base_win_prob = 0.3 + (confluence / 10.0) * 0.4  # 30-70% based on confluence

        # HTF alignment bonus
        if (signal_type == 1 and htf_bullish) or (signal_type == 0 and htf_bearish):
            base_win_prob += 0.15

        # Session bonus (London/NY)
        is_london = np.random.choice([0, 1], p=[0.7, 0.3])
        is_ny = np.random.choice([0, 1], p=[0.7, 0.3])
        if is_london or is_ny:
            base_win_prob += 0.05

        # Zone bonus (buy in discount, sell in premium)
        discount_zone = np.random.choice([0, 1])
        premium_zone = 1 - discount_zone
        if (signal_type == 1 and discount_zone) or (signal_type == 0 and premium_zone):
            base_win_prob += 0.1

        # Determine outcome
        profitable = 1 if np.random.random() < base_win_prob else 0

        sample = {
            'confluence_score': confluence,
            'signal_type': signal_type,
            'trend_score': np.random.randint(0, 3),
            'structure_score': np.random.randint(0, 2),
            'ob_score': np.random.randint(0, 2),
            'fvg_score': np.random.randint(0, 2),
            'liquidity_score': np.random.randint(0, 2),
            'volume_score': np.random.randint(0, 2),
            'current_price': 1.1000 + np.random.random() * 0.01,
            'atr': 0.0010 + np.random.random() * 0.0005,
            'volatility_percentile': np.random.randint(20, 80),
            'htf_bullish': htf_bullish,
            'htf_bearish': htf_bearish,
            'near_poc': np.random.choice([0, 1]),
            'in_value_area': np.random.choice([0, 1]),
            'premium_zone': premium_zone,
            'discount_zone': discount_zone,
            'hour': np.random.randint(0, 24),
            'is_london_session': is_london,
            'is_ny_session': is_ny,
            'is_overlap': is_london and is_ny,
            'risk_reward': 2.0 + np.random.random() * 2.0,
            'active_obs': np.random.randint(0, 5),
            'active_fvgs': np.random.randint(0, 3),
            'profitable': profitable
        }

        data.append(sample)

    win_rate = sum(s['profitable'] for s in data) / len(data) * 100
    logger.info("Synthetic data win rate: {:.1f}%", win_rate)

    return data


def main():
    """Main training function"""
    logger.info("=" * 70)
    logger.info("AI Signal Quality Predictor - Model Training")
    logger.info("=" * 70)

    # Prepare data
    df = prepare_training_data()

    if df.empty or len(df) < 10:
        logger.error("Insufficient training data. Cannot train model.")
        return False

    # Initialize predictor
    predictor = SignalQualityPredictor()

    # Train model
    logger.info("\nTraining XGBoost model...")
    success = predictor.train(df, target_column='profitable')

    if not success:
        logger.error("Model training failed")
        return False

    # Save model
    model_dir = Path(__file__).parent / 'models'
    model_dir.mkdir(exist_ok=True)
    model_path = model_dir / 'signal_predictor.pkl'

    predictor.save_model(str(model_path))

    logger.info("\n" + "=" * 70)
    logger.info("✅ Model training complete!")
    logger.info("Model saved to: {}", model_path)
    logger.info("=" * 70)

    return True


if __name__ == "__main__":
    main()
