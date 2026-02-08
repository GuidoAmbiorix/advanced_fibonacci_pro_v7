import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

def plot_learning_history(history):
    """Plots training and validation loss/accuracy."""
    if history is None:
        return

    plt.figure(figsize=(12, 4))
    
    # Loss
    plt.subplot(1, 2, 1)
    plt.plot(history.history['loss'], label='Train Loss')
    plt.plot(history.history['val_loss'], label='Val Loss')
    plt.title('Model Loss')
    plt.xlabel('Epoch')
    plt.ylabel('Loss')
    plt.legend()
    
    # Accuracy
    plt.subplot(1, 2, 2)
    plt.plot(history.history['accuracy'], label='Train Acc')
    plt.plot(history.history['val_accuracy'], label='Val Acc')
    plt.title('Model Accuracy')
    plt.xlabel('Epoch')
    plt.ylabel('Accuracy')
    plt.legend()
    
    plt.tight_layout()
    plt.savefig('learning_history.png')
    plt.close()

def visualize_model_perception(feature_model, last_window_scaled, window_size=48):
    """
    Visualizes the input data.
    Note: MLP does not have 'feature maps' like a CNN, so we visualize the input and
    potentially the first layer weights if accessible, but for now we focus on the input "image".
    """
    if last_window_scaled is None:
         return

    # Plot feature maps
    plt.figure(figsize=(10, 8))
    
    # Plot original data
    plt.subplot(3, 1, 1)
    plt.title("Original Price Data (Normalized)")
    plt.plot(np.arange(window_size), last_window_scaled[:, 0], label='Open', alpha=0.7)
    plt.plot(np.arange(window_size), last_window_scaled[:, 1], label='High', alpha=0.7)
    plt.plot(np.arange(window_size), last_window_scaled[:, 2], label='Low', alpha=0.7)
    plt.plot(np.arange(window_size), last_window_scaled[:, 3], label='Close', color='black', linewidth=2)
    plt.legend()
    
    # Plot candlestick representation
    plt.subplot(3, 1, 2)
    plt.title("Candlestick Representation")
    
    width = 0.6
    for i in range(len(last_window_scaled)):
        open_p = last_window_scaled[i, 0]
        close_p = last_window_scaled[i, 3]
        high_p = last_window_scaled[i, 1]
        low_p = last_window_scaled[i, 2]
        
        if close_p >= open_p:
            color = 'green'
            body_bottom = open_p
            body_height = close_p - open_p
        else:
            color = 'red'
            body_bottom = close_p
            body_height = open_p - close_p
        
        plt.bar(i, body_height, bottom=body_bottom, color=color, width=width, alpha=0.5)
        plt.plot([i, i], [low_p, high_p], color='black', linewidth=1)
    
    plt.tight_layout()
    plt.savefig('model_perception.png')
    plt.close()

def visualize_attention_heatmap(feature_model, last_window_scaled, window_size=48):
    """
    Visualizes attention heatmap.
    For MLP, we don't have spatial activation maps.
    We skipped the complex heatmap generation in this compatibility mode.
    """
    # Placeholder to prevent crash
    pass

def plot_prediction_chart(data, window_size=48, prediction_window=24, direction="UP ▲"):
    """Visualizes the final prediction on the chart."""
    if data is None or len(data) < window_size:
        return

    plt.figure(figsize=(10, 6))
    
    # Get the last window
    last_window = data.iloc[-window_size:]
    
    # Create future dates for visualization
    last_date = last_window.index[-1]
    # Estimate frequency. If undefined, assume hourly.
    freq = '1h'
    try:
        if isinstance(data.index, pd.DatetimeIndex):
             # Try to infer freq
             diff = data.index.to_series().diff().mode()
             if not diff.empty:
                 freq = diff[0]
    except:
        pass
        
    future_dates = pd.date_range(start=last_date, periods=prediction_window+1, freq=freq)[1:]
    
    # Plot closing prices
    plt.plot(last_window.index, last_window['close'], label='Historical Data')
    
    current_price = last_window['close'].iloc[-1]
    plt.scatter(last_window.index[-1], current_price, color='blue', s=100, zorder=5)
    
    # Draw arrow
    price_range = last_window['high'].max() - last_window['low'].min()
    arrow_length = price_range * 0.1
    
    if "UP" in direction:
        target_price = current_price + arrow_length
        arrow_color = 'green'
    else:
        target_price = current_price - arrow_length
        arrow_color = 'red'
        
    plt.annotate('', 
                 xy=(future_dates[-1], target_price),
                 xytext=(last_window.index[-1], current_price),
                 arrowprops=dict(arrowstyle='->', lw=2, color=arrow_color))
                 
    plt.title(f'Forecast for {prediction_window} periods: {direction}')
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig('prediction_chart.png')
    plt.close()
