"""
MT5 Bridge Service - REST API for MetaTrader 5 Communication

This service runs on the Windows host (where MT5 is installed) and provides
a REST API for the ML engine and dashboard to interact with MT5.
"""

import MetaTrader5 as mt5
from flask import Flask, jsonify, request
import yaml
import logging
import os
from datetime import datetime, timedelta
import pandas as pd
from pathlib import Path
import sys
import threading
import time
import schedule
from dotenv import load_dotenv

# Add parent directory to path for database access
sys.path.append(str(Path(__file__).parent.parent))
from src.database import DatabaseManager

app = Flask(__name__)

# Global state
config = None
db = None
mt5_connected = False

def load_config():
    """Load configuration from YAML file."""
    global config
    config_path = Path(__file__).parent / "config.yaml"
    with open(config_path, 'r') as f:
        config = yaml.safe_load(f)
    
    # Ensure logs directory exists
    log_file = Path(config['logging']['file'])
    log_file.parent.mkdir(parents=True, exist_ok=True)
    
    # Setup logging
    log_level = getattr(logging, config['logging']['level'])
    logging.basicConfig(
        level=log_level,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(config['logging']['file']),
            logging.StreamHandler()
        ]
    )

def connect_mt5():
    """Initialize connection to MT5."""
    global mt5_connected
    
    if not mt5.initialize():
        logging.error("MT5 initialization failed")
        return False
    
    # Login if credentials provided
    if config['mt5']['login'] and config['mt5']['password']:
        authorized = mt5.login(
            login=config['mt5']['login'],
            password=config['mt5']['password'],
            server=config['mt5']['server']
        )
        if not authorized:
            logging.error(f"MT5 login failed: {mt5.last_error()}")
            mt5.shutdown()
            return False
    
    mt5_connected = True
    logging.info("MT5 connected successfully")
    db.log('INFO', 'BRIDGE', 'MT5 connected successfully')
    return True

# ==================== API Endpoints ====================

@app.route('/status', methods=['GET'])
def get_status():
    """Get MT5 connection status."""
    return jsonify({
        'connected': mt5_connected,
        'terminal_info': mt5.terminal_info()._asdict() if mt5_connected else None,
        'account_info': mt5.account_info()._asdict() if mt5_connected else None
    })

@app.route('/symbols/list', methods=['GET'])
def list_symbols():
    """Get list of available symbols."""
    if not mt5_connected:
        return jsonify({'error': 'MT5 not connected'}), 503
    
    symbols = mt5.symbols_get()
    if symbols is None:
        return jsonify({'error': 'Failed to get symbols'}), 500
    
    return jsonify({
        'symbols': [s.name for s in symbols]
    })

@app.route('/symbols/<symbol>/info', methods=['GET'])
def get_symbol_info(symbol):
    """Get symbol specifications including minimum stop level."""
    if not mt5_connected:
        return jsonify({'error': 'MT5 not connected'}), 503
    
    # Get symbol info
    symbol_info = mt5.symbol_info(symbol)
    if symbol_info is None:
        return jsonify({'error': f'Symbol {symbol} not found'}), 404
    
    # Get stop level (minimum distance for stops in points)
    stops_level = symbol_info.trade_stops_level
    point = symbol_info.point
    
    # Get current prices
    tick = mt5.symbol_info_tick(symbol)
    bid = tick.bid if tick else 0.0
    ask = tick.ask if tick else 0.0
    
    return jsonify({
        'symbol': symbol,
        'bid': bid,
        'ask': ask,
        'stops_level': stops_level,  # Minimum stop distance in points
        'point': point,  # Point size
        'digits': symbol_info.digits,
        'trade_contract_size': symbol_info.trade_contract_size,
        'volume_min': symbol_info.volume_min,
        'volume_max': symbol_info.volume_max,
        'volume_step': symbol_info.volume_step
    })


