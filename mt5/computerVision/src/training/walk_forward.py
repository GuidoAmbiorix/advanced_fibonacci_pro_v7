"""
Walk-Forward Validation for Time Series Models

Validates model performance across multiple time windows to ensure
robustness and detect overfitting to specific market conditions.
"""

import pandas as pd
import numpy as np
from typing import List, Dict, Tuple
from datetime import datetime


class WalkForwardValidator:
    """
    Implements Walk-Forward Validation for trading strategies.

    Splits data into N windows:
    - Train on window 1-K, test on window K+1
    - Train on window 2-(K+1), test on window K+2
    - etc.

    This simulates real trading where model is periodically retrained
    on recent data and tested on future unseen data.
    """

    def __init__(
        self,
        train_window_bars: int = 2000,
        test_window_bars: int = 500,
        n_splits: int = 5
    ):
        """
        Args:
            train_window_bars: Number of bars for training window
            test_window_bars: Number of bars for testing window
            n_splits: Number of walk-forward splits to perform
        """
        self.train_window_bars = train_window_bars
        self.test_window_bars = test_window_bars
        self.n_splits = n_splits

    def split(self, df: pd.DataFrame) -> List[Tuple[pd.DataFrame, pd.DataFrame]]:
        """
        Generate train/test splits for walk-forward validation.

        Args:
            df: Full dataset (must have at least train_window + n_splits * test_window bars)

        Returns:
            List of (train_df, test_df) tuples
        """
        min_required = self.train_window_bars + (self.n_splits * self.test_window_bars)

        if len(df) < min_required:
            raise ValueError(
                f"Insufficient data: need {min_required} bars, have {len(df)} bars. "
                f"Reduce n_splits or window sizes."
            )

        splits = []

        for i in range(self.n_splits):
            # Calculate indices
            test_start = self.train_window_bars + (i * self.test_window_bars)
            test_end = test_start + self.test_window_bars

            # Train on all data up to test start
            train_df = df.iloc[:test_start].copy()

            # Test on next window
            test_df = df.iloc[test_start:test_end].copy()

            splits.append((train_df, test_df))

            print(f"   Split {i+1}: Train={len(train_df)} bars, Test={len(test_df)} bars")

        return splits

    def validate(
        self,
        df: pd.DataFrame,
        trainer,
        optimizer,
        symbol: str,
        timeframe: str,
        n_trials: int = 20
    ) -> Dict:
        """
        Run walk-forward validation.

        Args:
            df: Full dataset
            trainer: EnsembleTrainer instance
            optimizer: EnsembleOptimizer instance
            symbol: Trading symbol
            timeframe: Timeframe
            n_trials: Number of optimization trials per split

        Returns:
            Dictionary with validation results
        """
        print(f"\n{'='*60}")
        print(f"🔄 Walk-Forward Validation: {self.n_splits} splits")
        print(f"{'='*60}")

        splits = self.split(df)
        results = []

        for i, (train_df, test_df) in enumerate(splits):
            print(f"\n{'='*60}")
            print(f"📊 Split {i+1}/{self.n_splits}")
            print(f"{'='*60}")

            # Optimize on training window
            print(f"🔍 Optimizing on training data...")
            best_params = optimizer.optimize(
                symbol=symbol,
                timeframe=timeframe,
                n_trials=n_trials,
                voting='soft',
                df=train_df  # Use only training window
            )

            # Test on test window
            print(f"\n🧪 Testing on unseen data...")
            ensemble, metrics = trainer.train_ensemble(
                symbol=symbol,
                timeframe=timeframe,
                df=train_df,  # Train on training window
                **best_params  # Use optimized params
            )

            # Backtest on test window
            from src.training.vectorbt_engine import VectorBTEngine
            engine = VectorBTEngine()

            # Prepare test features
            from src.features.feature_engineering import prepare_training_data
            X_test, y_test, feature_names, test_aligned_df = prepare_training_data(
                test_df, use_talib=True
            )

            # Generate predictions
            probs = ensemble.predict_proba(X_test)
            threshold = best_params.get('threshold', 0.65)

            entries = probs[:, 1] > threshold
            exits = probs[:, 1] < (1 - threshold)

            # Shift signals (1-bar delay)
            entries = np.concatenate([[False], entries[:-1]])
            exits = np.concatenate([[False], exits[:-1]])

            # Run backtest
            price_test = test_aligned_df['close']
            atr_test = test_aligned_df['ATR']

            sl = (atr_test.mean() * 3.5) / price_test.mean()
            tp = (atr_test.mean() * 3.5 * 2.5) / price_test.mean()
            sl = min(sl, 0.08)
            tp = min(tp, 0.25)

            stats = engine.backtest_strategy(
                prices=price_test.reset_index(drop=True),
                entries=pd.Series(entries).reset_index(drop=True),
                exits=pd.Series(exits).reset_index(drop=True),
                sl_stop=sl,
                tp_stop=tp,
                fees=0.001
            )

            result = {
                'split': i + 1,
                'train_size': len(train_df),
                'test_size': len(test_df),
                'accuracy': metrics.get('test_accuracy', 0),
                'profit_factor': stats.get('profit_factor', 0),
                'win_rate': stats.get('win_rate', 0),
                'total_trades': stats.get('total_trades', 0),
                'best_params': best_params
            }

            results.append(result)

            print(f"\n✅ Split {i+1} Results:")
            print(f"   Accuracy: {result['accuracy']:.2%}")
            print(f"   Profit Factor: {result['profit_factor']:.2f}")
            print(f"   Win Rate: {result['win_rate']:.2%}")
            print(f"   Total Trades: {result['total_trades']}")

        # Aggregate results
        print(f"\n{'='*60}")
        print(f"📈 Walk-Forward Summary")
        print(f"{'='*60}")

        pf_values = [r['profit_factor'] for r in results]
        wr_values = [r['win_rate'] for r in results]
        acc_values = [r['accuracy'] for r in results]

        summary = {
            'n_splits': self.n_splits,
            'mean_profit_factor': np.mean(pf_values),
            'std_profit_factor': np.std(pf_values),
            'mean_win_rate': np.mean(wr_values),
            'std_win_rate': np.std(wr_values),
            'mean_accuracy': np.mean(acc_values),
            'std_accuracy': np.std(acc_values),
            'all_splits': results
        }

        print(f"Profit Factor: {summary['mean_profit_factor']:.2f} ± {summary['std_profit_factor']:.2f}")
        print(f"Win Rate: {summary['mean_win_rate']:.1%} ± {summary['std_win_rate']:.1%}")
        print(f"Accuracy: {summary['mean_accuracy']:.1%} ± {summary['std_accuracy']:.1%}")

        # Stability check
        if summary['std_profit_factor'] > 0.3:
            print("\n⚠️  WARNING: High PF variance suggests overfitting or market regime sensitivity")
        else:
            print("\n✅ Good PF stability across time periods")

        return summary


