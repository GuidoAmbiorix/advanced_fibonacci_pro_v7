"""
TensorFlow/Keras Model Architectures for Trading

Implements LSTM, CNN-LSTM, and Transformer models with attention mechanisms.
"""

import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers, Model, regularizers
from tensorflow.keras.callbacks import EarlyStopping, ReduceLROnPlateau, ModelCheckpoint, TensorBoard
from typing import Tuple, List, Dict
import numpy as np


@keras.utils.register_keras_serializable(package="CustomLayers")
class AttentionLayer(layers.Layer):
    """
    Custom attention layer for focusing on important time steps.
    """

    def __init__(self, **kwargs):
        super(AttentionLayer, self).__init__(**kwargs)
    
    def build(self, input_shape):
        self.W = self.add_weight(
            name='attention_weight',
            shape=(input_shape[-1], input_shape[-1]),
            initializer='glorot_uniform',
            trainable=True
        )
        self.b = self.add_weight(
            name='attention_bias',
            shape=(input_shape[-1],),
            initializer='zeros',
            trainable=True
        )
        super(AttentionLayer, self).build(input_shape)
    
    def call(self, inputs):
        # Calculate attention scores
        score = tf.nn.tanh(tf.tensordot(inputs, self.W, axes=1) + self.b)
        attention_weights = tf.nn.softmax(score, axis=1)
        
        # Apply attention weights
        context_vector = attention_weights * inputs
        context_vector = tf.reduce_sum(context_vector, axis=1)
        
        return context_vector
    
    def compute_output_shape(self, input_shape):
        return (input_shape[0], input_shape[-1])

    def get_config(self):
        """Get layer configuration for serialization."""
        config = super(AttentionLayer, self).get_config()
        return config


def build_lstm_model(sequence_length: int,
                     n_features: int,
                     lstm_units: List[int] = [64, 32],  # Phase 3.4: Reduced from [128, 64]
                     dense_units: List[int] = [16],     # Phase 3.4: Reduced from [32, 16]
                     dropout_rate: float = 0.4,         # Phase 3.4: Increased from 0.3
                     use_attention: bool = True,
                     learning_rate: float = 0.001) -> Model:
    """
    Build LSTM model with optional attention mechanism.
    
    Args:
        sequence_length: Number of time steps
        n_features: Number of features per time step
        lstm_units: List of LSTM layer units
        dense_units: List of dense layer units
        dropout_rate: Dropout rate for regularization
        use_attention: Whether to use attention mechanism
        learning_rate: Learning rate for optimizer
        
    Returns:
        Compiled Keras model
    """
    inputs = layers.Input(shape=(sequence_length, n_features), name='input')
    x = inputs

    # Layer Normalization before LSTM (stabilizes gradients)
    x = layers.LayerNormalization(name='layer_norm_input')(x)

    # LSTM layers with L2 regularization (Phase 3.4)
    for i, units in enumerate(lstm_units):
        return_sequences = (i < len(lstm_units) - 1) or use_attention
        x = layers.LSTM(
            units,
            return_sequences=return_sequences,
            kernel_regularizer=regularizers.l2(0.01),
            recurrent_regularizer=regularizers.l2(0.01),
            name=f'lstm_{i+1}'
        )(x)
        x = layers.BatchNormalization(name=f'bn_lstm_{i+1}')(x)
        x = layers.Dropout(dropout_rate, name=f'dropout_lstm_{i+1}')(x)
    
    # Attention layer
    if use_attention:
        x = AttentionLayer(name='attention')(x)
    
    # Dense layers
    for i, units in enumerate(dense_units):
        x = layers.Dense(units, activation='relu', name=f'dense_{i+1}')(x)
        x = layers.Dropout(dropout_rate * 0.5, name=f'dropout_dense_{i+1}')(x)
    
    # Output layer
    outputs = layers.Dense(2, activation='softmax', name='output')(x)
    
    # Create model
    model = Model(inputs=inputs, outputs=outputs, name='LSTM_Model')
    
    # Compile
    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=learning_rate),
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy']
    )
    
    return model