@app.route('/data/fetch', methods=['POST'])
def fetch_data():
    """
    Fetch historical data for a symbol.
    
    Request body:
    {
        "symbol": "EURUSD",
        "timeframe": "H1",
        "num_bars": 1000
    }
    """
    if not mt5_connected:
        return jsonify({'error': 'MT5 not connected'}), 503
    
    data = request.json
    symbol = data.get('symbol', 'EURUSD')
    timeframe_str = data.get('timeframe', 'H1')
    num_bars = data.get('num_bars', 1000)
    
    # Convert timeframe string to MT5 constant
    timeframe_map = {
        'M1': mt5.TIMEFRAME_M1,
        'M5': mt5.TIMEFRAME_M5,
        'M15': mt5.TIMEFRAME_M15,
        'M30': mt5.TIMEFRAME_M30,
        'H1': mt5.TIMEFRAME_H1,
        'H4': mt5.TIMEFRAME_H4,
        'D1': mt5.TIMEFRAME_D1
    }
    timeframe = timeframe_map.get(timeframe_str, mt5.TIMEFRAME_H1)
    
    # Check if symbol exists and is visible
    symbol_info = mt5.symbol_info(symbol)
    if symbol_info is None:
        error_msg = f"Symbol {symbol} not found. Check symbol name in MT5."
        logging.error(error_msg)
        logging.error(f"MT5 last error: {mt5.last_error()}")
        return jsonify({'error': error_msg, 'hint': 'Verify symbol name in MT5 Market Watch'}), 404
    
    # Enable symbol in Market Watch if not visible
    if not symbol_info.visible:
        logging.info(f"Symbol {symbol} not visible, attempting to enable...")
        if not mt5.symbol_select(symbol, True):
            error_msg = f"Failed to enable symbol {symbol}"
            logging.error(error_msg)
            logging.error(f"MT5 last error: {mt5.last_error()}")
            return jsonify({'error': error_msg, 'hint': 'Add symbol to Market Watch in MT5'}), 400
        logging.info(f"Symbol {symbol} enabled successfully")
    
    # Fetch data
    rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, num_bars)
    
    if rates is None or len(rates) == 0:
        error = mt5.last_error()
        error_msg = f"Failed to fetch data for {symbol}: {error}"
        logging.error(error_msg)
        hint = "Open a chart for this symbol in MT5 terminal to load historical data"
        return jsonify({'error': error_msg, 'hint': hint, 'mt5_error': error}), 500
    
    # Convert to DataFrame
    df = pd.DataFrame(rates)
    df['timestamp'] = pd.to_datetime(df['time'], unit='s')
    
    # Store in database
    try:
        db.insert_market_data(symbol, timeframe_str, df)
        logging.info(f"Fetched and stored {len(df)} bars for {symbol} {timeframe_str}")
    except Exception as e:
        logging.error(f"Error storing market data: {e}")
    
    return jsonify({
        'symbol': symbol,
        'timeframe': timeframe_str,
        'bars_fetched': len(df),
        'latest_time': df['timestamp'].max().isoformat()
    })

@app.route('/bars', methods=['GET'])
def get_bars():
    """
    Get historical bars for a symbol (GET request with query params).

    Query params:
        symbol: Symbol name (e.g., EURUSD)
        timeframe: Timeframe string (e.g., H1, H4, D1, W1)
        count: Number of bars to fetch (default: 200)

    Returns bars data as JSON array.
    """
    if not mt5_connected:
        return jsonify({'error': 'MT5 not connected'}), 503

    symbol = request.args.get('symbol', 'EURUSD')
    timeframe_str = request.args.get('timeframe', 'H1')
    count = int(request.args.get('count', 200))

    # Convert timeframe string to MT5 constant
    timeframe_map = {
        'M1': mt5.TIMEFRAME_M1,
        'M5': mt5.TIMEFRAME_M5,
        'M15': mt5.TIMEFRAME_M15,
        'M30': mt5.TIMEFRAME_M30,
        'H1': mt5.TIMEFRAME_H1,
        'H4': mt5.TIMEFRAME_H4,
        'D1': mt5.TIMEFRAME_D1,
        'W1': mt5.TIMEFRAME_W1,
    }
    timeframe = timeframe_map.get(timeframe_str, mt5.TIMEFRAME_H1)

    # Check if symbol exists
    symbol_info = mt5.symbol_info(symbol)
    if symbol_info is None:
        logging.warning(f"Symbol {symbol} not found")
        return jsonify({'error': f'Symbol {symbol} not found'}), 404

    # Enable symbol if not visible
    if not symbol_info.visible:
        logging.info(f"Enabling symbol {symbol}...")
        if not mt5.symbol_select(symbol, True):
            logging.error(f"Failed to enable symbol {symbol}")
            return jsonify({'error': f'Failed to enable symbol {symbol}'}), 400

    # Fetch bars
    rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, count)

    if rates is None or len(rates) == 0:
        error = mt5.last_error()
        logging.error(f"Failed to fetch bars for {symbol} {timeframe_str}: {error}")
        return jsonify({'error': f'No data available', 'mt5_error': error}), 404

    # Convert to list of dicts
    df = pd.DataFrame(rates)
    df['timestamp'] = pd.to_datetime(df['time'], unit='s')

    # Return bars in format expected by MTFAnalyzer
    bars = df[['timestamp', 'open', 'high', 'low', 'close', 'tick_volume']].to_dict('records')

    # Convert timestamp to ISO format string
    for bar in bars:
        bar['timestamp'] = bar['timestamp'].isoformat()

    logging.info(f"Served {len(bars)} bars for {symbol} {timeframe_str}")

    return jsonify({'bars': bars})

