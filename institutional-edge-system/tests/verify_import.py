
import sys
import os

# Add backend to path
sys.path.append(os.path.join(os.getcwd(), 'backend'))

# Mock 'ta' module since we only test config logic
import types
mock_ta = types.ModuleType("ta")
mock_ta.trend = types.ModuleType("ta.trend")
mock_ta.volatility = types.ModuleType("ta.volatility")
mock_ta.momentum = types.ModuleType("ta.momentum")

# Mock 'httpx'
sys.modules["httpx"] = types.ModuleType("httpx")

# Mock 'app.core.config'
mock_config = types.ModuleType("app.core.config")
mock_settings = types.SimpleNamespace()
mock_settings.DISCORD_WEBHOOK_URL = ""
mock_settings.DISCORD_WEBHOOK_SIGNALS_URL = ""
mock_config.settings = mock_settings
sys.modules["app.core.config"] = mock_config

# Mock 'app.services.discord_service'
mock_discord = types.ModuleType("app.services.discord_service")
class MockDiscordService:
    def __init__(self): pass
mock_discord.DiscordService = MockDiscordService
sys.modules["app.services.discord_service"] = mock_discord

class DummyIndicator:
    def __init__(self, *args, **kwargs): pass
    def sma_indicator(self): return []
    def ema_indicator(self): return []
    def macd(self): return []
    def macd_signal(self): return []
    def macd_diff(self): return []
    def rsi(self): return []
    def stoch(self): return []
    def stoch_signal(self): return []
    def average_true_range(self): return []
    def bollinger_hband(self): return []
    def bollinger_lband(self): return []
    def bollinger_mavg(self): return []

mock_ta.trend.SMAIndicator = DummyIndicator
mock_ta.trend.EMAIndicator = DummyIndicator
mock_ta.trend.MACD = DummyIndicator
mock_ta.volatility.AverageTrueRange = DummyIndicator
mock_ta.volatility.BollingerBands = DummyIndicator
mock_ta.momentum.RSIIndicator = DummyIndicator
mock_ta.momentum.StochasticOscillator = DummyIndicator

sys.modules["ta"] = mock_ta
sys.modules["ta.trend"] = mock_ta.trend
sys.modules["ta.volatility"] = mock_ta.volatility
sys.modules["ta.momentum"] = mock_ta.momentum

try:
    from app.backtesting.engine import BacktestEngine
    print("✅ Successfully imported BacktestEngine")
except ImportError as e:
    print(f"❌ ImportError: {e}")
except Exception as e:
    print(f"❌ Error: {e}")
