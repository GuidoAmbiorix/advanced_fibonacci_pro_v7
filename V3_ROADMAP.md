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
2.  **ML Pipeline**: Automated MLOps pipeline (Airflow/Prefect) to retrain models weekly.

### C. Advanced AI Expansion (The "Cortex")

1.  **Predictive Transformers (Time-Series)**
    - _Implementation_: PyTorch / HuggingFace.
    - _Role_: Replace lagging indicators (MA/RSI) with **Attention-based models** (Temporal Fusion Transformers) to predict short-term price direction intervals.
2.  **Reinforcement Learning (Portfolio Allocator)**
    - _Implementation_: Stable Baselines3 (PPO/Soft Actor-Critic).
    - _Role_: Dynamically adjust risk per pair. A **Multi-Armed Bandit** agent learns which pairs are currently "behaving" and allocates more capital to them in real-time.
3.  **LLM Macro Analyst**
    - _Implementation_: Local LLM (Llama-3) or OpenAI API.
    - _Role_: Ingests raw text from economic calendars and news feeds. instead of simple "High Impact" filtering, it outputs a **Sentiment Score (-1.0 to 1.0)** to bias the Alpha Engine.
4.  **Unsupervised Anomaly Detection**
    - _Implementation_: Isolation Forests / Autoencoders.
    - _Role_: Detects "black swan" or manipulation behavior that rule-based filters miss, triggering an automatic "Kill Switch" to protect capital.

### D. Dashboard (Control Plane)

1.  **Streamlit / React App**: Real-time view of the "Brain's" thinking, not just the "Muscle's" trades.
    - Visualizing Regime probabilities.
    - Live Correlation Heatmap.
    - "Emergency Stop" button (API call).

---

## 4. Modifications (Refactoring)

### 1. `Symbol_Engine` -> `Neural_Execution_Agent`

- **Current**: Hardcoded logic (if RSI > 70).
- **V3**: **Hybrid Neuro-Symbolic**. The Python "Brain" sends a probability map. The Agent executes only if the probability > 85%.
- **Reinforcement Learning**: The agent learns optimal _execution_ splitting (e.g. TWAP vs Sniper) to minimize slippage, rewarding itself for filling close to mid-price.

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