@app.route('/trade/open', methods=['POST'])
def open_trade():
    """
    Open a new trade.
    
    Request body:
    {
        "symbol": "EURUSD",
        "action": "BUY" or "SELL",
        "volume": 0.01,
        "stop_loss": 1.0950,
        "take_profit": 1.1050,
        "comment": "ML Signal"
    }
    """
    if not mt5_connected:
        return jsonify({'error': 'MT5 not connected'}), 503
    
    data = request.json
    symbol = data['symbol']
    action = data['action']
    volume = data['volume']
    sl = data.get('stop_loss')
    tp = data.get('take_profit')
    comment = data.get('comment', '')
    
    # Prepare request
    symbol_info = mt5.symbol_info(symbol)
    if symbol_info is None:
        return jsonify({'error': f'Symbol {symbol} not found'}), 400
    
    if not symbol_info.visible:
        if not mt5.symbol_select(symbol, True):
            return jsonify({'error': f'Failed to select {symbol}'}), 400
    
    # Get current price
    tick = mt5.symbol_info_tick(symbol)
    if tick is None:
        return jsonify({'error': 'Failed to get current price'}), 500
    
    price = tick.ask if action == 'BUY' else tick.bid
    order_type = mt5.ORDER_TYPE_BUY if action == 'BUY' else mt5.ORDER_TYPE_SELL
    
    request_dict = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": symbol,
        "volume": volume,
        "type": order_type,
        "price": price,
        "sl": sl if sl else 0.0,
        "tp": tp if tp else 0.0,
        "deviation": 20,
        "magic": 234000,
        "comment": comment,
        "type_time": mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_FOK,
    }
    
    # Send order
    result = mt5.order_send(request_dict)
    
    if result is None:
        error_msg = f"Order send failed: {mt5.last_error()}"
        logging.error(error_msg)
        db.log('ERROR', 'BRIDGE', error_msg, {'symbol': symbol, 'action': action})
        return jsonify({'error': error_msg}), 500
    
    if result.retcode != mt5.TRADE_RETCODE_DONE:
        error_msg = f"Order failed: {result.comment}"
        logging.error(error_msg)
        db.log('ERROR', 'BRIDGE', error_msg, {'result': result._asdict()})
        return jsonify({'error': error_msg, 'retcode': result.retcode}), 400
    
    # Store position in database
    try:
        db.insert_position(
            mt5_ticket=result.order,
            symbol=symbol,
            position_type=action,
            volume=volume,
            open_price=result.price,
            open_time=datetime.now(),
            stop_loss=sl,
            take_profit=tp
        )
        logging.info(f"Trade opened: {action} {volume} {symbol} @ {result.price}")
        db.log('INFO', 'BRIDGE', f'Trade opened: {action} {volume} {symbol}', 
               {'ticket': result.order, 'price': result.price})
    except Exception as e:
        logging.error(f"Error storing position: {e}")
    
    return jsonify({
        'success': True,
        'ticket': result.order,
        'price': result.price,
        'volume': result.volume
    })

@app.route('/trade/close', methods=['POST'])
def close_trade():
    """
    Close an existing position.
    
    Request body:
    {
        "ticket": 123456
    }
    """
    if not mt5_connected:
        return jsonify({'error': 'MT5 not connected'}), 503
    
    data = request.json
    ticket = data['ticket']
    
    # Get position info
    position = mt5.positions_get(ticket=ticket)
    if not position:
        return jsonify({'error': f'Position {ticket} not found'}), 404
    
    position = position[0]
    
    # Prepare close request
    close_type = mt5.ORDER_TYPE_SELL if position.type == mt5.ORDER_TYPE_BUY else mt5.ORDER_TYPE_BUY
    price = mt5.symbol_info_tick(position.symbol).bid if position.type == mt5.ORDER_TYPE_BUY else mt5.symbol_info_tick(position.symbol).ask
    
    request_dict = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": position.symbol,
        "volume": position.volume,
        "type": close_type,
        "position": ticket,
        "price": price,
        "deviation": 20,
        "magic": 234000,
        "comment": "Close by API",
        "type_time": mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_FOK,
    }
    
    result = mt5.order_send(request_dict)
    
    if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
        error_msg = f"Close failed: {result.comment if result else mt5.last_error()}"
        logging.error(error_msg)
        return jsonify({'error': error_msg}), 500
    
    logging.info(f"Position {ticket} closed @ {result.price}")
    db.log('INFO', 'BRIDGE', f'Position closed: {ticket}', {'price': result.price})
    
    return jsonify({
        'success': True,
        'ticket': ticket,
        'close_price': result.price
    })

