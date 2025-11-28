# Implementation Plan - God Combination & AlphaVantage

## Goal
Transform the trading system to use the "God Combination" strategy (Trend, Momentum, Volatility, Volume, Structure) and integrate AlphaVantage for fundamental analysis.

## User Review Required
> [!IMPORTANT]
> **API Key Required**: Please add `ALPHAVANTAGE_API_KEY=your_key_here` to your `.env` file.

> [!WARNING]
> **Strategy Change**: This will significantly modify the entry logic to strictly follow the "God Combination" rules (EMA50/200, MACD, OBV, Structure).

## Proposed Changes

### 1. Backend Configuration
#### [MODIFY] [config.py](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/backend/app/core/config.py)
- Add `ALPHAVANTAGE_API_KEY`.
- Add strategy parameters: `EMA_FAST=50`, `EMA_SLOW=200`, `ATR_PERIOD=14`, `ATR_SL_MULTIPLIER=1.5`, `ATR_TP_MULTIPLIER=3.0`.

### 2. Fundamental Analysis (AlphaVantage)
#### [NEW] [alphavantage_service.py](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/backend/app/services/alphavantage_service.py)
- Implement `AlphaVantageService` to fetch:
    - **Company Overview**: (PE Ratio, EPS, Sector) for fundamental filtering.
    - **News/Sentiment**: (Optional) for market sentiment.
- This service will be used to annotate signals with fundamental data.

### 3. Technical Analysis (God Combination)
#### [MODIFY] [trading_engine.py](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/backend/app/core/trading_engine.py)
- **Imports**: Add `ta` library for EMA, MACD, OBV, ATR.
- **Indicators**: Implement `_calculate_god_indicators(df)`:
    - EMA 50 & 200
    - MACD (12, 26, 9) & Histogram
    - OBV (On-Balance Volume)
    - ATR (14)
- **Logic Implementation**:
    - **Trend**: `EMA50 > EMA200` (Buy) / `EMA50 < EMA200` (Sell).
    - **Momentum**: `MACD_Hist > MACD_Hist[prev]` (Rising) vs Falling.
    - **Volume**: `OBV > OBV[prev]` (Rising) vs Falling.
    - **Structure**: Enhance `_detect_bos_choch` to specifically identify "Break + Retest" setups.
        - *Break*: Price closes above Swing High.
        - *Retest*: Price returns to the breakout level (or near it) and rejects.
- **Signal Generation**:
    - Enforce ALL conditions must be met for a signal.
    - Calculate SL/TP using ATR multipliers.

### 4. Integration
#### [MODIFY] [trading_bot.py](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/backend/app/services/trading_bot.py)
- Integrate `AlphaVantageService` to check fundamentals before trading (e.g., log fundamental data, or avoid trading if PE is extreme - *User to confirm specific fundamental rules, currently just logging*).

## Verification Plan

### Automated Tests
- **Strategy Test**: Create `tests/test_god_strategy.py` to feed mock data (perfect setup) and verify a signal is generated.
- **AlphaVantage Test**: Create `tests/test_alphavantage.py` to verify API connectivity.

### Manual Verification
- Run the bot in `paper_trading` mode.
- Verify logs show:
    - "God Combination" conditions being checked.
    - Fundamental data being fetched from AlphaVantage.