def build_cnn_lstm_model(sequence_length: int,
                         n_features: int,
                         cnn_filters: List[int] = [64, 32],
                         kernel_size: int = 3,
                         pool_size: int = 2,
                         lstm_units: List[int] = [64, 32],  # Phase 3.4: Reduced from [128, 64]
                         dense_units: List[int] = [16],     # Phase 3.4: Reduced from [32]
                         dropout_rate: float = 0.4,         # Phase 3.4: Increased from 0.3
                         use_attention: bool = True,
                         learning_rate: float = 0.001) -> Model:
    """
    Build CNN-LSTM hybrid model.
    
    CNN extracts local patterns, LSTM captures temporal dependencies.
    
    Args:
        sequence_length: Number of time steps
        n_features: Number of features per time step
        cnn_filters: List of CNN filter counts
        kernel_size: CNN kernel size
        pool_size: Max pooling size
        lstm_units: List of LSTM layer units
        dense_units: List of dense layer units
        dropout_rate: Dropout rate
        use_attention: Whether to use attention
        learning_rate: Learning rate
        
    Returns:
        Compiled Keras model
    """
    inputs = layers.Input(shape=(sequence_length, n_features), name='input')
    x = inputs

    # Layer Normalization before CNN (stabilizes gradients)
    x = layers.LayerNormalization(name='layer_norm_input')(x)

    # CNN layers for pattern extraction
    for i, filters in enumerate(cnn_filters):
        x = layers.Conv1D(
            filters=filters,
            kernel_size=kernel_size,
            activation='relu',
            padding='same',
            name=f'conv1d_{i+1}'
        )(x)
        x = layers.BatchNormalization(name=f'bn_conv_{i+1}')(x)
        
        if i < len(cnn_filters) - 1:  # Don't pool on last CNN layer
            x = layers.MaxPooling1D(pool_size=pool_size, name=f'pool_{i+1}')(x)
        
        x = layers.Dropout(dropout_rate * 0.5, name=f'dropout_conv_{i+1}')(x)
    
    # LSTM layers for temporal modeling with L2 regularization (Phase 3.4)
    for i, units in enumerate(lstm_units):
        return_sequences = (i < len(lstm_units) - 1) or use_attention
        x = layers.LSTM(
            units,
            return_sequences=return_sequences,
            kernel_regularizer=regularizers.l2(0.01),
            recurrent_regularizer=regularizers.l2(0.01),
            name=f'lstm_{i+1}'
        )(x)
        x = layers.BatchNormalization(name=f'bn_lstm_{i+1}')(x)
        x = layers.Dropout(dropout_rate, name=f'dropout_lstm_{i+1}')(x)
    
    # Attention layer
    if use_attention:
        x = AttentionLayer(name='attention')(x)
    
    # Dense layers
    for i, units in enumerate(dense_units):
        x = layers.Dense(units, activation='relu', name=f'dense_{i+1}')(x)
        x = layers.Dropout(dropout_rate * 0.5, name=f'dropout_dense_{i+1}')(x)
    
    # Output layer
    outputs = layers.Dense(2, activation='softmax', name='output')(x)
    
    # Create model
    model = Model(inputs=inputs, outputs=outputs, name='CNN_LSTM_Model')
    
    # Compile
    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=learning_rate),
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy']
    )
    
    return model


