"""
Sequence Generator for Time Series Models

Converts tabular market data into sequences for LSTM/CNN-LSTM models.
"""

import numpy as np
import pandas as pd
from typing import Tuple, List
from sklearn.model_selection import train_test_split


class SequenceGenerator:
    """
    Generate sequences from tabular data for time series models.
    """
    
    def __init__(self, sequence_length: int = 20):
        """
        Initialize sequence generator.
        
        Args:
            sequence_length: Number of time steps in each sequence
        """
        self.sequence_length = sequence_length
    
    def create_sequences(self, X: np.ndarray, y: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
        """
        Create sequences from feature matrix and labels.
        
        Args:
            X: Feature matrix (n_samples, n_features)
            y: Labels (n_samples,)
            
        Returns:
            (X_sequences, y_sequences)
            X_sequences: (n_sequences, sequence_length, n_features)
            y_sequences: (n_sequences,)
        """
        if len(X) < self.sequence_length:
            raise ValueError(f"Not enough data. Need at least {self.sequence_length} samples, got {len(X)}")
        
        sequences = []
        labels = []
        
        # Create sequences
        for i in range(self.sequence_length, len(X)):
            # Get sequence of features
            seq = X[i - self.sequence_length:i]
            sequences.append(seq)
            
            # Get label for the last time step
            labels.append(y[i])
        
        return np.array(sequences), np.array(labels)
    
    def create_sequences_from_dataframe(self, df: pd.DataFrame, 
                                       feature_columns: List[str],
                                       target_column: str) -> Tuple[np.ndarray, np.ndarray]:
        """
        Create sequences directly from DataFrame.
        
        Args:
            df: DataFrame with features and target
            feature_columns: List of feature column names
            target_column: Name of target column
            
        Returns:
            (X_sequences, y_sequences)
        """
        X = df[feature_columns].values
        y = df[target_column].values
        
        return self.create_sequences(X, y)
    
    def split_sequences(self, X_seq: np.ndarray, y_seq: np.ndarray,
                       test_size: float = 0.2,
                       val_size: float = 0.1,
                       shuffle: bool = False,
                       random_state: int = 42) -> Tuple:
        """
        Split sequences into train/val/test sets.
        
        Args:
            X_seq: Sequence features
            y_seq: Sequence labels
            test_size: Proportion for test set
            val_size: Proportion for validation set (from training data)
            shuffle: Whether to shuffle before splitting
            random_state: Random seed
            
        Returns:
            (X_train, X_val, X_test, y_train, y_val, y_test)
        """
        # First split: train+val vs test
        X_temp, X_test, y_temp, y_test = train_test_split(
            X_seq, y_seq,
            test_size=test_size,
            shuffle=shuffle,
            random_state=random_state
        )
        
        # Second split: train vs val
        val_size_adjusted = val_size / (1 - test_size)
        X_train, X_val, y_train, y_val = train_test_split(
            X_temp, y_temp,
            test_size=val_size_adjusted,
            shuffle=shuffle,
            random_state=random_state
        )
        
        return X_train, X_val, X_test, y_train, y_val, y_test
    
    def get_sequence_info(self, X_seq: np.ndarray) -> dict:
        """
        Get information about sequence shape.
        
        Args:
            X_seq: Sequence array
            
        Returns:
            Dictionary with sequence information
        """
        return {
            'n_sequences': X_seq.shape[0],
            'sequence_length': X_seq.shape[1],
            'n_features': X_seq.shape[2],
            'total_shape': X_seq.shape
        }


def prepare_sequences_for_training(X: np.ndarray, y: np.ndarray,
                                   sequence_length: int = 20,
                                   test_size: float = 0.2,
                                   val_size: float = 0.1,
                                   shuffle: bool = False,
                                   random_state: int = 42) -> Tuple:
    """
    One-step function to prepare sequences for training.
    
    Args:
        X: Feature matrix (n_samples, n_features)
        y: Labels (n_samples,)
        sequence_length: Number of time steps
        test_size: Test set proportion
        val_size: Validation set proportion
        shuffle: Whether to shuffle
        random_state: Random seed
        
    Returns:
        (X_train, X_val, X_test, y_train, y_val, y_test, info)
    """
    print(f"📊 Preparing sequences...")
    print(f"   Input shape: {X.shape}")
    print(f"   Sequence length: {sequence_length}")
    
    # Create generator
    generator = SequenceGenerator(sequence_length=sequence_length)
    
    # Create sequences
    X_seq, y_seq = generator.create_sequences(X, y)
    
    print(f"   Sequences created: {X_seq.shape}")
    print(f"   Samples lost: {len(X) - len(X_seq)} (used for sequence history)")
    
    # Split sequences
    X_train, X_val, X_test, y_train, y_val, y_test = generator.split_sequences(
        X_seq, y_seq,
        test_size=test_size,
        val_size=val_size,
        shuffle=shuffle,
        random_state=random_state
    )
    
    # Get info
    info = {
        'sequence_length': sequence_length,
        'n_features': X_seq.shape[2],
        'train_samples': len(X_train),
        'val_samples': len(X_val),
        'test_samples': len(X_test),
        'total_sequences': len(X_seq),
        'original_samples': len(X),
        'samples_lost': len(X) - len(X_seq)
    }
    
    print(f"\n✅ Sequence preparation complete:")
    print(f"   Train: {len(X_train)} sequences")
    print(f"   Val:   {len(X_val)} sequences")
    print(f"   Test:  {len(X_test)} sequences")
    
    return X_train, X_val, X_test, y_train, y_val, y_test, info


if __name__ == '__main__':
    # Test sequence generation
    print("Testing SequenceGenerator...")
    
    # Create dummy data
    n_samples = 1000
    n_features = 150
    X_dummy = np.random.randn(n_samples, n_features)
    y_dummy = np.random.randint(0, 2, n_samples)
    
    # Test sequence creation
    X_train, X_val, X_test, y_train, y_val, y_test, info = prepare_sequences_for_training(
        X_dummy, y_dummy,
        sequence_length=20,
        test_size=0.2,
        val_size=0.1
    )
    
    print(f"\n📊 Final shapes:")
    print(f"   X_train: {X_train.shape}")
    print(f"   X_val: {X_val.shape}")
    print(f"   X_test: {X_test.shape}")
    print(f"\n✅ SequenceGenerator test passed!")
