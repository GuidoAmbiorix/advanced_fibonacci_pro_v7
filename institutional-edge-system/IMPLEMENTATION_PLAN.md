# Implementation Plan - Fibonacci Signal Enhancement

## Goal Description
Enhance the existing trading signals by incorporating Fibonacci retracement and extension levels. This will add a new layer of confluence to the `TradingEngine`, improving the precision of entry and exit points.

## User Review Required
> [!IMPORTANT]
> This change will modify the `TradingEngine` logic and the `TradingSignal` structure. Existing strategies relying on the current confluence score might need adjustment as the scoring range will increase.

## Proposed Changes

### Backend

#### [MODIFY] [trading_engine.py](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/backend/app/core/trading_engine.py)
- **Add Fibonacci Calculation Logic**:
    - Implement a method `_calculate_fibonacci_levels` to compute key levels (0.382, 0.5, 0.618, 0.786) based on the most recent significant swing high and low.
    - Identify the "Golden Zone" (0.5 - 0.618).
- **Update Confluence Calculation**:
    - Modify `_calculate_confluence` to check if the current price is within a key Fibonacci level or the Golden Zone.
    - Add points to the confluence score if price aligns with Fibonacci levels (e.g., +2 for Golden Zone, +1 for other levels).
- **Update Signal Generation**:
    - Include Fibonacci levels in the `TradingSignal` object for reference (e.g., nearest fib level).
    - Use Fibonacci extensions (e.g., -0.27, -0.618) for dynamic Take Profit targets if applicable.

#### [MODIFY] [schemas.py](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/backend/app/schemas/schemas.py)
- Update `SignalResponse` schema to include Fibonacci data if we decide to expose it in the API response.

## Verification Plan

### Automated Tests
- Create a unit test for `_calculate_fibonacci_levels` to ensure it correctly identifies levels from given swing points.
- Create a test case where price is in the Golden Zone and verify the confluence score increases.

### Manual Verification
- Run the backend locally on Windows (`python scripts/run_backend.py`) to connect to the real MT5 terminal.
- Ensure MetaTrader 5 is running and Algo Trading is enabled.
- Trigger analysis on a symbol (e.g., EURUSD).
- Verify in the logs that "Fibonacci Golden Zone" is listed in the score breakdown when applicable and that real price data is used.
