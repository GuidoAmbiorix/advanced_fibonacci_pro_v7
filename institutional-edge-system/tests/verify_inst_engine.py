
import sys
import os
from pprint import pprint

# Add backend to path
sys.path.append(os.path.join(os.getcwd(), 'backend'))

# Mock 'ta' module since we only test config logic
import types
mock_ta = types.ModuleType("ta")
mock_ta.trend = types.ModuleType("ta.trend")
mock_ta.volatility = types.ModuleType("ta.volatility")
sys.modules["ta"] = mock_ta
sys.modules["ta.trend"] = mock_ta.trend
sys.modules["ta.volatility"] = mock_ta.volatility

# Add Dummy Classes
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
mock_ta.momentum = types.ModuleType("ta.momentum")
mock_ta.momentum.RSIIndicator = DummyIndicator
mock_ta.momentum.StochasticOscillator = DummyIndicator
sys.modules["ta.momentum"] = mock_ta.momentum


from app.engines.factory import EngineFactory
from app.engines.xau_pro.core import InstitutionalProEngine

def test_engine_defaults():
    test_cases = [
        {'symbol': 'XAUUSD', 'expected_session': 'BOTH_KZ', 'desc': 'Gold - Should have Killzones'},
        {'symbol': 'BTCUSD', 'expected_session': 'ALL', 'desc': 'Crypto - 24/7 Session'},
        {'symbol': 'EURUSD', 'expected_session': 'BOTH_KZ', 'desc': 'Forex - Killzones'},
        {'symbol': 'USDJPY', 'expected_session': 'ALL', 'desc': 'JPY Pair - 24/7 or All due to Asia'},
    ]
    
    print("🧪 Verifying InstitutionalProEngine Defaults...\n")
    
    for case in test_cases:
        print(f"--- Testing {case['symbol']} ({case['desc']}) ---")
        config = {'symbol': case['symbol'], 'timeframe': 'M15'}
        
        # Instantiate via Factory
        try:
            engine = EngineFactory.create_engine('INSTITUTIONAL', config)
            
            # Check Class
            is_pro = isinstance(engine, InstitutionalProEngine)
            print(f"✅ Instantiated Correctly: {is_pro}")
            
            # Check Defaults
            print(f"   Session Mode: {engine.session_mode}")
            print(f"   RSI Thresholds: {engine.rsi_buy_threshold}/{engine.rsi_sell_threshold}")
            print(f"   SL ATR Multiplier: {engine.sl_atr_multiplier}")
            print(f"   MACD: {engine.macd_fast}/{engine.macd_slow}/{engine.macd_signal}")
            
            # Validation
            if engine.session_mode != case['expected_session']:
                 print(f"❌ SESSION MISMATCH: Expected {case['expected_session']}, got {engine.session_mode}")
            else:
                 print(f"✅ Session Mode OK")
                 
            print("")
            
        except Exception as e:
            print(f"❌ FAILED: {e}")
            import traceback
            traceback.print_exc()

if __name__ == "__main__":
    test_engine_defaults()