@app.route('/positions', methods=['GET'])
def get_positions():
    """Get all open positions (direct list)."""
    if not mt5_connected:
        return jsonify({'error': 'MT5 not connected'}), 503
    
    positions = mt5.positions_get()
    if positions is None:
        return jsonify([])
    
    return jsonify([p._asdict() for p in positions])

@app.route('/positions/list', methods=['GET'])
def list_positions():
    """Get all open positions."""
    if not mt5_connected:
        return jsonify({'error': 'MT5 not connected'}), 503
    
    positions = mt5.positions_get()
    if positions is None:
        return jsonify({'positions': []})
    
    return jsonify({
        'positions': [p._asdict() for p in positions]
    })

# ==================== Background Data Sync ====================

def sync_market_data():
    """Background task to sync market data for multiple timeframes."""
    if not mt5_connected or not config['sync']['enabled']:
        return

    # Timeframes to sync for MTF analysis
    timeframes_to_sync = {
        'H1': mt5.TIMEFRAME_H1,
        'H4': mt5.TIMEFRAME_H4,
        'D1': mt5.TIMEFRAME_D1
    }

    for symbol in config['sync']['symbols']:
        for timeframe_str, timeframe_constant in timeframes_to_sync.items():
            try:
                # Adjust bars based on timeframe (need more history for higher TFs)
                if timeframe_str == 'H1':
                    num_bars = config['sync']['bars_to_fetch']  # e.g., 5000
                elif timeframe_str == 'H4':
                    num_bars = 1500  # 1500 H4 bars = ~250 days
                else:  # D1
                    num_bars = 500   # 500 D1 bars = ~500 days

                rates = mt5.copy_rates_from_pos(symbol, timeframe_constant, 0, num_bars)
                if rates is not None and len(rates) > 0:
                    df = pd.DataFrame(rates)
                    df['timestamp'] = pd.to_datetime(df['time'], unit='s')
                    db.insert_market_data(symbol, timeframe_str, df)
                    logging.debug(f"Synced {len(df)} bars for {symbol} {timeframe_str}")
            except Exception as e:
                logging.error(f"Error syncing {symbol} {timeframe_str}: {e}")

def run_scheduler():
    """Run the background scheduler."""
    while True:
        schedule.run_pending()
        time.sleep(1)

@app.route('/trade/modify', methods=['POST'])
def modify_trade():
    """Modify an existing position's SL/TP."""
    if not mt5_connected:
        return jsonify({'success': False, 'error': 'MT5 not connected'}), 503
    
    data = request.json
    ticket = data.get('ticket')
    new_sl = data.get('sl')
    new_tp = data.get('tp')
    
    if not ticket:
        return jsonify({'success': False, 'error': 'Ticket required'}), 400
    
    # Get position info
    position = mt5.positions_get(ticket=ticket)
    if not position:
        return jsonify({'success': False, 'error': 'Position not found'}), 404
    
    position = position[0]
    
    # Create modification request
    request_dict = {
        "action": mt5.TRADE_ACTION_SLTP,
        "position": ticket,
        "sl": new_sl if new_sl else position.sl,
        "tp": new_tp if new_tp else position.tp,
    }
    
    # Send modification
    result = mt5.order_send(request_dict)
    
    if result.retcode != mt5.TRADE_RETCODE_DONE:
        error_msg = f"Modification failed: {result.comment}"
        logging.error(error_msg)
        return jsonify({'success': False, 'error': error_msg, 'retcode': result.retcode}), 400
    
    logging.info(f"Modified position {ticket}: SL={new_sl}, TP={new_tp}")
    return jsonify({
        'success': True,
        'ticket': ticket,
        'new_sl': new_sl,
        'new_tp': new_tp
    })

