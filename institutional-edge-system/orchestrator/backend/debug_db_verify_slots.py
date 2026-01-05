
from app.api.database import SessionLocal
from app.models.database import BotSlot

db = SessionLocal()
try:
    slot = db.query(BotSlot).filter(BotSlot.symbol == "XAUUSD").first()
    if slot:
        print(f"Risk: {slot.risk_percent}")
        print(f"MACD: {slot.macd_fast}/{slot.macd_slow}/{slot.macd_signal}")
        print(f"RSI: {slot.rsi_period} (OB:{slot.rsi_overbought} OS:{slot.rsi_oversold})")
        print(f"ZigZag: {slot.zigzag_lookback}")
        print(f"SMC: OB={slot.ob_lookback} Sweep={slot.sweep_lookback} FVG={slot.fvg_min_size_atr}")
        print(f"Session: {slot.trading_session}")
    else:
        print("Slot not found")
finally:
    db.close()
