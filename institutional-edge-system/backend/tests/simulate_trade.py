import asyncio
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from unittest.mock import MagicMock, AsyncMock
import sys
import os

# Add backend to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

from app.services.trading_bot import TradingBot
from app.core.adaptive_multi_strategy_engine import AdaptiveMultiStrategyEngine, MarketRegime

async def run_simulation():
    print("🚀 Starting Trading Bot Simulation...")

    # 1. Create Synthetic Data (Strong Uptrend + Pullback + Resumption)
    print("📊 Generating synthetic market data for Trend Following BUY...")
    dates = pd.date_range(end=datetime.now(), periods=200, freq='15min')
    data = {
        'time': dates,
        'open': [], 'high': [], 'low': [], 'close': [], 'volume': []
    }
    
    price = 1.1000
    ema20 = 1.1000
    
    for i in range(200):
        # 0-170: Strong Uptrend
        if i < 170:
            change = 0.0005
            price += change
        # 171-195: Pullback (drop towards EMA) - Longer pullback to cool RSI
        elif i < 195:
            change = -0.0003
            price += change
        # 196-199: Resumption (Buy Signal) - Gradual rise
        else:
            change = 0.0002 # Less aggressive rise
            price += change
            
        # Add some noise
        noise = (i % 2) * 0.0001
        
        open_p = price
        close_p = price + change
        high_p = max(open_p, close_p) + 0.0002
        low_p = min(open_p, close_p) - 0.0002
        
        data['open'].append(open_p)
        data['high'].append(high_p)
        data['low'].append(low_p)
        data['close'].append(close_p)
        
        # High volume on resumption
        vol = 1000 if i < 195 else 5000
        data['volume'].append(vol)
        
    df = pd.DataFrame(data)
    
    # 2. Mock Dependencies
    print("🛠️ Mocking MT5 and Discord...")
    
    # Mock MT5 Connector
    mock_mt5 = MagicMock()
    # Mock get_ohlcv_data for both primary (M15) and higher timeframe (H4)
    mock_mt5.get_ohlcv_data.side_effect = lambda symbol, timeframe, bars: df
    
    mock_mt5.get_current_price.return_value = df.iloc[-1]['close']
    mock_mt5.get_account_info.return_value = {'balance': 10000, 'equity': 10000}
    mock_mt5.get_positions.return_value = []
    mock_mt5.place_trade.return_value = {'retcode': 10009, 'deal': 12345, 'volume': 0.1, 'price': 1.1000} # Trade executed
    
    # Mock Discord Service
    mock_discord = AsyncMock()
    
    # 3. Initialize Bot
    print("🤖 Initializing Trading Bot...")
    
    # Mock Socket.IO
    mock_sio = AsyncMock()
    
    # Initialize with correct arguments: id, connector, sio
    bot = TradingBot(1, mock_mt5, mock_sio)
    bot.discord = mock_discord
    
    # Ensure the connector is set correctly (TradingBot sets self.mt5_connector)
    bot.mt5_connector = mock_mt5
    
    # Mock database session to avoid DB errors
    bot.db = MagicMock()
    
    # Mock _load_config to avoid DB query
    bot_config = MagicMock()
    bot_config.id = 1
    bot_config.symbol = "EURUSD"
    bot_config.timeframe = "M15"
    bot_config.strategy_config = {
        'enable_institutional_strategy': True,
        'enable_vwap_strategy': True,
        'enable_stoch_strategy': True,
        'enable_fibonacci_strategy': True
    }
    # Add other required config fields
    bot_config.be_trigger = 1.0
    bot_config.trailing_sl = True
    bot_config.trailing_step = 0.5
    bot_config.trailing_distance = 1.0
    bot_config.tsl_mode = "ATR"
    bot_config.tsl_activation_r = 1.0
    bot_config.tsl_atr_period = 14
    bot_config.tsl_atr_multiplier = 1.5
    bot_config.partial_tp_on = False
    bot_config.partial_tp_amount = 0.5
    
    bot.config = bot_config
    
    # Manually call _init_trading_engine since we skipped start()
    bot._init_trading_engine()
    
    # Initialize trade manager manually since we skipped start()
    from app.services.trade_manager import TradeManager
    bot.trade_manager = TradeManager(mock_mt5)
    bot.trade_manager.timeframe = "M15"
    
    # Initialize other managers
    from app.services.risk_manager import AdaptiveRiskManager
    from app.services.portfolio_manager import PortfolioManager
    bot.risk_manager = AdaptiveRiskManager()
    bot.portfolio_manager = PortfolioManager()
    
    # 4. Run Analysis
    print("🧠 Running Market Analysis...")
    
    # FORCE A SIGNAL to test execution path
    from app.core.adaptive_multi_strategy_engine import AdaptiveSignal, StrategyType, MarketRegime
    
    mock_signal = AdaptiveSignal(
        symbol="EURUSD",
        timeframe="M15",
        entry_price=1.1000,
        stop_loss=1.0950,
        take_profit=1.1100,
        direction="BUY",
        strategy_type=StrategyType.TREND_FOLLOWING,
        market_regime=MarketRegime.TRENDING,
        score=9.0,
        confidence=0.9,
        timestamp=datetime.now(),
        metadata={'test': 'true'}
    )
    
    # Mock the analyze method to return our forced signal
    # This bypasses indicator logic and tests _save_signals and _execute_signal directly
    bot.trading_engine.analyze = MagicMock(return_value={
        'symbol': "EURUSD",
        'timeframe': "M15",
        'signals': [mock_signal],
        'market_regime': "TRENDING",
        'strategy_used': "TREND_FOLLOWING",
        'win_streak': 0,
        'higher_tf_trend': "BULLISH",
        'bull_confluence_score': 9.0,
        'bear_confluence_score': 2.0
    })

    await bot._analyze_market()
    
    # 5. Verify Results
    print("\n📋 Simulation Results:")
    
    # Check if market status update was sent
    if mock_discord.send_market_status_update.called:
        print("✅ Market Status Update sent to Discord")
        call_args = mock_discord.send_market_status_update.call_args[0][0]
        print(f"   - Bull Score: {call_args.get('bull_confluence_score')}")
        print(f"   - Bear Score: {call_args.get('bear_confluence_score')}")
        print(f"   - Signals: {len(call_args.get('signals', []))}")
    else:
        print("❌ Market Status Update NOT sent")

    # Check if trade was placed
    if mock_mt5.place_trade.called:
        print("✅ Trade Executed on MT5")
        trade_args = mock_mt5.place_trade.call_args
        print(f"   - Args: {trade_args}")
    else:
        print("⚠️ No Trade Executed (Check signal logic or filters)")
        
    # Check if signal alert was sent
    if mock_discord.send_signal_alert.called:
        print("✅ Signal Alert sent to Discord")
    else:
        print("⚠️ No Signal Alert sent")

if __name__ == "__main__":
    asyncio.run(run_simulation())