@app.route('/trade/close_partial', methods=['POST'])
def close_partial():
    """Close a partial amount of a position."""
    if not mt5_connected:
        return jsonify({'success': False, 'error': 'MT5 not connected'}), 503
    
    data = request.json
    ticket = data.get('ticket')
    close_percent = data.get('close_percent', 0.5)  # Default 50%
    
    if not ticket:
        return jsonify({'success': False, 'error': 'Ticket required'}), 400
    
    # Get position
    position = mt5.positions_get(ticket=ticket)
    if not position:
        return jsonify({'success': False, 'error': 'Position not found'}), 404
    
    position = position[0]
    
    # Calculate partial volume
    partial_volume = round(position.volume * close_percent, 2)
    
    # Ensure minimum volume
    symbol_info = mt5.symbol_info(position.symbol)
    if partial_volume < symbol_info.volume_min:
        return jsonify({'success': False, 'error': 'Partial volume too small'}), 400
    
    # Close partial
    request_dict = {
        "action": mt5.TRADE_ACTION_DEAL,
        "position": ticket,
        "symbol": position.symbol,
        "volume": partial_volume,
        "type": mt5.ORDER_TYPE_SELL if position.type == mt5.ORDER_TYPE_BUY else mt5.ORDER_TYPE_BUY,
        "price": mt5.symbol_info_tick(position.symbol).bid if position.type == mt5.ORDER_TYPE_BUY else mt5.symbol_info_tick(position.symbol).ask,
        "deviation": 20,
        "magic": 234000,
        "comment": "Partial close",
        "type_time": mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_IOC,
    }
    
    result = mt5.order_send(request_dict)
    
    if result.retcode != mt5.TRADE_RETCODE_DONE:
        error_msg = f"Partial close failed: {result.comment}"
        logging.error(error_msg)
        return jsonify({'success': False, 'error': error_msg, 'retcode': result.retcode}), 400
    
    logging.info(f"Closed {close_percent*100}% of position {ticket}")
    return jsonify({
        'success': True,
        'ticket': ticket,
        'closed_volume': partial_volume,
        'remaining_volume': position.volume - partial_volume
    })

@app.route('/indicators/atr', methods=['GET'])
def get_atr():
    """Calculate ATR for a symbol."""
    if not mt5_connected:
        return jsonify({'error': 'MT5 not connected'}), 503
    
    symbol = request.args.get('symbol', 'EURUSD')
    timeframe = request.args.get('timeframe', 'M5')
    period = int(request.args.get('period', 14))
    
    # Map timeframe string to MT5 constant
    timeframe_map = {
        'M1': mt5.TIMEFRAME_M1,
        'M5': mt5.TIMEFRAME_M5,
        'M15': mt5.TIMEFRAME_M15,
        'M30': mt5.TIMEFRAME_M30,
        'H1': mt5.TIMEFRAME_H1,
        'H4': mt5.TIMEFRAME_H4,
        'D1': mt5.TIMEFRAME_D1
    }
    
    tf = timeframe_map.get(timeframe, mt5.TIMEFRAME_M5)
    
    # Get recent bars
    bars = mt5.copy_rates_from_pos(symbol, tf, 0, period + 1)
    
    if bars is None or len(bars) < period:
        return jsonify({'error': 'Insufficient data'}), 400
    
    # Calculate True Range for each bar
    true_ranges = []
    for i in range(1, len(bars)):
        high = bars[i]['high']
        low = bars[i]['low']
        prev_close = bars[i-1]['close']
        
        tr = max(
            high - low,
            abs(high - prev_close),
            abs(low - prev_close)
        )
        true_ranges.append(tr)
    
    # ATR is the average of true ranges
    atr = sum(true_ranges[-period:]) / period
    
    return jsonify({
        'symbol': symbol,
        'timeframe': timeframe,
        'period': period,
        'atr': atr
    })

