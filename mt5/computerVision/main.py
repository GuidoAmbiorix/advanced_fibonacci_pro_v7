import MetaTrader5 as mt5
import matplotlib
matplotlib.use('Agg')  # Using Agg backend for running without GUI
import sys
import os

# Add src to path
sys.path.append(os.path.join(os.path.dirname(__file__), 'src'))

from mt5_connector import connect_to_mt5, get_historical_data
from preprocessing import create_images
from model_builder import build_and_train_model, make_prediction
from visualization import plot_learning_history, visualize_model_perception, visualize_attention_heatmap, plot_prediction_chart

def main():
    print("Starting EURUSD prediction system with computer vision")
    
    # Connect to MT5
    if not connect_to_mt5():
        print("Failed to connect to MT5. Exiting.")
        return
    
    print("Successfully connected to MetaTrader5")
    
    # Load historical data
    bars_to_load = 2000  # Load more than needed for training
    symbol = "EURUSD"
    data = get_historical_data(symbol=symbol, num_bars=bars_to_load)
    
    if data is None:
        mt5.shutdown()
        return
    
    print(f"Loaded {len(data)} bars of {symbol} history")
    
    # Convert data to image format
    print("Converting data for computer vision processing...")
    images, targets = create_images(data)
    print(f"Created {len(images)} images for training")
    
    # Train model
    print("Training computer vision model...")
    model, history, feature_model = build_and_train_model(images, targets)
    
    if model is None:
        print("Model training failed.")
        mt5.shutdown()
        return

    # Visualize training process
    plot_learning_history(history)
    print("Saved learning_history.png")
    
    # Prediction
    direction, confidence, last_window_scaled = make_prediction(model, data)
    print(f"Forecast for the next 24 periods: {direction} (confidence: {confidence:.2f}%)")
    
    # Visualize prediction
    plot_prediction_chart(data, direction=direction)
    print("Saved prediction_chart.png")
    
    # Visualize how the model "sees" the market
    visualize_model_perception(feature_model, last_window_scaled)
    print("Saved model_perception.png")
    
    # Visualize attention heatmap
    visualize_attention_heatmap(feature_model, last_window_scaled)
    print("Saved attention_heatmap.png")
    
    # Disconnect from MT5
    mt5.shutdown()
    print("Work completed")

if __name__ == "__main__":
    main()
