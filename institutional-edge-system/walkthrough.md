# System Overhaul Walkthrough

## Changes Implemented

### 1. De-Dockerization
- **Backend**: Now runs locally on `localhost:8000`.
- **Frontend**: Now runs locally on `localhost:5173`.
- **Infrastructure**: `docker-compose.yml` now only runs PostgreSQL (Port 5433) and Redis (Port 6379).

### 2. Database Updates
- **BotConfig Table**: Added columns for automated trade management:
    - `be_trigger` (Float): R-multiple to trigger Break Even move.
    - `trailing_sl` (Boolean): Enable/Disable trailing stop.
    - `trailing_step` (Float): Step size for trailing stop in R-multiples.
    - `partial_tp_on` (Boolean): Enable/Disable partial take profit.
    - `partial_tp_amount` (Float): Percentage of position to close at TP1 (e.g., 0.5 for 50%).

### 3. Trading Logic Overhaul
- **Trade Manager**: Implemented `TradeManager` in `backend/app/services/trade_manager.py`.
    - **Break Even**: Automatically moves SL to Entry + Offset when price moves in favor by `BE Trigger` amount.
    - **Trailing Stop**: Dynamically trails SL behind price by 1.5R once `Trailing Step` is reached.
    - **Partial TP**: (Logic stubbed) Ready to close partial volume at TP1.
    - **Auto-Execution**: Bot now executes trades automatically based on signals.
- **Streaming Removed**: WebSocket endpoints and `StreamDashboard` have been removed.

### 4. New Frontend
- **Execution Dashboard**: A new dashboard focused on execution and trade management.
    - **Control Panel**: Start/Stop Bot, Configure Risk & BE Trigger.
    - **Signal Feed**: View and manually execute signals.
    - **Open Trades**: Monitor active trades and PnL.

## How to Run

### 1. Infrastructure
Start the database and redis:
```bash
docker-compose up -d
```
*Note: Since the DB schema changed, you may need to recreate the database or run migrations if using Alembic. For dev, dropping the tables is easiest.*

### 2. Backend
Open a new terminal:
```bash
run_backend.bat
```
*Verify at http://localhost:8000/docs*

### 3. Frontend
Open a new terminal:
```bash
run_frontend.bat
```
*Access at http://localhost:5173*

## Verification Steps

1.  **Start System**: Follow the "How to Run" steps above.
2.  **Configure**: On the dashboard, set "Risk per Trade" to 1.0% and "BE Trigger" to 1.0R.
3.  **Start Bot**: Click "START BOT".
4.  **Wait for Signal**: When a signal appears, it will auto-execute (if bot is running) or you can click "EXECUTE NOW".
5.  **Monitor Trade**: Watch the "Open Positions" table.
6.  **Verify BE**: If the trade goes in profit by 1R, check MT5 (or the table) to see if SL has moved to the entry price.
