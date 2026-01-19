
import asyncio
import sys
import os
from datetime import datetime
from loguru import logger

# Add project root to path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../../')))

from app.core.config import settings
from app.services.risk_manager import risk_manager

async def run_chaos_test():
    print("🔥 STARTED: INTERNAL CHAOS TEST 🔥")
    print("-----------------------------------")
    
    # 1. Test Frequency Guard
    print("\n[TEST 1] Testing Frequency Guard (Max Trades/Hour)...")
    print(f"Configured Limit: {settings.RISK_MAX_TRADES_PER_HOUR}")
    
    allowed_count = 0
    blocked_count = 0
    
    # Reset for test
    risk_manager.trade_timestamps.clear()
    
    for i in range(20):
        is_allowed, reason = risk_manager.check_trade_allowed("XAUUSD", 0.1)
        if is_allowed:
            allowed_count += 1
            risk_manager.record_trade("XAUUSD", 0.1)
            print(f"Trade {i+1}: ✅ ALLOWED")
        else:
            blocked_count += 1
            print(f"Trade {i+1}: 🛡️ BLOCKED ({reason})")
            
    print(f"\nResult: Allowed {allowed_count} / Blocked {blocked_count}")
    if blocked_count > 0 and allowed_count <= settings.RISK_MAX_TRADES_PER_HOUR:
        print("✅ PASS: Frequency Guard active")
    else:
        print("❌ FAIL: Frequency Guard did not trigger or allowed too many")

    # 2. Test Equity Curve Guard (Kill Switch)
    print("\n[TEST 2] Testing Equity Crash (Kill Switch)...")
    
    # Simulate stable state
    risk_manager.initial_balance = 100000
    risk_manager.current_equity = 100000
    # Seed history to satisfy len < 5 check
    for _ in range(10):
        risk_manager.update_metrics(100000, 100000)
    
    # Crash equity by 10% instantly
    crash_equity = 90000 
    print(f"Simulating Drop: $100,000 -> ${crash_equity}")
    
    risk_manager.update_metrics(crash_equity, 100000)
    
    # Allow async tasks to fire
    await asyncio.sleep(1)
    
    if risk_manager.kill_switch_active:
        print(f"✅ PASS: Kill Switch Triggered! Reason: {risk_manager.kill_switch_reason}")
    else:
        print(f"❌ FAIL: Kill Switch did NOT trigger. (Active: {risk_manager.kill_switch_active})")

    print("\n-----------------------------------")
    print("🏁 CHAOS TEST COMPLETE")

if __name__ == "__main__":
    asyncio.run(run_chaos_test())
