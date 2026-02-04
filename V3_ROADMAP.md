# Version 3 Roadmap: The "Brain & Muscle" Architecture

## 1. Vision

**Version 2** was a monolithic MQL5 system where all logic (SMC, ML, Correlation) lived inside the terminal. This created bloat and limited AI capabilities.
**Version 3** decouples intelligence from execution.

- **The Brain (Python)**: Handles deep analysis, ML models, correlation complexity, and strategy decisions.
- **The Muscle (MT5)**: Handles sub-millisecond execution, trade management, and data feeding.

---

## 2. Deletions (Hollowing out MQL5)

Remove heavy computation and "fake" ML logic from MQL5 to strip it down to a pure execution engine.

### Files to Delete / Deprecate

| File                            | Reason                                                | Replacement                                               |
| ------------------------------- | ----------------------------------------------------- | --------------------------------------------------------- |
| `Include/MLRegimeDetector.mqh`  | Primitive k-means implementation in C++.              | `sklearn.cluster.KMeans` or PyTorch classifiers (Python). |
| `Include/CorrelationMatrix.mqh` | Heavy matrix math, memory intensive in MQL5.          | `pandas.DataFrame.corr()` (Python).                       |
| `Include/NewsFilter.mqh`        | Parsing calendars in MQL5 is fragile.                 | specialized News API aggregator (Python).                 |
| `Include/KillzoneOptimizer.mqh` | Optimization logic should not live in the trading EA. | Python `optuna` or Genetic Algorithms running outside.    |
| `Include/SMC_*` (Partial)       | Move complex pattern recognition to Python.           | `scipy.signal` find_peaks & ML pattern recognition.       |

---

## 3. Additions (New Infrastructure)

### A. Python Core ("The Brain")

1.  **Alpha Engine**: A Python service that consumes price data and outputs probability signals (0.0 - 1.0).
2.  **Risk Engine**: Calculates real-time VaR (Value at Risk) and correlations across the entire portfolio using Pandas.
3.  **Bridge Layer**:
    - **ZeroMQ (ZMQ)**: For ultra-low latency signal passing between Python and MT5.
    - **FastAPI**: For dashboard control and configuration.

### B. Data & Logging

1.  **TimescaleDB / PostgreSQL**: Replace text-file logs with a proper time-series database for trade history and tick data.
2.  **ML Pipeline**: A process to retrain the Regime Detector models weekly based on new data.

### C. Dashboard (Control Plane)

1.  **Streamlit / React App**: Real-time view of the "Brain's" thinking, not just the "Muscle's" trades.
    - Visualizing Regime probabilities.
    - Live Correlation Heatmap.
    - "Emergency Stop" button (API call).

---

## 4. Modifications (Refactoring)

### 1. `Symbol_Engine` -> `Execution_Agent`

- **Current**: Decides _if_ and _when_ to trade based on 20 parameters.
- **V3**: Receives a specific command: `{"action": "BUY", "ticket": 123, "sl": 1.0950, "tp": 1.1000}`.
- **Job**: Execute the order, manage the trail, handle retires, reports fill status. ensuring execution quality.

### 2. `Portfolio_Governor` -> `Bridge_Client`

- **Current**: Loops through symbols and calculates scores.
- **V3**: Listens to the ZMQ socket. When a signal arrives for "EURUSD", it delegates it to the EURUSD `Execution_Agent`.

### 3. Verification & Testing

- **Backtesting**: Shift to **Vectorized Backtesting** (vectorbt / backtrader) in Python for strategy iteration (seconds vs hours in MT5).
- **Verification**: Use MT5 Strategy Tester only for verification of execution slippage/swaps, not for strategy logic finding.

---

## 5. Implementation Plan (Step-by-Step)

1.  **Phase 1: The Bridge**: Build the ZMQ connection. Make MT5 print "Hello from Python".
2.  **Phase 2: Data Stream**: Make MT5 stream tick data to Python/DB in real-time.
3.  **Phase 3: Logic Migration**: Move `MLRegimeDetector` logic to a Python script and send the "Regime" back to MT5.
4.  **Phase 4: The Cut**: Delete the MQL5 implementation of the migrated feature.
5.  **Phase 5: Full Control**: Python sends trade signals; MT5 simply obeys.
