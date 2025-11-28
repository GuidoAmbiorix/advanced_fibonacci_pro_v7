# Implementation Plan - God Combination & AlphaVantage (Full Stack)

## Goal
Transform the trading system to use the "God Combination" strategy (Trend, Momentum, Volatility, Volume, Structure) and integrate AlphaVantage for fundamental analysis. This plan covers the entire flow from backend logic to frontend visualization.

## User Review Required
> [!IMPORTANT]
> **API Key Required**: Please add `ALPHAVANTAGE_API_KEY=your_key_here` to your `.env` file.

> [!WARNING]
> **Strategy Change**: This will significantly modify the entry logic to strictly follow the "God Combination" rules (EMA50/200, MACD, OBV, Structure).

## Proposed Changes

### 1. Backend Configuration & Dependencies
#### [MODIFY] [config.py](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/backend/app/core/config.py)
- Add `ALPHAVANTAGE_API_KEY`.
- Add strategy parameters: `EMA_FAST=50`, `EMA_SLOW=200`, `ATR_PERIOD=14`, `ATR_SL_MULTIPLIER=1.5`, `ATR_TP_MULTIPLIER=3.0`.

#### [MODIFY] [requirements.txt](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/backend/requirements.txt)
- Ensure `ta` (Technical Analysis library) and `httpx` are installed.

### 2. Backend Services (Logic Layer)
#### [NEW] [alphavantage_service.py](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/backend/app/services/alphavantage_service.py)
- **Purpose**: Fetch fundamental data.
- **Methods**:
    - `get_company_overview(symbol)`: Returns PE, EPS, Sector, Description.
    - `get_sentiment(symbol)`: Returns market sentiment score.
- **Caching**: Implement simple in-memory or Redis caching to avoid hitting API limits.

#### [MODIFY] [trading_engine.py](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/backend/app/core/trading_engine.py)
- **Purpose**: Execute "God Combination" logic.
- **New Logic**:
    - `_calculate_god_indicators(df)`: Computes EMA50/200, MACD, OBV, ATR.
    - `_check_god_entry(df)`: Returns `True` ONLY if all 5 conditions are met.
- **Signal Structure**: Update `TradingSignal` dataclass to include `god_score_breakdown` (e.g., "Trend: Bullish", "Momentum: Rising").

### 3. Backend API (Exposure Layer)
#### [NEW] [fundamentals.py](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/backend/app/api/fundamentals.py)
- **Endpoint**: `GET /api/fundamentals/{symbol}`
- **Response**: JSON with company overview and sentiment.

#### [MODIFY] [main.py](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/backend/app/main.py)
- Register the new `fundamentals` router.

### 4. Frontend Integration (UI Layer)
#### [MODIFY] [api.js](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/frontend/src/services/api.js)
- Add `getFundamentals(symbol)` method calling `/api/fundamentals/{symbol}`.

#### [NEW] [FundamentalWidget.vue](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/frontend/src/components/FundamentalWidget.vue)
- **Purpose**: Display AlphaVantage data.
- **UI**: Small card showing Sector, PE Ratio, and a Sentiment gauge.

#### [MODIFY] [SignalsPanel.vue](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/frontend/src/components/SignalsPanel.vue)
- **UI Updates**:
    - Add a "God Mode" badge for signals meeting all criteria.
    - Display the specific "God Combination" factors (e.g., "EMA Trend: ✅", "OBV: ✅").
    - Integrate `FundamentalWidget` inside the expanded signal view (if space permits) or as a tooltip.

#### [MODIFY] [Dashboard.vue](file:///C:/Users/gamparo/Desktop/Projects/advanced_fibonacci_pro_v7/institutional-edge-system/frontend/src/components/Dashboard.vue)
- Add `FundamentalWidget` to the sidebar or main grid.

## Verification Plan

### Automated Tests
- **Backend**: `tests/test_god_strategy.py` (mock data -> signal verification).
- **Backend**: `tests/test_alphavantage.py` (API connectivity).

### Manual Verification
1.  **Start Backend**: `run_backend.bat`
2.  **Start Frontend**: `run_frontend.bat`
3.  **Check UI**:
    - Verify `FundamentalWidget` loads data for a symbol (e.g., AAPL/EURUSD).
    - Wait for a signal (or force one via mock) and verify the "God Mode" indicators are visible in `SignalsPanel`.
