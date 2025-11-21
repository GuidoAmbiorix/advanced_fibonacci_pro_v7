# 🎯 COMPLETE IMPLEMENTATION PLAN
## Institutional Edge PRO - From Zero to Production

**Estimated Total Time:** 4-6 weeks (working part-time)
**Difficulty Level:** Intermediate to Advanced
**Prerequisites:** Python, JavaScript, Basic Trading Knowledge

---

# 📋 TABLE OF CONTENTS

1. [Phase 0: Prerequisites & Environment Setup](#phase-0-prerequisites--environment-setup)
2. [Phase 1: Backend Core - Trading Engine](#phase-1-backend-core---trading-engine)
3. [Phase 2: MT5 Integration](#phase-2-mt5-integration)
4. [Phase 3: Database Setup](#phase-3-database-setup)
5. [Phase 4: FastAPI Backend](#phase-4-fastapi-backend)
6. [Phase 5: Frontend Dashboard](#phase-5-frontend-dashboard)
7. [Phase 6: Testing & Validation](#phase-6-testing--validation)
8. [Phase 7: Deployment](#phase-7-deployment)
9. [Phase 8: Monitoring & Maintenance](#phase-8-monitoring--maintenance)

---

# PHASE 0: Prerequisites & Environment Setup

**⏱️ Time Required:** 2-3 hours
**Goal:** Set up development environment and install all required tools

## Step 0.1: Install Required Software

### Windows Users:

1. **Python 3.10 or higher**
   ```
   Download from: https://www.python.org/downloads/

   ⚠️ IMPORTANT: Check "Add Python to PATH" during installation

   Verify installation:
   > python --version
   Python 3.10.x
   ```

2. **MetaTrader 5**
   ```
   Download from: https://www.metatrader5.com/en/download

   Install and login with your broker credentials
   Verify MT5 is running and connected to your broker
   ```

3. **PostgreSQL Database**
   ```
   Download from: https://www.postgresql.org/download/

   During installation:
   - Set password: "postgres" (or your choice)
   - Port: 5432 (default)
   - Remember your password!

   Verify:
   > psql --version
   psql (PostgreSQL) 15.x
   ```

4. **Node.js and npm**
   ```
   Download from: https://nodejs.org/ (LTS version)

   Verify:
   > node --version
   v18.x.x
   > npm --version
   9.x.x
   ```

5. **Git (Optional but recommended)**
   ```
   Download from: https://git-scm.com/download/win

   Verify:
   > git --version
   git version 2.x.x
   ```

6. **Code Editor**
   ```
   VS Code (Recommended):
   Download from: https://code.visualstudio.com/

   Install these extensions:
   - Python
   - Pylance
   - Vue Language Features (Volar)
   - ESLint
   - Prettier
   ```

### Mac/Linux Users:

```bash
# Python
brew install python@3.10  # Mac
sudo apt install python3.10  # Ubuntu

# PostgreSQL
brew install postgresql  # Mac
sudo apt install postgresql  # Ubuntu

# Node.js
brew install node  # Mac
sudo apt install nodejs npm  # Ubuntu
```

---

## Step 0.2: Create Project Structure

```bash
# Create main directory
cd Desktop/Sccripts
mkdir institutional-edge-system
cd institutional-edge-system

# Create subdirectories
mkdir -p backend/app/core
mkdir -p backend/app/models
mkdir -p backend/app/schemas
mkdir -p backend/app/api
mkdir -p backend/app/services
mkdir -p frontend/src/components
mkdir -p frontend/src/views
mkdir -p frontend/src/stores
mkdir -p logs
mkdir -p tests
```

**Result:** You should have this structure:
```
institutional-edge-system/
├── backend/
│   └── app/
│       ├── core/
│       ├── models/
│       ├── schemas/
│       ├── api/
│       └── services/
├── frontend/
│   └── src/
│       ├── components/
│       ├── views/
│       └── stores/
├── logs/
└── tests/
```

---

## Step 0.3: Create Python Virtual Environment

```bash
cd institutional-edge-system

# Create virtual environment
python -m venv venv

# Activate it
# Windows:
venv\Scripts\activate

# Mac/Linux:
source venv/bin/activate

# You should see (venv) in your terminal
(venv) C:\...\institutional-edge-system>
```

**✅ Verification:**
```bash
which python  # Mac/Linux
where python  # Windows

# Should point to venv directory
```

---

## Step 0.4: Create requirements.txt

Create `requirements.txt` in root directory:

```txt
# Core Trading
MetaTrader5==5.0.45
pandas==2.1.4
numpy==1.26.2
ta==0.11.0

# FastAPI Backend
fastapi==0.109.0
uvicorn[standard]==0.27.0
python-multipart==0.0.6
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
python-dotenv==1.0.0

# Database
sqlalchemy==2.0.25
alembic==1.13.1
psycopg2-binary==2.9.9

# Redis
redis==5.0.1

# WebSocket
websockets==12.0

# Data Validation
pydantic==2.5.3
pydantic-settings==2.1.0

# Utilities
python-dateutil==2.8.2
pytz==2023.3
loguru==0.7.2

# Testing
pytest==7.4.4
pytest-asyncio==0.23.3
httpx==0.26.0
```

Install all dependencies:
```bash
pip install -r requirements.txt
```

This will take 5-10 minutes.

---

## Step 0.5: Create .env Configuration File

Create `.env` file in root directory:

```bash
# Copy from example
cp .env.example .env

# Or create manually
notepad .env  # Windows
nano .env     # Mac/Linux
```

**Minimal .env for Development:**
```bash
# Application
APP_NAME="Institutional Edge Pro"
APP_VERSION="1.0.0"
DEBUG=True
SECRET_KEY=dev-secret-key-change-in-production
JWT_SECRET_KEY=dev-jwt-secret-change-in-production

# Server
HOST=0.0.0.0
PORT=8000

# MetaTrader 5 (Fill these in later)
MT5_LOGIN=
MT5_PASSWORD=
MT5_SERVER=
MT5_PATH=C:\Program Files\MetaTrader 5\terminal64.exe

# Trading Parameters
DEFAULT_SYMBOL=EURUSD
DEFAULT_TIMEFRAME=H1
DEFAULT_RISK_PERCENT=2.0
MAX_RISK_PERCENT=5.0
MIN_CONFLUENCE_SCORE=6

# Database (SQLite for development)
DATABASE_URL=sqlite:///./trading.db

# For production, use PostgreSQL:
# DATABASE_URL=postgresql://postgres:yourpassword@localhost:5432/institutional_edge

# Redis (Optional)
REDIS_HOST=localhost
REDIS_PORT=6379

# CORS (Frontend URLs)
CORS_ORIGINS=http://localhost:3000,http://localhost:5173,http://localhost:8080

# Logging
LOG_LEVEL=INFO
LOG_FILE=logs/trading.log
```

**⚠️ IMPORTANT:** Never commit `.env` to Git!

Create `.gitignore`:
```
.env
venv/
__pycache__/
*.pyc
node_modules/
dist/
*.db
logs/
.DS_Store
```

---

## ✅ Phase 0 Checklist

- [ ] Python 3.10+ installed and verified
- [ ] MetaTrader 5 installed
- [ ] PostgreSQL installed
- [ ] Node.js and npm installed
- [ ] Code editor (VS Code) set up
- [ ] Project structure created
- [ ] Virtual environment created and activated
- [ ] All Python packages installed
- [ ] .env file created
- [ ] .gitignore created

**If all checked, proceed to Phase 1! 🚀**

---

# PHASE 1: Backend Core - Trading Engine

**⏱️ Time Required:** 1 week
**Goal:** Build the core trading logic that analyzes markets and generates signals

---

## Step 1.1: Understand the Trading Logic

**Before coding, understand what we're building:**

The trading engine implements **Smart Money Concepts**:

1. **Order Blocks (OB):**
   - Last down candle before big up move = Bullish OB
   - Last up candle before big down move = Bearish OB
   - Institutions accumulate here

2. **Fair Value Gaps (FVG):**
   - Price gaps that weren't filled
   - Bullish FVG: Gap between high[2] and low[0]
   - Bearish FVG: Gap between low[2] and high[0]

3. **Market Structure:**
   - Higher Highs + Higher Lows = Uptrend
   - Lower Highs + Lower Lows = Downtrend
   - Break of Structure (BOS) = Continuation
   - Change of Character (CHOCH) = Reversal

4. **Volume Profile:**
   - POC (Point of Control) = Highest volume price
   - Value Area = 70% of volume
   - High/Low Volume Nodes

5. **Confluence Scoring:**
   - Combine all factors
   - Score 0-10
   - Signal when score ≥ threshold

---

## Step 1.2: Create Data Structures

Create `backend/app/core/trading_engine.py`:

```python
"""
Trading Engine - Core Logic
"""

from dataclasses import dataclass
from datetime import datetime
from typing import List, Dict, Optional

@dataclass
class OrderBlock:
    """Represents an institutional Order Block"""
    top: float              # Highest price of OB
    bottom: float           # Lowest price of OB
    start_time: datetime    # When OB formed
    is_bullish: bool        # True = buy zone, False = sell zone
    is_mitigated: bool      # Has price returned and invalidated it?
    volume: float           # Volume when OB formed
    bar_index: int          # Index in price data

@dataclass
class FairValueGap:
    """Represents an unfilled price gap"""
    top: float
    bottom: float
    start_time: datetime
    is_bullish: bool
    is_filled: bool         # Has price filled the gap?
    bar_index: int

@dataclass
class SwingPoint:
    """Swing high or low point"""
    price: float
    time: datetime
    is_high: bool           # True = swing high, False = swing low
    bar_index: int

@dataclass
class TradingSignal:
    """Generated trading signal with all details"""
    signal_type: str        # "BUY" or "SELL"
    entry_price: float
    stop_loss: float
    take_profit_1: float
    take_profit_2: float
    take_profit_3: float
    confluence_score: int   # 0-10
    score_breakdown: Dict[str, int]  # Why this score?
    timestamp: datetime
    symbol: str
    timeframe: str
    risk_reward_ratio: float
```

**Why these classes?**
- Clean data organization
- Type safety
- Easy to test
- Self-documenting code

---

## Step 1.3: Build the Trading Engine Class

Add to `trading_engine.py`:

```python
import pandas as pd
import numpy as np
from loguru import logger

class TradingEngine:
    """
    Core trading logic implementing Institutional Edge Pro strategy
    """

    def __init__(self, config: Dict):
        """Initialize with configuration"""
        self.config = config

        # Parameters
        self.swing_length = config.get('swing_length', 10)
        self.ob_lookback = config.get('ob_lookback', 50)
        self.fvg_min_size_atr = config.get('fvg_min_size', 0.3)
        self.min_confluence_score = config.get('min_confluence_score', 6)

        # Storage
        self.bullish_obs: List[OrderBlock] = []
        self.bearish_obs: List[OrderBlock] = []
        self.bullish_fvgs: List[FairValueGap] = []
        self.bearish_fvgs: List[FairValueGap] = []
        self.swing_highs: List[SwingPoint] = []
        self.swing_lows: List[SwingPoint] = []

        # State
        self.trend_bullish = True
        self.poc_level = None

        logger.info("Trading Engine initialized")

    def analyze(self, df: pd.DataFrame) -> Dict:
        """
        Main analysis function

        Args:
            df: DataFrame with columns: time, open, high, low, close, volume

        Returns:
            Dictionary with analysis results and signals
        """
        # Validate input
        if len(df) < 100:
            return {"error": "Need at least 100 bars"}

        # Calculate indicators
        df = self._calculate_indicators(df)

        # Detect patterns
        self._detect_swing_points(df)
        self._update_market_structure(df)
        self._detect_order_blocks(df)
        self._detect_fair_value_gaps(df)

        # Volume analysis
        self._calculate_volume_profile(df)

        # Generate signals
        confluence_data = self._calculate_confluence(df)
        signals = self._generate_signals(df, confluence_data)

        return {
            "timestamp": df.iloc[-1]['time'],
            "current_price": df.iloc[-1]['close'],
            "trend": "BULLISH" if self.trend_bullish else "BEARISH",
            "active_order_blocks": len([ob for ob in self.bullish_obs + self.bearish_obs if not ob.is_mitigated]),
            "bull_confluence_score": confluence_data['bull_score'],
            "bear_confluence_score": confluence_data['bear_score'],
            "signals": signals,
        }
```

---

## Step 1.4: Implement Technical Indicators

Add these methods to `TradingEngine` class:

```python
def _calculate_indicators(self, df: pd.DataFrame) -> pd.DataFrame:
    """Calculate ATR and other indicators"""
    # Average True Range
    df['atr'] = self._calculate_atr(df, 14)

    # Average Volume
    df['avg_volume'] = df['volume'].rolling(window=20).mean()

    # Volume spikes
    df['volume_spike'] = df['volume'] > (df['avg_volume'] * 1.5)

    return df

def _calculate_atr(self, df: pd.DataFrame, period: int = 14) -> pd.Series:
    """Calculate Average True Range"""
    high = df['high']
    low = df['low']
    close = df['close']

    tr1 = high - low
    tr2 = abs(high - close.shift())
    tr3 = abs(low - close.shift())

    tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
    atr = tr.rolling(window=period).mean()

    return atr
```

**What this does:**
- ATR measures volatility (for stop losses)
- Volume analysis finds institutional activity
- Returns modified DataFrame with new columns

---

## Step 1.5: Implement Swing Point Detection

```python
def _detect_swing_points(self, df: pd.DataFrame):
    """Find swing highs and lows"""
    for i in range(self.swing_length, len(df) - self.swing_length):
        # Swing High: Current high > all surrounding highs
        is_swing_high = all(
            df.iloc[i]['high'] > df.iloc[i-j]['high']
            for j in range(1, self.swing_length + 1)
        ) and all(
            df.iloc[i]['high'] > df.iloc[i+j]['high']
            for j in range(1, self.swing_length + 1)
        )

        if is_swing_high:
            swing = SwingPoint(
                price=df.iloc[i]['high'],
                time=df.iloc[i]['time'],
                is_high=True,
                bar_index=i
            )
            self.swing_highs.append(swing)

        # Swing Low: Current low < all surrounding lows
        is_swing_low = all(
            df.iloc[i]['low'] < df.iloc[i-j]['low']
            for j in range(1, self.swing_length + 1)
        ) and all(
            df.iloc[i]['low'] < df.iloc[i+j]['low']
            for j in range(1, self.swing_length + 1)
        )

        if is_swing_low:
            swing = SwingPoint(
                price=df.iloc[i]['low'],
                time=df.iloc[i]['time'],
                is_high=False,
                bar_index=i
            )
            self.swing_lows.append(swing)

    # Keep only recent 50 swings
    if len(self.swing_highs) > 50:
        self.swing_highs = self.swing_highs[-50:]
    if len(self.swing_lows) > 50:
        self.swing_lows = self.swing_lows[-50:]
```

**Logic:**
- Swing high = High point surrounded by lower highs
- Swing low = Low point surrounded by higher lows
- These define support/resistance levels

---

## Step 1.6: Implement Order Block Detection

```python
def _detect_order_blocks(self, df: pd.DataFrame):
    """Detect institutional order blocks"""
    # Clear old mitigated OBs
    self.bullish_obs = [ob for ob in self.bullish_obs if not ob.is_mitigated]
    self.bearish_obs = [ob for ob in self.bearish_obs if not ob.is_mitigated]

    # Look for new OBs
    for i in range(len(df) - 3, len(df) - 2):
        # Bullish OB Pattern:
        # 1. Down candle (close < open)
        # 2. Up candle next
        # 3. Price breaks above down candle's high
        # 4. High volume on down candle
        if (df.iloc[i]['close'] < df.iloc[i]['open'] and  # Down candle
            df.iloc[i+1]['close'] > df.iloc[i+1]['open'] and  # Up candle
            df.iloc[i+2]['close'] > df.iloc[i]['high'] and  # Break high
            df.iloc[i]['volume'] > df.iloc[i]['avg_volume']):  # Volume

            ob = OrderBlock(
                top=df.iloc[i]['high'],
                bottom=df.iloc[i]['low'],
                start_time=df.iloc[i]['time'],
                is_bullish=True,
                is_mitigated=False,
                volume=df.iloc[i]['volume'],
                bar_index=i
            )
            self.bullish_obs.append(ob)

        # Bearish OB Pattern (opposite)
        if (df.iloc[i]['close'] > df.iloc[i]['open'] and
            df.iloc[i+1]['close'] < df.iloc[i+1]['open'] and
            df.iloc[i+2]['close'] < df.iloc[i]['low'] and
            df.iloc[i]['volume'] > df.iloc[i]['avg_volume']):

            ob = OrderBlock(
                top=df.iloc[i]['high'],
                bottom=df.iloc[i]['low'],
                start_time=df.iloc[i]['time'],
                is_bullish=False,
                is_mitigated=False,
                volume=df.iloc[i]['volume'],
                bar_index=i
            )
            self.bearish_obs.append(ob)

    # Check for mitigation
    current_close = df.iloc[-1]['close']
    for ob in self.bullish_obs:
        if current_close < ob.bottom:
            ob.is_mitigated = True
    for ob in self.bearish_obs:
        if current_close > ob.top:
            ob.is_mitigated = True
```

**Order Block Logic:**
- Institutions place large orders creating these zones
- Last candle before reversal = order block
- Once broken, it's "mitigated" (invalid)

---

## Step 1.7: Implement Fair Value Gap Detection

```python
def _detect_fair_value_gaps(self, df: pd.DataFrame):
    """Detect price imbalances (FVGs)"""
    fvg_min_size = df.iloc[-1]['atr'] * self.fvg_min_size_atr

    for i in range(len(df) - 3, len(df) - 1):
        # Bullish FVG: Gap between candle[i-2] high and candle[i] low
        bull_top = df.iloc[i]['low']
        bull_bottom = df.iloc[i-2]['high']

        if bull_bottom < bull_top and (bull_top - bull_bottom) > fvg_min_size:
            fvg = FairValueGap(
                top=bull_top,
                bottom=bull_bottom,
                start_time=df.iloc[i-1]['time'],
                is_bullish=True,
                is_filled=False,
                bar_index=i-1
            )
            self.bullish_fvgs.append(fvg)

        # Bearish FVG: Gap between candle[i] high and candle[i-2] low
        bear_top = df.iloc[i-2]['low']
        bear_bottom = df.iloc[i]['high']

        if bear_bottom < bear_top and (bear_top - bear_bottom) > fvg_min_size:
            fvg = FairValueGap(
                top=bear_top,
                bottom=bear_bottom,
                start_time=df.iloc[i-1]['time'],
                is_bullish=False,
                is_filled=False,
                bar_index=i-1
            )
            self.bearish_fvgs.append(fvg)

    # Check for fills
    current_low = df.iloc[-1]['low']
    current_high = df.iloc[-1]['high']

    for fvg in self.bullish_fvgs:
        if current_low <= fvg.bottom:
            fvg.is_filled = True
    for fvg in self.bearish_fvgs:
        if current_high >= fvg.top:
            fvg.is_filled = True
```

**FVG Logic:**
- Price moves so fast it leaves gaps
- These gaps often get "filled" later
- Prime entry zones when combined with other factors

---

## Step 1.8: Implement Volume Profile

```python
def _calculate_volume_profile(self, df: pd.DataFrame):
    """Calculate POC and Value Area"""
    lookback = min(100, len(df))
    recent_df = df.tail(lookback)

    highest = recent_df['high'].max()
    lowest = recent_df['low'].min()
    rows = 24
    row_height = (highest - lowest) / rows

    # Build volume distribution
    volume_at_price = np.zeros(rows)

    for idx, candle in recent_df.iterrows():
        for i in range(rows):
            row_low = lowest + (i * row_height)
            row_high = row_low + row_height

            # Calculate overlap
            if candle['low'] <= row_high and candle['high'] >= row_low:
                overlap = min(candle['high'], row_high) - max(candle['low'], row_low)
                candle_range = candle['high'] - candle['low']
                if candle_range > 0:
                    volume_at_price[i] += candle['volume'] * (overlap / candle_range)

    # Find POC (Point of Control)
    max_volume_row = np.argmax(volume_at_price)
    self.poc_level = lowest + (max_volume_row * row_height) + (row_height / 2)
```

**Volume Profile Logic:**
- Divides price range into rows
- Distributes volume to each price level
- POC = Price with most volume
- Where institutions are most active

---

## Step 1.9: Implement Confluence Scoring

```python
def _calculate_confluence(self, df: pd.DataFrame) -> Dict:
    """Score the setup quality (0-10)"""
    bull_score = 0
    bear_score = 0
    bull_breakdown = {}
    bear_breakdown = {}

    current_price = df.iloc[-1]['close']
    current_low = df.iloc[-1]['low']
    current_high = df.iloc[-1]['high']
    atr = df.iloc[-1]['atr']

    # 1. Order Block (+2 points)
    at_bullish_ob = any(
        ob.bottom <= current_low <= ob.top
        for ob in self.bullish_obs if not ob.is_mitigated
    )
    if at_bullish_ob:
        bull_score += 2
        bull_breakdown['Order Block'] = 2

    at_bearish_ob = any(
        ob.bottom <= current_high <= ob.top
        for ob in self.bearish_obs if not ob.is_mitigated
    )
    if at_bearish_ob:
        bear_score += 2
        bear_breakdown['Order Block'] = 2

    # 2. Fair Value Gap (+2 points)
    at_bullish_fvg = any(
        fvg.bottom <= current_price <= fvg.top
        for fvg in self.bullish_fvgs if not fvg.is_filled
    )
    if at_bullish_fvg:
        bull_score += 2
        bull_breakdown['FVG'] = 2

    at_bearish_fvg = any(
        fvg.bottom <= current_price <= fvg.top
        for fvg in self.bearish_fvgs if not fvg.is_filled
    )
    if at_bearish_fvg:
        bear_score += 2
        bear_breakdown['FVG'] = 2

    # 3. Trend Alignment (+2 points)
    if self.trend_bullish:
        bull_score += 2
        bull_breakdown['Trend'] = 2
    else:
        bear_score += 2
        bear_breakdown['Trend'] = 2

    # 4. Premium/Discount Zone (+2 points)
    if self.swing_highs and self.swing_lows:
        last_high = self.swing_highs[-1].price
        last_low = self.swing_lows[-1].price
        equilibrium = (last_high + last_low) / 2

        if current_price < equilibrium:  # Discount = buy zone
            bull_score += 2
            bull_breakdown['Discount Zone'] = 2
        else:  # Premium = sell zone
            bear_score += 2
            bear_breakdown['Premium Zone'] = 2

    # 5. POC Proximity (+1 point)
    if self.poc_level and abs(current_price - self.poc_level) < atr * 0.5:
        bull_score += 1
        bear_score += 1
        bull_breakdown['Near POC'] = 1
        bear_breakdown['Near POC'] = 1

    # 6. Volume Confirmation (+1 point)
    if df.iloc[-1]['volume_spike']:
        if df.iloc[-1]['close'] > df.iloc[-1]['open']:
            bull_score += 1
            bull_breakdown['Volume'] = 1
        else:
            bear_score += 1
            bear_breakdown['Volume'] = 1

    # Normalize to 0-10
    bull_score = min(bull_score, 10)
    bear_score = min(bear_score, 10)

    return {
        'bull_score': bull_score,
        'bear_score': bear_score,
        'bull_breakdown': bull_breakdown,
        'bear_breakdown': bear_breakdown
    }
```

**Confluence Scoring:**
- Each factor adds points
- Maximum 10 points
- Higher score = Higher probability
- Breakdown shows WHY (transparency)

---

## Step 1.10: Generate Trading Signals

```python
def _generate_signals(self, df: pd.DataFrame, confluence: Dict) -> List[TradingSignal]:
    """Create trading signals when score is high enough"""
    signals = []

    bull_score = confluence['bull_score']
    bear_score = confluence['bear_score']
    current_price = df.iloc[-1]['close']
    atr = df.iloc[-1]['atr']

    # Bull Signal
    if bull_score >= self.min_confluence_score and self.trend_bullish:
        stop_loss = current_price - (atr * 1.5)
        risk = current_price - stop_loss

        signal = TradingSignal(
            signal_type="BUY",
            entry_price=current_price,
            stop_loss=stop_loss,
            take_profit_1=current_price + (risk * 1.0),  # 1:1 RR
            take_profit_2=current_price + (risk * 2.0),  # 1:2 RR
            take_profit_3=current_price + (risk * 3.0),  # 1:3 RR
            confluence_score=bull_score,
            score_breakdown=confluence['bull_breakdown'],
            timestamp=df.iloc[-1]['time'],
            symbol=self.config.get('symbol', 'UNKNOWN'),
            timeframe=self.config.get('timeframe', 'UNKNOWN'),
            risk_reward_ratio=2.0
        )
        signals.append(signal)

    # Bear Signal
    if bear_score >= self.min_confluence_score and not self.trend_bullish:
        stop_loss = current_price + (atr * 1.5)
        risk = stop_loss - current_price

        signal = TradingSignal(
            signal_type="SELL",
            entry_price=current_price,
            stop_loss=stop_loss,
            take_profit_1=current_price - (risk * 1.0),
            take_profit_2=current_price - (risk * 2.0),
            take_profit_3=current_price - (risk * 3.0),
            confluence_score=bear_score,
            score_breakdown=confluence['bear_breakdown'],
            timestamp=df.iloc[-1]['time'],
            symbol=self.config.get('symbol', 'UNKNOWN'),
            timeframe=self.config.get('timeframe', 'UNKNOWN'),
            risk_reward_ratio=2.0
        )
        signals.append(signal)

    return signals
```

**Signal Generation:**
- Only when confluence score ≥ threshold
- Must align with trend
- Dynamic stop loss based on ATR
- Multiple take profit levels
- 2:1 minimum risk:reward

---

## ✅ Phase 1 Checklist

Test your trading engine:

Create `test_engine.py`:

```python
import sys
sys.path.append('backend/app')

from core.trading_engine import TradingEngine
import pandas as pd
import numpy as np
from datetime import datetime, timedelta

# Generate sample data
dates = pd.date_range(start=datetime.now() - timedelta(days=500), periods=500, freq='H')
close = 1.0850 + np.cumsum(np.random.randn(500) * 0.0001)
high = close + np.random.rand(500) * 0.0005
low = close - np.random.rand(500) * 0.0005
open_price = close + (np.random.rand(500) - 0.5) * 0.0003
volume = np.random.randint(1000, 10000, 500)

df = pd.DataFrame({
    'time': dates,
    'open': open_price,
    'high': high,
    'low': low,
    'close': close,
    'volume': volume
})

# Test engine
config = {
    'symbol': 'EURUSD',
    'timeframe': 'H1',
    'swing_length': 10,
    'ob_lookback': 50,
    'fvg_min_size': 0.3,
    'min_confluence_score': 6,
}

engine = TradingEngine(config)
result = engine.analyze(df)

print("✅ Trading Engine Working!")
print(f"Bull Score: {result['bull_confluence_score']}/10")
print(f"Bear Score: {result['bear_confluence_score']}/10")
print(f"Signals: {len(result['signals'])}")
```

Run:
```bash
python test_engine.py
```

**Expected output:**
```
✅ Trading Engine Working!
Bull Score: 7/10
Bear Score: 3/10
Signals: 1
```

- [ ] trading_engine.py created
- [ ] All dataclasses defined
- [ ] TradingEngine class created
- [ ] All indicator methods working
- [ ] Swing detection working
- [ ] Order block detection working
- [ ] FVG detection working
- [ ] Volume profile working
- [ ] Confluence scoring working
- [ ] Signal generation working
- [ ] Test script passes

**If all checked, move to Phase 2! 🎯**

---

# PHASE 2: MT5 Integration

**⏱️ Time Required:** 3-4 days
**Goal:** Connect to MetaTrader 5 and execute trades

---

## Step 2.1: Understand MT5 Python API

The `MetaTrader5` library allows Python to:
- ✅ Connect to MT5 terminal
- ✅ Get market data (OHLCV)
- ✅ Get account info (balance, equity)
- ✅ Open/close positions
- ✅ Modify orders
- ✅ Get positions and history

**Important:** MT5 terminal must be running!

---

## Step 2.2: Test MT5 Connection

Create `test_mt5.py`:

```python
import MetaTrader5 as mt5

print("Testing MT5 connection...")

# Initialize
if not mt5.initialize():
    print("❌ Failed to initialize MT5")
    print(f"Error: {mt5.last_error()}")
    quit()

print("✅ MT5 initialized!")

# Get terminal info
terminal_info = mt5.terminal_info()
if terminal_info:
    print(f"\nTerminal: {terminal_info.name}")
    print(f"Build: {terminal_info.build}")
    print(f"Path: {terminal_info.path}")

# Get account info
account_info = mt5.account_info()
if account_info:
    print(f"\nAccount #{account_info.login}")
    print(f"Balance: ${account_info.balance:.2f}")
    print(f"Equity: ${account_info.equity:.2f}")
    print(f"Leverage: 1:{account_info.leverage}")

# Get symbols
symbols = mt5.symbols_total()
print(f"\nTotal symbols: {symbols}")

# Test getting data
rates = mt5.copy_rates_from_pos("EURUSD", mt5.TIMEFRAME_H1, 0, 10)
if rates is not None:
    print(f"\n✅ Successfully got {len(rates)} bars of EURUSD H1 data")
    print(f"Latest close: {rates[-1]['close']:.5f}")
else:
    print("\n⚠️  Failed to get rates")

mt5.shutdown()
print("\n✅ MT5 test complete!")
```

Run:
```bash
# Make sure MT5 is running and logged in first!
python test_mt5.py
```

**Troubleshooting:**
- "Failed to initialize" → MT5 not running
- "No data" → Symbol not available or wrong name
- "Connection error" → Check internet connection

---

## Step 2.3: Create MT5 Connector Class

Create `backend/app/core/mt5_connector.py`:

```python
"""
MT5 Integration Layer
"""

import MetaTrader5 as mt5
import pandas as pd
from typing import Optional, List, Dict
from datetime import datetime
from loguru import logger


class MT5Connector:
    """Handle all MT5 operations"""

    # Timeframe mapping
    TIMEFRAMES = {
        'M1': mt5.TIMEFRAME_M1,
        'M5': mt5.TIMEFRAME_M5,
        'M15': mt5.TIMEFRAME_M15,
        'M30': mt5.TIMEFRAME_M30,
        'H1': mt5.TIMEFRAME_H1,
        'H4': mt5.TIMEFRAME_H4,
        'D1': mt5.TIMEFRAME_D1,
        'W1': mt5.TIMEFRAME_W1,
    }

    def __init__(self, config: Dict):
        """Initialize connector"""
        self.config = config
        self.connected = False

    def connect(self) -> bool:
        """Connect to MT5"""
        try:
            # Initialize MT5
            path = self.config.get('mt5_path')
            if path:
                if not mt5.initialize(path=path):
                    logger.error("MT5 init failed: {}", mt5.last_error())
                    return False
            else:
                if not mt5.initialize():
                    logger.error("MT5 init failed: {}", mt5.last_error())
                    return False

            # Login if credentials provided
            login = self.config.get('mt5_login')
            password = self.config.get('mt5_password')
            server = self.config.get('mt5_server')

            if login and password and server:
                if not mt5.login(int(login), password, server):
                    logger.error("MT5 login failed: {}", mt5.last_error())
                    mt5.shutdown()
                    return False

                logger.info("Logged in to MT5 account: {}", login)

            self.connected = True
            logger.info("MT5 connected successfully")

            # Log account info
            account = mt5.account_info()
            if account:
                logger.info("Balance: ${:.2f}, Equity: ${:.2f}",
                          account.balance, account.equity)

            return True

        except Exception as e:
            logger.exception("MT5 connection error: {}", e)
            return False

    def disconnect(self):
        """Disconnect from MT5"""
        if self.connected:
            mt5.shutdown()
            self.connected = False
            logger.info("MT5 disconnected")
```

---

## Step 2.4: Implement Data Retrieval

Add to `MT5Connector` class:

```python
def get_ohlcv_data(
    self,
    symbol: str,
    timeframe: str,
    bars: int = 500
) -> Optional[pd.DataFrame]:
    """
    Get OHLCV data from MT5

    Args:
        symbol: e.g. "EURUSD"
        timeframe: e.g. "H1"
        bars: Number of bars

    Returns:
        DataFrame with: time, open, high, low, close, volume
    """
    if not self.connected:
        logger.error("Not connected to MT5")
        return None

    try:
        # Get MT5 timeframe constant
        mt5_tf = self.TIMEFRAMES.get(timeframe)
        if not mt5_tf:
            logger.error("Invalid timeframe: {}", timeframe)
            return None

        # Fetch data
        rates = mt5.copy_rates_from_pos(symbol, mt5_tf, 0, bars)

        if rates is None or len(rates) == 0:
            logger.error("Failed to get rates for {}", symbol)
            return None

        # Convert to DataFrame
        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        df = df.rename(columns={'tick_volume': 'volume'})

        logger.debug("Fetched {} bars for {} {}", len(df), symbol, timeframe)

        return df[['time', 'open', 'high', 'low', 'close', 'volume']]

    except Exception as e:
        logger.exception("Error fetching data: {}", e)
        return None

def get_current_price(self, symbol: str) -> Optional[Dict]:
    """Get current bid/ask prices"""
    if not self.connected:
        return None

    try:
        tick = mt5.symbol_info_tick(symbol)
        if not tick:
            return None

        return {
            'symbol': symbol,
            'bid': tick.bid,
            'ask': tick.ask,
            'time': datetime.fromtimestamp(tick.time),
            'spread': tick.ask - tick.bid
        }
    except Exception as e:
        logger.exception("Error getting price: {}", e)
        return None
```

---

## Step 2.5: Implement Trading Operations

Add to `MT5Connector`:

```python
def open_position(
    self,
    symbol: str,
    order_type: str,  # "BUY" or "SELL"
    volume: float,
    stop_loss: Optional[float] = None,
    take_profit: Optional[float] = None,
    comment: str = "Institutional Edge Pro"
) -> Optional[Dict]:
    """Open a trading position"""
    if not self.connected:
        logger.error("Not connected to MT5")
        return None

    try:
        # Get symbol info
        symbol_info = mt5.symbol_info(symbol)
        if not symbol_info:
            logger.error("Symbol {} not found", symbol)
            return None

        # Enable symbol if not visible
        if not symbol_info.visible:
            if not mt5.symbol_select(symbol, True):
                logger.error("Failed to select symbol {}", symbol)
                return None

        # Get current price
        tick = mt5.symbol_info_tick(symbol)
        if not tick:
            logger.error("Failed to get tick for {}", symbol)
            return None

        # Prepare order
        order_type_mt5 = mt5.ORDER_TYPE_BUY if order_type == "BUY" else mt5.ORDER_TYPE_SELL
        price = tick.ask if order_type == "BUY" else tick.bid

        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": symbol,
            "volume": volume,
            "type": order_type_mt5,
            "price": price,
            "deviation": 20,
            "magic": 234000,  # Unique identifier
            "comment": comment,
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }

        # Add SL/TP if provided
        if stop_loss:
            request["sl"] = stop_loss
        if take_profit:
            request["tp"] = take_profit

        # Send order
        result = mt5.order_send(request)

        if result.retcode != mt5.TRADE_RETCODE_DONE:
            logger.error("Order failed: {} - {}", result.retcode, result.comment)
            return None

        logger.info("✅ Order opened: {} {} {} @ {}",
                   order_type, symbol, volume, result.price)

        return {
            "success": True,
            "ticket": result.order,
            "volume": result.volume,
            "price": result.price,
            "order_type": order_type,
            "symbol": symbol,
        }

    except Exception as e:
        logger.exception("Error opening position: {}", e)
        return None

def close_position(self, ticket: int) -> bool:
    """Close a position by ticket number"""
    if not self.connected:
        return False

    try:
        # Get position
        position = mt5.positions_get(ticket=ticket)
        if not position or len(position) == 0:
            logger.error("Position {} not found", ticket)
            return False

        position = position[0]

        # Prepare close request (opposite direction)
        order_type = mt5.ORDER_TYPE_SELL if position.type == mt5.ORDER_TYPE_BUY else mt5.ORDER_TYPE_BUY
        price = mt5.symbol_info_tick(position.symbol).bid if position.type == mt5.ORDER_TYPE_BUY else mt5.symbol_info_tick(position.symbol).ask

        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": position.symbol,
            "volume": position.volume,
            "type": order_type,
            "position": ticket,
            "price": price,
            "deviation": 20,
            "magic": 234000,
            "comment": "Close",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }

        result = mt5.order_send(request)

        if result.retcode != mt5.TRADE_RETCODE_DONE:
            logger.error("Failed to close {}: {}", ticket, result.retcode)
            return False

        logger.info("✅ Position {} closed", ticket)
        return True

    except Exception as e:
        logger.exception("Error closing position: {}", e)
        return False

def get_open_positions(self, symbol: Optional[str] = None) -> List[Dict]:
    """Get all open positions"""
    if not self.connected:
        return []

    try:
        if symbol:
            positions = mt5.positions_get(symbol=symbol)
        else:
            positions = mt5.positions_get()

        if not positions:
            return []

        result = []
        for pos in positions:
            result.append({
                'ticket': pos.ticket,
                'symbol': pos.symbol,
                'type': 'BUY' if pos.type == mt5.ORDER_TYPE_BUY else 'SELL',
                'volume': pos.volume,
                'price_open': pos.price_open,
                'price_current': pos.price_current,
                'sl': pos.sl,
                'tp': pos.tp,
                'profit': pos.profit,
                'time': datetime.fromtimestamp(pos.time),
            })

        return result

    except Exception as e:
        logger.exception("Error getting positions: {}", e)
        return []
```

---

## Step 2.6: Test MT5 Connector

Create `test_mt5_connector.py`:

```python
import sys
sys.path.append('backend/app')

from core.mt5_connector import MT5Connector

# Configure
config = {
    'mt5_login': '',  # Leave empty to use current login
    'mt5_password': '',
    'mt5_server': '',
    'mt5_path': 'C:\\Program Files\\MetaTrader 5\\terminal64.exe',
}

# Create connector
connector = MT5Connector(config)

# Test connection
print("Testing MT5 Connector...")
if connector.connect():
    print("✅ Connected!")

    # Test getting data
    df = connector.get_ohlcv_data('EURUSD', 'H1', bars=100)
    if df is not None:
        print(f"\n✅ Got {len(df)} bars of data")
        print(f"Latest close: {df.iloc[-1]['close']:.5f}")

    # Test getting price
    price = connector.get_current_price('EURUSD')
    if price:
        print(f"\n✅ Current EURUSD price:")
        print(f"   Bid: {price['bid']:.5f}")
        print(f"   Ask: {price['ask']:.5f}")

    # Test getting positions
    positions = connector.get_open_positions()
    print(f"\n✅ Open positions: {len(positions)}")

    connector.disconnect()
    print("\n✅ All tests passed!")
else:
    print("❌ Failed to connect")
```

Run (with MT5 open):
```bash
python test_mt5_connector.py
```

---

## ✅ Phase 2 Checklist

- [ ] MT5 installed and logged in
- [ ] test_mt5.py passes
- [ ] mt5_connector.py created
- [ ] Connection method works
- [ ] Data retrieval works
- [ ] Price fetching works
- [ ] Position opening works (tested on demo!)
- [ ] Position closing works
- [ ] Get positions works
- [ ] test_mt5_connector.py passes

**If all checked, move to Phase 3! 🚀**

---

# PHASE 3: Database Setup

**⏱️ Time Required:** 2-3 days
**Goal:** Set up PostgreSQL database and SQLAlchemy models

---

## Step 3.1: Create Database

```bash
# Start PostgreSQL service
# Windows: Should auto-start
# Mac: brew services start postgresql
# Linux: sudo service postgresql start

# Create database
createdb institutional_edge

# Or using psql:
psql -U postgres
CREATE DATABASE institutional_edge;
\q
```

---

## Step 3.2: Create Database Models

Create `backend/app/models/database.py`:

```python
"""
Database Models
"""

from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, JSON, ForeignKey
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship
from datetime import datetime

Base = declarative_base()


class User(Base):
    """User accounts"""
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    username = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    is_active = Column(Boolean, default=True)
    is_admin = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    bot_configs = relationship("BotConfig", back_populates="user")
    trades = relationship("Trade", back_populates="user")


class BotConfig(Base):
    """Bot configuration per user"""
    __tablename__ = "bot_configs"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    name = Column(String, nullable=False)

    # MT5 Config
    mt5_login = Column(String)
    mt5_server = Column(String)

    # Trading Parameters
    symbol = Column(String, default="EURUSD")
    timeframe = Column(String, default="H1")
    risk_percent = Column(Float, default=2.0)
    min_confluence_score = Column(Integer, default=6)
    max_trades = Column(Integer, default=3)

    # Bot Status
    is_active = Column(Boolean, default=False)
    last_signal_time = Column(DateTime)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    user = relationship("User", back_populates="bot_configs")


class Trade(Base):
    """Trade execution records"""
    __tablename__ = "trades"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)

    # Trade Details
    ticket = Column(Integer, unique=True)  # MT5 ticket
    symbol = Column(String, nullable=False)
    trade_type = Column(String, nullable=False)  # "BUY" or "SELL"

    # Prices
    entry_price = Column(Float, nullable=False)
    stop_loss = Column(Float)
    take_profit_1 = Column(Float)
    take_profit_2 = Column(Float)
    take_profit_3 = Column(Float)
    exit_price = Column(Float)

    # Volume & Risk
    volume = Column(Float, nullable=False)
    risk_percent = Column(Float, nullable=False)

    # Confluence
    confluence_score = Column(Integer, nullable=False)
    score_breakdown = Column(JSON)

    # Status
    status = Column(String, default="OPEN")  # OPEN, CLOSED, CANCELLED
    profit_loss = Column(Float, default=0.0)

    # Timestamps
    opened_at = Column(DateTime, default=datetime.utcnow)
    closed_at = Column(DateTime)

    # Relationships
    user = relationship("User", back_populates="trades")


class Signal(Base):
    """Trading signal history"""
    __tablename__ = "signals"

    id = Column(Integer, primary_key=True, index=True)

    symbol = Column(String, nullable=False)
    timeframe = Column(String, nullable=False)
    signal_type = Column(String, nullable=False)

    price = Column(Float, nullable=False)
    stop_loss = Column(Float, nullable=False)
    take_profit = Column(Float, nullable=False)

    confluence_score = Column(Integer, nullable=False)
    score_breakdown = Column(JSON)

    trend = Column(String, nullable=False)
    poc_level = Column(Float)

    was_executed = Column(Boolean, default=False)
    trade_id = Column(Integer, ForeignKey("trades.id"))

    created_at = Column(DateTime, default=datetime.utcnow)
```

---

## Step 3.3: Create Database Connection

Create `backend/app/api/database.py`:

```python
"""
Database Connection
"""

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from typing import Generator
from app.core.config import settings
from app.models.database import Base


# Create engine
engine = create_engine(
    settings.DATABASE_URL,
    pool_pre_ping=True,  # Verify connections
)

# Session factory
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def init_db():
    """Create all tables"""
    Base.metadata.create_all(bind=engine)


def get_db() -> Generator[Session, None, None]:
    """
    Dependency for getting DB session

    Usage:
        def endpoint(db: Session = Depends(get_db)):
            # Use db here
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

---

## Step 3.4: Initialize Database

Create `init_db.py`:

```python
import sys
sys.path.append('backend/app')

from api.database import init_db
from loguru import logger

logger.info("Initializing database...")
init_db()
logger.info("✅ Database initialized!")
```

Run:
```bash
python init_db.py
```

**Verify:** Check PostgreSQL:
```bash
psql -U postgres -d institutional_edge

\dt  # List tables

# You should see:
# users
# bot_configs
# trades
# signals
```

---

## ✅ Phase 3 Checklist

- [ ] PostgreSQL installed and running
- [ ] Database created
- [ ] database.py models created
- [ ] database.py connection created
- [ ] Tables created successfully
- [ ] Can connect to database
- [ ] Can query tables

**Move to Phase 4! 💾**

---

# PHASE 4: FastAPI Backend

**⏱️ Time Required:** 1 week
**Goal:** Build complete REST API

---

## Step 4.1: Create Configuration

Create `backend/app/core/config.py`:

```python
"""
Application Configuration
"""

from pydantic_settings import BaseSettings
from typing import List


class Settings(BaseSettings):
    APP_NAME: str = "Institutional Edge Pro"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = True
    SECRET_KEY: str

    # Server
    HOST: str = "0.0.0.0"
    PORT: int = 8000

    # MT5
    MT5_LOGIN: str = ""
    MT5_PASSWORD: str = ""
    MT5_SERVER: str = ""
    MT5_PATH: str = ""

    # Trading
    DEFAULT_SYMBOL: str = "EURUSD"
    DEFAULT_TIMEFRAME: str = "H1"
    DEFAULT_RISK_PERCENT: float = 2.0
    MIN_CONFLUENCE_SCORE: int = 6

    # Database
    DATABASE_URL: str

    # CORS
    CORS_ORIGINS: str = "http://localhost:3000,http://localhost:5173"

    @property
    def cors_origins_list(self) -> List[str]:
        return [o.strip() for o in self.CORS_ORIGINS.split(",")]

    # JWT
    JWT_SECRET_KEY: str
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30

    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
```

---

## Step 4.2: Create Pydantic Schemas

Create `backend/app/schemas/schemas.py`:

```python
"""
Pydantic Schemas for Request/Response Validation
"""

from pydantic import BaseModel, EmailStr, Field
from typing import Optional, List, Dict
from datetime import datetime


# User Schemas
class UserCreate(BaseModel):
    email: EmailStr
    username: str
    password: str


class UserResponse(BaseModel):
    id: int
    email: str
    username: str
    is_active: bool
    created_at: datetime

    class Config:
        from_attributes = True


# Bot Config Schemas
class BotConfigCreate(BaseModel):
    name: str
    symbol: str = "EURUSD"
    timeframe: str = "H1"
    risk_percent: float = Field(default=2.0, ge=0.5, le=5.0)
    min_confluence_score: int = Field(default=6, ge=3, le=10)


class BotConfigResponse(BaseModel):
    id: int
    user_id: int
    name: str
    symbol: str
    timeframe: str
    risk_percent: float
    is_active: bool
    created_at: datetime

    class Config:
        from_attributes = True


# Signal Schemas
class SignalResponse(BaseModel):
    signal_type: str
    entry_price: float
    stop_loss: float
    take_profit_1: float
    take_profit_2: float
    confluence_score: int
    score_breakdown: Dict[str, int]
    timestamp: datetime
    symbol: str
    timeframe: str


class AnalysisResponse(BaseModel):
    timestamp: datetime
    current_price: float
    trend: str
    active_order_blocks: int
    bull_confluence_score: int
    bear_confluence_score: int
    bull_score_breakdown: Dict[str, int]
    bear_score_breakdown: Dict[str, int]
    signals: List[SignalResponse]


# Trade Schemas
class TradeResponse(BaseModel):
    id: int
    ticket: Optional[int]
    symbol: str
    trade_type: str
    entry_price: float
    stop_loss: Optional[float]
    volume: float
    confluence_score: int
    status: str
    profit_loss: float
    opened_at: datetime

    class Config:
        from_attributes = True


# Bot Control
class BotStartRequest(BaseModel):
    bot_config_id: int


class BotStatusResponse(BaseModel):
    bot_config_id: int
    is_active: bool
    symbol: str
    current_price: Optional[float]
    open_positions: int
    total_trades_today: int
    pnl_today: float
```

---

## Step 4.3: Create Main FastAPI App

Create `backend/app/main.py`:

```python
"""
FastAPI Main Application
"""

from fastapi import FastAPI, WebSocket, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from typing import List
import asyncio
from datetime import datetime
from loguru import logger

from app.core.config import settings
from app.core.trading_engine import TradingEngine
from app.core.mt5_connector import MT5Connector
from app.schemas import schemas
from app.models.database import BotConfig, Trade
from app.api import database

# Create app
app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global instances
mt5_connector: MT5Connector = None


@app.on_event("startup")
async def startup():
    """Initialize on startup"""
    logger.info("Starting API...")

    # Create tables
    database.init_db()

    # Connect to MT5
    global mt5_connector
    config = {
        'mt5_login': settings.MT5_LOGIN,
        'mt5_password': settings.MT5_PASSWORD,
        'mt5_server': settings.MT5_SERVER,
        'mt5_path': settings.MT5_PATH,
    }

    mt5_connector = MT5Connector(config)
    if settings.MT5_LOGIN:
        connected = mt5_connector.connect()
        if connected:
            logger.info("MT5 connected")
        else:
            logger.warning("MT5 not connected")

    logger.info("API started on {}:{}", settings.HOST, settings.PORT)


@app.on_event("shutdown")
async def shutdown():
    """Cleanup"""
    logger.info("Shutting down...")
    if mt5_connector:
        mt5_connector.disconnect()


# Root endpoint
@app.get("/")
async def root():
    return {
        "app": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "status": "running",
        "mt5_connected": mt5_connector.connected if mt5_connector else False,
    }


# Health check
@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow(),
    }


# Market analysis endpoint
@app.get("/api/analysis/{symbol}/{timeframe}", response_model=schemas.AnalysisResponse)
async def analyze_market(symbol: str, timeframe: str):
    """Analyze market and get signals"""
    if not mt5_connector or not mt5_connector.connected:
        raise HTTPException(status_code=503, detail="MT5 not connected")

    # Get data
    df = mt5_connector.get_ohlcv_data(symbol, timeframe, bars=500)
    if df is None:
        raise HTTPException(status_code=404, detail=f"No data for {symbol}")

    # Analyze
    config = {
        'symbol': symbol,
        'timeframe': timeframe,
        'swing_length': 10,
        'ob_lookback': 50,
        'fvg_min_size': 0.3,
        'min_confluence_score': settings.MIN_CONFLUENCE_SCORE,
    }

    engine = TradingEngine(config)
    analysis = engine.analyze(df)

    if 'error' in analysis:
        raise HTTPException(status_code=400, detail=analysis['error'])

    return analysis


# Get current price
@app.get("/api/mt5/price/{symbol}")
async def get_price(symbol: str):
    """Get current price"""
    if not mt5_connector or not mt5_connector.connected:
        raise HTTPException(status_code=503, detail="MT5 not connected")

    price = mt5_connector.get_current_price(symbol)
    if not price:
        raise HTTPException(status_code=404, detail=f"Symbol {symbol} not found")

    return price


# Get open positions
@app.get("/api/mt5/positions")
async def get_positions(symbol: str = None):
    """Get open positions"""
    if not mt5_connector or not mt5_connector.connected:
        raise HTTPException(status_code=503, detail="MT5 not connected")

    positions = mt5_connector.get_open_positions(symbol)
    return {"positions": positions, "count": len(positions)}


# Start bot
@app.post("/api/bot/start")
async def start_bot(
    request: schemas.BotStartRequest,
    db: Session = Depends(database.get_db)
):
    """Start trading bot"""
    bot = db.query(BotConfig).filter(BotConfig.id == request.bot_config_id).first()
    if not bot:
        raise HTTPException(status_code=404, detail="Bot not found")

    bot.is_active = True
    db.commit()

    logger.info("Bot {} started", bot.name)

    return {
        "success": True,
        "message": f"Bot {bot.name} started",
        "bot_config_id": bot.id,
    }


# Stop bot
@app.post("/api/bot/stop")
async def stop_bot(
    request: schemas.BotStartRequest,
    db: Session = Depends(database.get_db)
):
    """Stop trading bot"""
    bot = db.query(BotConfig).filter(BotConfig.id == request.bot_config_id).first()
    if not bot:
        raise HTTPException(status_code=404, detail="Bot not found")

    bot.is_active = False
    db.commit()

    logger.info("Bot {} stopped", bot.name)

    return {
        "success": True,
        "message": f"Bot {bot.name} stopped",
    }


# Get trades
@app.get("/api/trades", response_model=List[schemas.TradeResponse])
async def get_trades(
    limit: int = 50,
    db: Session = Depends(database.get_db)
):
    """Get trade history"""
    trades = db.query(Trade).order_by(Trade.opened_at.desc()).limit(limit).all()
    return trades


# WebSocket
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """Real-time updates"""
    await websocket.accept()

    try:
        while True:
            if mt5_connector and mt5_connector.connected:
                # Get account info
                account = mt5_connector.get_account_info()

                message = {
                    "type": "account_update",
                    "data": account,
                    "timestamp": datetime.utcnow().isoformat(),
                }

                await websocket.send_json(message)

            await asyncio.sleep(2)
    except:
        pass


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
    )
```

---

## Step 4.4: Test the API

```bash
cd backend/app
python main.py
```

**Open browser to:**
```
http://localhost:8000/docs
```

**You should see:**
- Interactive API documentation
- All endpoints listed
- Try them out!

**Test key endpoints:**

1. Health check:
   ```
   GET http://localhost:8000/health
   ```

2. Market analysis:
   ```
   GET http://localhost:8000/api/analysis/EURUSD/H1
   ```

3. Current price:
   ```
   GET http://localhost:8000/api/mt5/price/EURUSD
   ```

---

## ✅ Phase 4 Checklist

- [ ] config.py created
- [ ] schemas.py created
- [ ] main.py created
- [ ] API starts without errors
- [ ] Can access /docs
- [ ] Health check works
- [ ] Market analysis endpoint works
- [ ] Price endpoint works
- [ ] Bot start/stop works
- [ ] WebSocket connects

**Move to Phase 5! 🎉**

---

# PHASE 5: Frontend Dashboard

**⏱️ Time Required:** 1-2 weeks
**Goal:** Build Vue 3 dashboard

---

## Step 5.1: Initialize Vue Project

```bash
cd frontend

# Initialize with npm
npm init vue@latest

# Choose:
# ✔ Project name: institutional-edge-dashboard
# ✔ Add TypeScript? No
# ✔ Add JSX Support? No
# ✔ Add Vue Router? Yes
# ✔ Add Pinia? Yes
# ✔ Add Vitest? No
# ✔ Add End-to-End Testing? No
# ✔ Add ESLint? Yes
# ✔ Add Prettier? Yes

# Install dependencies
npm install

# Install additional packages
npm install axios chart.js vue-chartjs @headlessui/vue @heroicons/vue
npm install -D tailwindcss postcss autoprefixer

# Initialize Tailwind
npx tailwindcss init -p
```

---

## Step 5.2: Configure Tailwind CSS

Edit `tailwind.config.js`:

```javascript
/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{vue,js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
```

Create `src/assets/main.css`:

```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```

---

## Step 5.3: Create API Service

Create `src/services/api.js`:

```javascript
import axios from 'axios'

const API_BASE_URL = 'http://localhost:8000'

const api = axios.create({
  baseURL: API_BASE_URL,
  timeout: 10000,
})

export default {
  // Market Analysis
  async analyzeMarket(symbol, timeframe) {
    const response = await api.get(`/api/analysis/${symbol}/${timeframe}`)
    return response.data
  },

  // MT5
  async getCurrentPrice(symbol) {
    const response = await api.get(`/api/mt5/price/${symbol}`)
    return response.data
  },

  async getPositions() {
    const response = await api.get('/api/mt5/positions')
    return response.data
  },

  // Bot Control
  async startBot(botConfigId) {
    const response = await api.post('/api/bot/start', { bot_config_id: botConfigId })
    return response.data
  },

  async stopBot(botConfigId) {
    const response = await api.post('/api/bot/stop', { bot_config_id: botConfigId })
    return response.data
  },

  // Trades
  async getTrades(limit = 50) {
    const response = await api.get('/api/trades', { params: { limit } })
    return response.data
  },

  // Health
  async getHealth() {
    const response = await api.get('/health')
    return response.data
  },
}
```

---

## Step 5.4: Create Main Dashboard Component

Create `src/views/Dashboard.vue`:

```vue
<template>
  <div class="min-h-screen bg-gray-900 text-white p-8">
    <div class="max-w-7xl mx-auto">
      <h1 class="text-4xl font-bold mb-8">Institutional Edge PRO</h1>

      <!-- Status Cards -->
      <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
        <div class="bg-gray-800 p-6 rounded-lg">
          <div class="text-gray-400 text-sm">Current Price</div>
          <div class="text-2xl font-bold mt-2">
            {{ currentPrice ? currentPrice.toFixed(5) : '--' }}
          </div>
        </div>

        <div class="bg-gray-800 p-6 rounded-lg">
          <div class="text-gray-400 text-sm">Trend</div>
          <div class="text-2xl font-bold mt-2" :class="trendColor">
            {{ trend || '--' }}
          </div>
        </div>

        <div class="bg-gray-800 p-6 rounded-lg">
          <div class="text-gray-400 text-sm">Bull Score</div>
          <div class="text-2xl font-bold mt-2 text-green-400">
            {{ bullScore }}/10
          </div>
        </div>

        <div class="bg-gray-800 p-6 rounded-lg">
          <div class="text-gray-400 text-sm">Bear Score</div>
          <div class="text-2xl font-bold mt-2 text-red-400">
            {{ bearScore }}/10
          </div>
        </div>
      </div>

      <!-- Controls -->
      <div class="bg-gray-800 p-6 rounded-lg mb-8">
        <div class="flex gap-4">
          <input
            v-model="symbol"
            class="px-4 py-2 bg-gray-700 rounded"
            placeholder="Symbol (e.g., EURUSD)"
          />

          <select v-model="timeframe" class="px-4 py-2 bg-gray-700 rounded">
            <option value="M1">M1</option>
            <option value="M5">M5</option>
            <option value="M15">M15</option>
            <option value="M30">M30</option>
            <option value="H1">H1</option>
            <option value="H4">H4</option>
            <option value="D1">D1</option>
          </select>

          <button
            @click="analyze"
            class="px-6 py-2 bg-blue-600 hover:bg-blue-700 rounded font-semibold"
          >
            Analyze
          </button>

          <button
            @click="refresh"
            class="px-6 py-2 bg-gray-700 hover:bg-gray-600 rounded"
          >
            Refresh
          </button>
        </div>
      </div>

      <!-- Signals -->
      <div v-if="signals.length > 0" class="bg-gray-800 p-6 rounded-lg mb-8">
        <h2 class="text-2xl font-bold mb-4">🎯 Trading Signals</h2>

        <div v-for="signal in signals" :key="signal.timestamp" class="mb-4 p-4 bg-gray-700 rounded">
          <div class="flex justify-between items-start">
            <div>
              <div class="text-2xl font-bold" :class="signal.signal_type === 'BUY' ? 'text-green-400' : 'text-red-400'">
                {{ signal.signal_type }}
              </div>
              <div class="mt-2 text-sm space-y-1">
                <div>Entry: {{ signal.entry_price.toFixed(5) }}</div>
                <div>Stop Loss: {{ signal.stop_loss.toFixed(5) }}</div>
                <div>TP1: {{ signal.take_profit_1.toFixed(5) }}</div>
                <div>TP2: {{ signal.take_profit_2.toFixed(5) }}</div>
              </div>
            </div>

            <div>
              <div class="text-3xl font-bold">{{ signal.confluence_score }}/10</div>
              <div class="text-xs text-gray-400 mt-2">
                <div v-for="(score, factor) in signal.score_breakdown" :key="factor">
                  {{ factor }}: +{{ score }}
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Open Positions -->
      <div class="bg-gray-800 p-6 rounded-lg">
        <h2 class="text-2xl font-bold mb-4">📊 Open Positions</h2>

        <div v-if="positions.length === 0" class="text-gray-400">
          No open positions
        </div>

        <div v-else class="overflow-x-auto">
          <table class="w-full">
            <thead>
              <tr class="text-left text-gray-400">
                <th class="pb-2">Ticket</th>
                <th class="pb-2">Symbol</th>
                <th class="pb-2">Type</th>
                <th class="pb-2">Volume</th>
                <th class="pb-2">Entry</th>
                <th class="pb-2">Current</th>
                <th class="pb-2">P/L</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="pos in positions" :key="pos.ticket" class="border-t border-gray-700">
                <td class="py-2">{{ pos.ticket }}</td>
                <td>{{ pos.symbol }}</td>
                <td :class="pos.type === 'BUY' ? 'text-green-400' : 'text-red-400'">
                  {{ pos.type }}
                </td>
                <td>{{ pos.volume }}</td>
                <td>{{ pos.price_open.toFixed(5) }}</td>
                <td>{{ pos.price_current.toFixed(5) }}</td>
                <td :class="pos.profit >= 0 ? 'text-green-400' : 'text-red-400'">
                  ${{ pos.profit.toFixed(2) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import api from '../services/api'

const symbol = ref('EURUSD')
const timeframe = ref('H1')
const currentPrice = ref(null)
const trend = ref(null)
const bullScore = ref(0)
const bearScore = ref(0)
const signals = ref([])
const positions = ref([])

const trendColor = computed(() => {
  return trend.value === 'BULLISH' ? 'text-green-400' : 'text-red-400'
})

async function analyze() {
  try {
    const result = await api.analyzeMarket(symbol.value, timeframe.value)

    currentPrice.value = result.current_price
    trend.value = result.trend
    bullScore.value = result.bull_confluence_score
    bearScore.value = result.bear_confluence_score
    signals.value = result.signals

  } catch (error) {
    console.error('Analysis failed:', error)
    alert('Analysis failed. Make sure MT5 is connected.')
  }
}

async function refresh() {
  await analyze()
  await loadPositions()
}

async function loadPositions() {
  try {
    const result = await api.getPositions()
    positions.value = result.positions
  } catch (error) {
    console.error('Failed to load positions:', error)
  }
}

onMounted(() => {
  analyze()
  loadPositions()

  // Auto-refresh every 10 seconds
  setInterval(refresh, 10000)
})
</script>
```

---

## Step 5.5: Update App.vue

Edit `src/App.vue`:

```vue
<template>
  <Dashboard />
</template>

<script setup>
import Dashboard from './views/Dashboard.vue'
</script>
```

---

## Step 5.6: Run the Dashboard

```bash
cd frontend
npm run dev
```

**Open:** http://localhost:5173

**You should see:**
- Dashboard with real-time data
- Market analysis button
- Signal display
- Open positions table
- Auto-refresh every 10 seconds

---

## ✅ Phase 5 Checklist

- [ ] Vue project initialized
- [ ] Tailwind configured
- [ ] API service created
- [ ] Dashboard component created
- [ ] Can connect to backend
- [ ] Market analysis works
- [ ] Signals display correctly
- [ ] Positions load
- [ ] UI looks professional

**Move to Phase 6! 🎨**

---

# PHASE 6: Testing & Validation

**⏱️ Time Required:** 3-4 days
**Goal:** Test entire system end-to-end

---

## Step 6.1: Test Trading Engine

```bash
python test_system.py
```

**Expected:** All tests pass

---

## Step 6.2: Test MT5 Integration

With MT5 open:

```bash
python test_mt5_connector.py
```

**Verify:**
- Connection works
- Data retrieval works
- Can open demo position
- Can close position

---

## Step 6.3: Test API Endpoints

```bash
# Start backend
cd backend/app
python main.py
```

**Test each endpoint at http://localhost:8000/docs**

---

## Step 6.4: Test Frontend

```bash
cd frontend
npm run dev
```

**Manual test:**
1. Click "Analyze" button
2. Verify data loads
3. Change symbol and timeframe
4. Check signals appear
5. Verify positions display

---

## Step 6.5: Integration Test

**Full System Test:**

1. Start PostgreSQL
2. Start backend
3. Start frontend
4. Open MT5
5. Open dashboard
6. Click "Analyze"
7. Verify everything works together

---

## ✅ Phase 6 Checklist

- [ ] Trading engine tests pass
- [ ] MT5 tests pass
- [ ] All API endpoints work
- [ ] Frontend connects to backend
- [ ] Data flows end-to-end
- [ ] Signals generate correctly
- [ ] Can view positions
- [ ] No console errors

**Move to Phase 7! ✅**

---

# PHASE 7: Deployment

**⏱️ Time Required:** 1 week
**Goal:** Deploy to production VPS

---

## Step 7.1: Choose VPS Provider

**Recommended:**
- DigitalOcean ($12/month)
- AWS EC2 (t2.small)
- Vultr ($12/month)
- Linode ($12/month)

**Specs needed:**
- 2 CPU cores
- 4GB RAM
- 80GB SSD
- Ubuntu 22.04 LTS

---

## Step 7.2: Server Setup

```bash
# SSH into server
ssh root@your_server_ip

# Update system
apt update && apt upgrade -y

# Install Python
apt install python3.10 python3-pip python3-venv -y

# Install PostgreSQL
apt install postgresql postgresql-contrib -y

# Install Nginx
apt install nginx -y

# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install nodejs -y

# Install Wine (for MT5 on Linux)
dpkg --add-architecture i386
apt update
apt install wine64 wine32 -y
```

---

## Step 7.3: Deploy Backend

```bash
# Clone or upload code
cd /home
git clone your_repo_url institutional-edge-system

# Set up backend
cd institutional-edge-system/backend
python3 -m venv venv
source venv/bin/activate
pip install -r ../requirements.txt

# Create .env
nano .env
# (Paste production config)

# Create database
sudo -u postgres psql
CREATE DATABASE institutional_edge;
\q

# Initialize DB
cd app
python -c "from api.database import init_db; init_db()"

# Create systemd service
sudo nano /etc/systemd/system/institutional-edge.service
```

**Service file:**
```ini
[Unit]
Description=Institutional Edge Pro API
After=network.target postgresql.service

[Service]
User=root
WorkingDirectory=/home/institutional-edge-system/backend/app
Environment="PATH=/home/institutional-edge-system/backend/venv/bin"
ExecStart=/home/institutional-edge-system/backend/venv/bin/python main.py

Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
# Start service
sudo systemctl daemon-reload
sudo systemctl enable institutional-edge
sudo systemctl start institutional-edge

# Check status
sudo systemctl status institutional-edge
```

---

## Step 7.4: Deploy Frontend

```bash
cd /home/institutional-edge-system/frontend

# Build for production
npm install
npm run build

# Copy to Nginx
sudo cp -r dist/* /var/www/html/
```

---

## Step 7.5: Configure Nginx

```bash
sudo nano /etc/nginx/sites-available/default
```

```nginx
server {
    listen 80;
    server_name your_domain.com;

    # Frontend
    location / {
        root /var/www/html;
        try_files $uri $uri/ /index.html;
    }

    # Backend API
    location /api {
        proxy_pass http://localhost:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    # WebSocket
    location /ws {
        proxy_pass http://localhost:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

```bash
# Test and reload
sudo nginx -t
sudo systemctl reload nginx
```

---

## Step 7.6: SSL Certificate (HTTPS)

```bash
# Install Certbot
apt install certbot python3-certbot-nginx -y

# Get certificate
sudo certbot --nginx -d your_domain.com

# Auto-renewal is set up automatically
```

---

## Step 7.7: Setup MT5 on VPS

**Option 1: Windows VPS**
- Easier - just install MT5 normally
- More expensive

**Option 2: Linux + Wine**
- Cheaper
- More complex setup
- May have issues

**Option 3: Local MT5 + VPN**
- Run MT5 on your PC
- VPN to VPS
- Backend connects remotely

---

## ✅ Phase 7 Checklist

- [ ] VPS created and configured
- [ ] Backend deployed and running
- [ ] Frontend built and deployed
- [ ] Nginx configured
- [ ] SSL certificate installed
- [ ] MT5 accessible
- [ ] System accessible via domain
- [ ] Auto-restart on reboot configured

**Move to Phase 8! 🚀**

---

# PHASE 8: Monitoring & Maintenance

**⏱️ Time Required:** Ongoing
**Goal:** Keep system running smoothly

---

## Step 8.1: Setup Logging

Backend logs already use Loguru.

**View logs:**
```bash
tail -f logs/trading.log
```

**Configure log rotation:**
```bash
nano /etc/logrotate.d/institutional-edge
```

```
/home/institutional-edge-system/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
}
```

---

## Step 8.2: Monitoring Script

Create `monitor.sh`:

```bash
#!/bin/bash

# Check if backend is running
if ! systemctl is-active --quiet institutional-edge; then
    echo "Backend is down! Restarting..."
    systemctl restart institutional-edge
    # Send alert (add your notification method)
fi

# Check disk space
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 80 ]; then
    echo "Disk usage is above 80%!"
    # Send alert
fi

# Check database
if ! systemctl is-active --quiet postgresql; then
    echo "PostgreSQL is down! Restarting..."
    systemctl restart postgresql
fi
```

```bash
chmod +x monitor.sh

# Add to crontab (run every 5 minutes)
crontab -e
*/5 * * * * /home/institutional-edge-system/monitor.sh
```

---

## Step 8.3: Backup Strategy

```bash
# Create backup script
nano backup.sh
```

```bash
#!/bin/bash

# Backup database
pg_dump institutional_edge > /backups/db_$(date +%Y%m%d).sql

# Keep only last 30 days
find /backups -name "db_*.sql" -mtime +30 -delete

# Backup config
cp .env /backups/env_$(date +%Y%m%d)
```

```bash
chmod +x backup.sh

# Daily backup at 2 AM
crontab -e
0 2 * * * /home/institutional-edge-system/backup.sh
```

---

## Step 8.4: Performance Monitoring

**Use tools:**
- `htop` - CPU/RAM usage
- `netdata` - Real-time monitoring
- PostgreSQL slow query log
- Application logs

---

## Step 8.5: Regular Maintenance Tasks

**Weekly:**
- Check logs for errors
- Review trade performance
- Verify backups
- Check disk space

**Monthly:**
- Update dependencies
- Review and optimize database
- Analyze system performance
- Update documentation

**Quarterly:**
- Security audit
- Performance optimization
- Feature updates
- User feedback review

---

## ✅ Phase 8 Checklist

- [ ] Logging configured
- [ ] Log rotation setup
- [ ] Monitoring script created
- [ ] Automated backups working
- [ ] Alerts configured
- [ ] Performance monitoring in place
- [ ] Maintenance schedule created

---

# 🎉 COMPLETION CHECKLIST

## Overall System

- [ ] All 8 phases completed
- [ ] Trading engine working
- [ ] MT5 integration working
- [ ] Database functioning
- [ ] API endpoints tested
- [ ] Frontend dashboard complete
- [ ] System tested end-to-end
- [ ] Deployed to production
- [ ] Monitoring in place
- [ ] Documentation complete

---

# 📚 Additional Resources

## Learning Materials

**Python:**
- Official Python Tutorial
- FastAPI Documentation
- SQLAlchemy Tutorial

**Vue.js:**
- Vue 3 Documentation
- Pinia State Management
- TailwindCSS Docs

**Trading:**
- Smart Money Concepts courses
- ICT (Inner Circle Trader) YouTube
- Volume Profile analysis

**DevOps:**
- DigitalOcean Tutorials
- Nginx documentation
- PostgreSQL optimization

---

# 🆘 Troubleshooting Guide

## Common Issues

**"Module not found"**
- Solution: `pip install -r requirements.txt`

**"MT5 not connecting"**
- Check MT5 is running
- Verify credentials in .env
- Check broker allows API

**"Database connection failed"**
- Ensure PostgreSQL running
- Check DATABASE_URL in .env
- Verify database exists

**"Frontend can't connect to backend"**
- Check backend is running
- Verify CORS settings
- Check API_BASE_URL in frontend

**"No data from MT5"**
- Verify symbol name is correct
- Check market is open
- Ensure broker provides data

---

# 🎯 Next Steps After Completion

1. **Test with paper trading** for 1 month
2. **Optimize confluence parameters** based on results
3. **Add more strategies** (e.g., breakout, range trading)
4. **Implement backtesting** engine
5. **Create mobile app** (React Native)
6. **Add multi-user support**
7. **Build SaaS platform**
8. **Marketing and sales**

---

# 💡 Pro Tips

1. **Start small** - Test on demo account first
2. **Keep it simple** - Don't over-optimize
3. **Log everything** - You'll need it for debugging
4. **Backup regularly** - Databases, code, configs
5. **Monitor closely** - Especially first month
6. **Stay updated** - Keep dependencies current
7. **Be patient** - Building takes time
8. **Test thoroughly** - Before going live
9. **Document changes** - Future you will thank you
10. **Have fun** - You're building something awesome!

---

**Good luck building your Institutional Edge PRO system! 🚀**

**Questions? Issues? Check:**
- README.md
- QUICKSTART.md
- GitHub Issues