@app.route('/indicators/momentum', methods=['GET'])
def get_momentum():
    """Calculate momentum indicators (RSI, MACD, Stochastic) for a symbol."""
    if not mt5_connected:
        return jsonify({'error': 'MT5 not connected'}), 503

    symbol = request.args.get('symbol', 'EURUSD')
    timeframe_str = request.args.get('timeframe', 'H1')

    # Map timeframe string to MT5 constant
    timeframe_map = {
        'M1': mt5.TIMEFRAME_M1,
        'M5': mt5.TIMEFRAME_M5,
        'M15': mt5.TIMEFRAME_M15,
        'M30': mt5.TIMEFRAME_M30,
        'H1': mt5.TIMEFRAME_H1,
        'H4': mt5.TIMEFRAME_H4,
        'D1': mt5.TIMEFRAME_D1,
        'W1': mt5.TIMEFRAME_W1,
    }
    timeframe = timeframe_map.get(timeframe_str, mt5.TIMEFRAME_H1)

    # Get 100 bars for indicator calculation
    bars = mt5.copy_rates_from_pos(symbol, timeframe, 0, 100)

    if bars is None or len(bars) < 50:
        return jsonify({'error': 'Insufficient data'}), 400

    # Convert to numpy arrays
    import numpy as np
    close_prices = np.array([bar['close'] for bar in bars], dtype=np.float64)
    high_prices = np.array([bar['high'] for bar in bars], dtype=np.float64)
    low_prices = np.array([bar['low'] for bar in bars], dtype=np.float64)

    try:
        import talib

        # RSI
        rsi = talib.RSI(close_prices, timeperiod=14)
        rsi_current = float(rsi[-1]) if len(rsi) > 0 and not np.isnan(rsi[-1]) else 50.0

        # MACD
        macd, signal, hist = talib.MACD(close_prices, fastperiod=12, slowperiod=26, signalperiod=9)
        macd_hist = float(hist[-1]) if len(hist) > 0 and not np.isnan(hist[-1]) else 0.0

        # Stochastic
        stoch_k, stoch_d = talib.STOCH(high_prices, low_prices, close_prices,
                                        fastk_period=14, slowk_period=3, slowd_period=3)
        stoch_k_current = float(stoch_k[-1]) if len(stoch_k) > 0 and not np.isnan(stoch_k[-1]) else 50.0

        return jsonify({
            'symbol': symbol,
            'timeframe': timeframe_str,
            'rsi': rsi_current,
            'macd_hist': macd_hist,
            'stoch_k': stoch_k_current
        })

    except ImportError:
        # Fallback: simple calculations without TA-Lib
        # Simple RSI approximation
        changes = np.diff(close_prices)
        gains = np.where(changes > 0, changes, 0)
        losses = np.where(changes < 0, -changes, 0)
        avg_gain = np.mean(gains[-14:]) if len(gains) >= 14 else 0
        avg_loss = np.mean(losses[-14:]) if len(losses) >= 14 else 0
        rs = avg_gain / avg_loss if avg_loss != 0 else 0
        rsi = 100 - (100 / (1 + rs))

        # Simple momentum
        momentum = close_prices[-1] - close_prices[-10] if len(close_prices) >= 10 else 0

        return jsonify({
            'symbol': symbol,
            'timeframe': timeframe_str,
            'rsi': float(rsi),
            'macd_hist': float(momentum),
            'stoch_k': 50.0  # Neutral
        })

# ==================== Main ====================

if __name__ == '__main__':
    # Load environment variables from bridge/.env (for PostgreSQL config)
    bridge_env_path = Path(__file__).parent / '.env'
    if bridge_env_path.exists():
        load_dotenv(bridge_env_path)
        print(f"✓ Loaded environment variables from {bridge_env_path}")
    else:
        print(f"✗ WARNING: {bridge_env_path} not found!")

    # Debug: Print what was loaded
    print(f"DATABASE_TYPE = {os.environ.get('DATABASE_TYPE', 'NOT SET')}")
    print(f"DATABASE_URL = {os.environ.get('DATABASE_URL', 'NOT SET')}")

    # Load configuration
    load_config()

    # Initialize database
    # DatabaseManager will automatically detect DATABASE_TYPE and DATABASE_URL from environment
    db = DatabaseManager()

    # Log database connection
    logging.info("Database type: PostgreSQL")
    logging.info(f"PostgreSQL connection: {db.db_url.split('@')[1] if '@' in db.db_url else 'configured'}")
    
    # Connect to MT5
    if not connect_mt5():
        logging.error("Failed to connect to MT5. Exiting.")
        sys.exit(1)
    
    # Setup background sync
    if config['sync']['enabled']:
        schedule.every(config['sync']['interval_seconds']).seconds.do(sync_market_data)
        scheduler_thread = threading.Thread(target=run_scheduler, daemon=True)
        scheduler_thread.start()
        logging.info(f"Background sync enabled (every {config['sync']['interval_seconds']}s)")
    
    # Start Flask API
    logging.info(f"Starting MT5 Bridge API on {config['api']['host']}:{config['api']['port']}")
    app.run(
        host=config['api']['host'],
        port=config['api']['port'],
        debug=config['api']['debug']
    )
