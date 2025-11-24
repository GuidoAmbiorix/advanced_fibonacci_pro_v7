"""
Simple MT5 Connection Test
This script tests if MT5 is installed and can be connected to.
"""

import MetaTrader5 as mt5

print("=" * 60)
print("Testing MT5 Connection...")
print("=" * 60)

# Initialize MT5
print("\n1. Attempting to initialize MT5...")
if not mt5.initialize():
    print("   [FAILED] Failed to initialize MT5")
    print(f"   Error: {mt5.last_error()}")
    print("\n   Possible solutions:")
    print("   - Make sure MetaTrader 5 is installed")
    print("   - Make sure MT5 is running")
    print("   - Check MT5_PATH in .env file")
    quit()

print("   [SUCCESS] MT5 initialized successfully!")

# Get terminal info
print("\n2. Getting terminal information...")
terminal_info = mt5.terminal_info()
if terminal_info:
    print(f"   Terminal: {terminal_info.name}")
    print(f"   Company: {terminal_info.company}")
    print(f"   Build: {terminal_info.build}")
    print(f"   Path: {terminal_info.path}")
    print(f"   Connected: {terminal_info.connected}")
else:
    print("   [WARNING] Could not get terminal info")

# Get account info
print("\n3. Getting account information...")
account_info = mt5.account_info()
if account_info:
    print(f"   Account: #{account_info.login}")
    print(f"   Server: {account_info.server}")
    print(f"   Balance: ${account_info.balance:.2f}")
    print(f"   Equity: ${account_info.equity:.2f}")
    print(f"   Leverage: 1:{account_info.leverage}")
    print(f"   Currency: {account_info.currency}")
else:
    print("   [WARNING] Could not get account info")
    print("   You may need to log in to MT5 first")

# Test getting symbols
print("\n4. Testing symbol access...")
symbols = mt5.symbols_total()
print(f"   Total symbols available: {symbols}")

# Test getting data
print("\n5. Testing market data retrieval...")
try:
    rates = mt5.copy_rates_from_pos("EURUSD", mt5.TIMEFRAME_H1, 0, 10)
    if rates is not None and len(rates) > 0:
        print(f"   [SUCCESS] Successfully got {len(rates)} bars of EURUSD H1 data")
        print(f"   Latest close price: {rates[-1]['close']:.5f}")
    else:
        print("   [WARNING] No data available for EURUSD")
        print("   Try a different symbol that your broker provides")
except Exception as e:
    print(f"   [FAILED] Error getting data: {e}")

# Shutdown
mt5.shutdown()

print("\n" + "=" * 60)
print("[SUCCESS] MT5 Connection Test Complete!")
print("=" * 60)
print("\nNext steps:")
print("1. If MT5 connected successfully, you can proceed")
print("2. Update .env file with your MT5 credentials if needed")
print("3. Run the backend server: python backend/app/main.py")
print("=" * 60)
