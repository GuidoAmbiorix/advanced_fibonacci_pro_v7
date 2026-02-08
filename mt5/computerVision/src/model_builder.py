import numpy as np
import pandas as pd
from sklearn.neural_network import MLPClassifier
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import MinMaxScaler
import pickle

def build_and_train_model(images, targets):
    """
    Builds and trains the Neural Network model using Scikit-Learn.
    
    Args:
        images (np.array): Array of input images (normalized OHLC windows).
        targets (np.array): Array of target labels (0 or 1).
        
    Returns:
        tuple: (model, history, feature_model)
        Note: history and feature_model are simulated/simplified for compatibility.
    """
    if len(images) == 0:
        print("No images to train on.")
        return None, None, None

    # Flatten the images for MLP input (batch_size, window_size * channels)
    n_samples = images.shape[0]
    n_features = images.shape[1] * images.shape[2]
    X_flattened = images.reshape(n_samples, n_features)

    # Split data into training and validation sets
    X_train, X_val, y_train, y_val = train_test_split(X_flattened, targets, test_size=0.2, shuffle=True, random_state=42)
    
    print("Initializing MLP Classifier...")
    # Create MLP Classifier (simulating the deep network)
    # Architecture: Input -> Dense(128) -> Dense(64) -> Output
    model = MLPClassifier(
        hidden_layer_sizes=(128, 64),
        activation='relu',
        solver='adam',
        alpha=0.0001,
        batch_size=32,
        learning_rate='adaptive',
        learning_rate_init=0.001,
        max_iter=50,
        early_stopping=True,
        validation_fraction=0.1,
        verbose=True,
        random_state=42
    )
    
    print("Starting model training...")
    # Train model
    model.fit(X_train, y_train)
    
    # Create a history object to mimic Keras history for visualization
    class History:
        def __init__(self, loss_curve, score):
            self.history = {
                'loss': loss_curve,
                'val_loss': [], # MLP doesn't expose val_loss easily per epoch in the same way
                'accuracy': [], # MLP doesn't expose accuracy per epoch easily
                'val_accuracy': [score] * len(loss_curve) 
            }
            
    # Calculate score on validation set
    val_score = model.score(X_val, y_val)
    history = History(model.loss_curve_, val_score)
    
    # Feature model concept doesn't map 1:1 to MLP, so we return None or the model itself to handle in viz
    feature_model = model 
    
    return model, history, feature_model

def make_prediction(model, data, window_size=48):
    """
    Makes a prediction on the most recent data window.
    
    Args:
        model: Trained Scikit-Learn model.
        data (pd.DataFrame): OHLC data.
        window_size (int): Size of the input window.
        
    Returns:
        tuple: (direction, confidence_percent, last_window_scaled)
    """
    if len(data) < window_size:
        return "INSUFFICIENT DATA", 0.0, None

    # Get the last window of data
    last_window = data.iloc[-window_size:][['open', 'high', 'low', 'close']]
    
    # Normalize data
    scaler = MinMaxScaler(feature_range=(0, 1))
    last_window_scaled = scaler.fit_transform(last_window)
    
    # Prepare data for the model
    # Flatten: (1, window_size * 4)
    last_window_flattened = last_window_scaled.reshape(1, -1)
    
    # Get prediction probabilities
    try:
        prediction_prob = model.predict_proba(last_window_flattened)[0]
        # prediction_prob is [prob_class_0, prob_class_1]
        
        up_prob = prediction_prob[1]
        
        # Interpret result
        direction = "UP ▲" if up_prob > 0.5 else "DOWN ▼"
        confidence = up_prob if up_prob > 0.5 else 1 - up_prob
        
    except Exception as e:
        print(f"Prediction error: {e}")
        return "ERROR", 0.0, last_window_scaled
    
    return direction, confidence * 100, last_window_scaled