def build_bidirectional_lstm_model(sequence_length: int,
                                   n_features: int,
                                   lstm_units: List[int] = [128, 64],
                                   dense_units: List[int] = [32],
                                   dropout_rate: float = 0.3,
                                   learning_rate: float = 0.001) -> Model:
    """
    Build Bidirectional LSTM model.
    
    Processes sequences in both forward and backward directions.
    
    Args:
        sequence_length: Number of time steps
        n_features: Number of features
        lstm_units: LSTM layer units
        dense_units: Dense layer units
        dropout_rate: Dropout rate
        learning_rate: Learning rate
        
    Returns:
        Compiled Keras model
    """
    inputs = layers.Input(shape=(sequence_length, n_features), name='input')
    x = inputs
    
    # Bidirectional LSTM layers
    for i, units in enumerate(lstm_units):
        return_sequences = i < len(lstm_units) - 1
        x = layers.Bidirectional(
            layers.LSTM(units, return_sequences=return_sequences),
            name=f'bi_lstm_{i+1}'
        )(x)
        x = layers.BatchNormalization(name=f'bn_{i+1}')(x)
        x = layers.Dropout(dropout_rate, name=f'dropout_{i+1}')(x)
    
    # Dense layers
    for i, units in enumerate(dense_units):
        x = layers.Dense(units, activation='relu', name=f'dense_{i+1}')(x)
        x = layers.Dropout(dropout_rate * 0.5, name=f'dropout_dense_{i+1}')(x)
    
    # Output
    outputs = layers.Dense(2, activation='softmax', name='output')(x)
    
    model = Model(inputs=inputs, outputs=outputs, name='BiLSTM_Model')
    
    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=learning_rate),
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy']
    )
    
    return model


def get_callbacks(model_path: str,
                  patience: int = 10,
                  min_delta: float = 0.001,
                  log_dir: str = None) -> List:
    """
    Get standard callbacks for training.
    
    Args:
        model_path: Path to save best model
        patience: Early stopping patience
        min_delta: Minimum improvement threshold
        log_dir: TensorBoard log directory
        
    Returns:
        List of callbacks
    """
    callbacks = [
        EarlyStopping(
            monitor='val_loss',
            patience=patience,
            min_delta=min_delta,
            restore_best_weights=True,
            verbose=1
        ),
        ReduceLROnPlateau(
            monitor='val_loss',
            factor=0.5,
            patience=5,
            min_lr=1e-7,
            verbose=1
        ),
        ModelCheckpoint(
            filepath=model_path,
            monitor='val_accuracy',
            save_best_only=True,
            verbose=1
        )
    ]
    
    if log_dir:
        callbacks.append(
            TensorBoard(
                log_dir=log_dir,
                histogram_freq=1,
                write_graph=True
            )
        )
    
    return callbacks


def print_model_summary(model: Model):
    """
    Print detailed model summary.
    
    Args:
        model: Keras model
    """
    print("\n" + "="*60)
    print(f"Model: {model.name}")
    print("="*60)
    model.summary()
    print("="*60)
    
    # Count parameters
    trainable_params = np.sum([np.prod(v.shape) for v in model.trainable_weights])
    non_trainable_params = np.sum([np.prod(v.shape) for v in model.non_trainable_weights])
    total_params = trainable_params + non_trainable_params
    
    print(f"\n📊 Parameters:")
    print(f"   Total: {total_params:,}")
    print(f"   Trainable: {trainable_params:,}")
    print(f"   Non-trainable: {non_trainable_params:,}")
    print("="*60 + "\n")


if __name__ == '__main__':
    # Test model building
    print("Testing TensorFlow model builders...")
    
    sequence_length = 20
    n_features = 150
    
    # Test LSTM
    print("\n1. Building LSTM model...")
    lstm_model = build_lstm_model(sequence_length, n_features)
    print_model_summary(lstm_model)
    
    # Test CNN-LSTM
    print("\n2. Building CNN-LSTM model...")
    cnn_lstm_model = build_cnn_lstm_model(sequence_length, n_features)
    print_model_summary(cnn_lstm_model)
    
    # Test Bidirectional LSTM
    print("\n3. Building Bidirectional LSTM model...")
    bi_lstm_model = build_bidirectional_lstm_model(sequence_length, n_features)
    print_model_summary(bi_lstm_model)
    
    print("\n✅ All model builders tested successfully!")