def run_walk_forward_validation(
    symbol: str = 'EURUSD',
    timeframe: str = 'H1',
    train_window: int = 2000,
    test_window: int = 500,
    n_splits: int = 5,
    n_trials_per_split: int = 20
) -> Dict:
    """
    Convenience function to run walk-forward validation.

    Args:
        symbol: Trading symbol
        timeframe: Timeframe
        train_window: Training window size in bars
        test_window: Test window size in bars
        n_splits: Number of walk-forward splits
        n_trials_per_split: Optimization trials per split

    Returns:
        Validation results dictionary
    """
    from src.database.db_manager import DatabaseManager
    from src.training.ensemble_trainer import EnsembleTrainer
    from src.training.ensemble_optimizer import EnsembleOptimizer

    # Fetch all available data
    db = DatabaseManager()
    min_required = train_window + (n_splits * test_window)

    print(f"📥 Fetching {min_required} bars for walk-forward validation...")
    query = """
        SELECT * FROM market_data
        WHERE symbol = %s AND timeframe = %s
        ORDER BY timestamp DESC
        LIMIT %s
    """

    with db.get_connection() as conn:
        cursor = conn.execute(query, (symbol, timeframe, min_required))
        rows = cursor.fetchall()
        df = pd.DataFrame(rows)

    if len(df) < min_required:
        raise ValueError(f"Insufficient data: need {min_required}, have {len(df)}")

    # Reverse to chronological order
    df = df.iloc[::-1].reset_index(drop=True)

    # Run validation
    validator = WalkForwardValidator(
        train_window_bars=train_window,
        test_window_bars=test_window,
        n_splits=n_splits
    )

    trainer = EnsembleTrainer(db)
    optimizer = EnsembleOptimizer(trainer, db)

    results = validator.validate(
        df=df,
        trainer=trainer,
        optimizer=optimizer,
        symbol=symbol,
        timeframe=timeframe,
        n_trials=n_trials_per_split
    )

    return results


if __name__ == '__main__':
    # Example usage
    results = run_walk_forward_validation(
        symbol='EURUSD',
        timeframe='H1',
        train_window=2000,
        test_window=500,
        n_splits=3,  # Start with 3 for faster testing
        n_trials_per_split=15
    )

    print(f"\n{'='*60}")
    print(f"✅ Walk-Forward Validation Complete")
    print(f"{'='*60}")
    print(f"Mean PF: {results['mean_profit_factor']:.2f}")
    print(f"PF Stability (std): {results['std_profit_factor']:.2f}")
