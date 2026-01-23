# Elite MT5 Trading Intelligence Platform

> **Advanced real-time trading analytics and intelligent portfolio management for MetaTrader 5**

A sophisticated Streamlit-based web application that provides comprehensive trading analytics, performance tracking, and intelligent portfolio optimization using correlation analysis and dynamic multi-factor scoring.

---

## 📊 Features

### Core Analytics
- **Real-Time Trade Monitoring**: Live tracking of open positions and historical trades
- **Performance Analytics**: Comprehensive metrics including Sharpe ratio, profit factor, win rates, expectancy, and drawdown analysis
- **Equity Curve Tracking**: Visual equity curves with peak tracking and drawdown visualization
- **Pattern Analysis**: Performance breakdown by trading patterns and comment tags
- **Multi-Timeframe Charts**: Interactive candlestick charts with trade markers using lightweight-charts

### Portfolio Governor System
The crown jewel of the platform - an intelligent portfolio selection system that:

- **Automated Symbol Selection**: Automatically selects optimal 4-symbol trading groups from a universe of 20 symbols
- **Real-Time Correlation Analysis**: Calculates correlation matrices using live MT5 price data
- **Dynamic Multi-Factor Scoring** (0-100 scale):
  - Session Activity (0-20): Trading session alignment
  - Trend Alignment (0-25): HTF trend clarity via EMA analysis
  - Spread Quality (0-15): Current vs maximum acceptable spread
  - Volatility Match (0-15): ATR-based volatility assessment
  - Historical Performance (0-25): Win rate from past trades

- **Intelligent Group Generation**: Creates valid combinations with rules:
  - Maximum 2 symbols with same primary currency driver
  - Maximum 1 high correlation pair (>0.75) per group
  - Minimum 2 different asset classes per group
  - Risk-On/Risk-Off balance optimization

- **MT5 EA Integration**: Automatic synchronization with Expert Advisors

### Visualization Components
- **Equity Curves**: Interactive Plotly charts with peak tracking
- **Drawdown Analysis**: Underwater drawdown charts
- **Correlation Heatmaps**: Real-time correlation matrices
- **Performance Breakdowns**: By symbol, time of day, day of week, and month
- **Profit Distribution**: Histogram analysis of trade outcomes
- **Currency Exposure**: Net exposure tracking across currencies

---

## 🚀 Quick Start

### Prerequisites

- **Windows** (MT5 is Windows-only)
- **Python 3.8+**
- **MetaTrader 5 Terminal** installed and running
- **Active MT5 account** (demo or live)

### Installation

1. **Clone the repository**:
   ```bash
   cd path/to/streamlit_project
   ```

2. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Configure environment** (optional):
   ```bash
   cp .env.example .env
   # Edit .env to customize settings
   ```

4. **Verify MT5 .set files path**:
   - Default path: `C:\Users\[YourUser]\Desktop\Projects\advanced_fibonacci_pro_v7\mt5\portafolio_manager\sets`
   - Update `MT5_SETS_PATH` in `.env` if your path differs

5. **Run the application**:
   ```bash
   streamlit run app.py
   ```

6. **Open browser**:
   - Navigate to `http://localhost:8501`
   - The app will automatically connect to your running MT5 terminal

---

## ⚙️ Configuration

### Environment Variables

Create a `.env` file (use `.env.example` as template) to customize:

#### MT5 Settings
```env
MT5_SETS_PATH=C:\path\to\your\sets
MT5_TIMEOUT=60000
```

#### Portfolio Governor
```env
CORRELATION_TIMEFRAME=H1
CORRELATION_BARS=100
CORRELATION_CACHE_TTL=900
CORRELATION_HIGH_THRESHOLD=0.75

GROUP_SIZE=4
MAX_SAME_DRIVER=2
MAX_HIGH_CORR_PAIRS=1
MIN_ASSET_CLASSES=2
```

#### Scoring Weights (must sum to 100)
```env
SCORE_SESSION_ACTIVITY_MAX=20
SCORE_TREND_ALIGNMENT_MAX=25
SCORE_SPREAD_QUALITY_MAX=15
SCORE_VOLATILITY_MATCH_MAX=15
SCORE_HISTORICAL_PERF_MAX=25
```

#### Performance & Caching
```env
CACHE_ENABLED=true
SYMBOL_SCORES_CACHE_TTL=60
GROUPS_CACHE_TTL=300
```

See `.env.example` for all available options.

---

## 📁 Project Structure

```
streamlit_project/
├── app.py                          # Main Streamlit application
├── requirements.txt                # Python dependencies
├── .env.example                    # Environment configuration template
├── README.md                       # This file
│
├── .streamlit/
│   └── config.toml                # Streamlit theme configuration
│
├── src/                           # Core application code
│   ├── __init__.py
│   ├── config.py                  # Configuration management
│   ├── logger.py                  # Logging framework
│   ├── cache_utils.py             # Caching utilities
│   │
│   ├── connector.py               # MT5 connection singleton
│   ├── data_engine.py             # Data fetching & processing
│   ├── analytics.py               # Performance analytics
│   ├── patterns.py                # Pattern analysis
│   ├── types.py                   # Data models (Trade dataclass)
│   │
│   └── portfolio/                 # Portfolio Governor subsystem
│       ├── __init__.py
│       ├── portfolio_governor.py  # Main orchestrator
│       ├── symbol_metadata.py     # 20-symbol metadata database
│       ├── symbol_scorer.py       # Dynamic scoring engine
│       ├── correlation_engine.py  # Real-time correlations
│       ├── group_generator.py     # 4-symbol combinations
│       ├── group_ranker.py        # Group ranking logic
│       ├── set_parser.py          # MT5 .set file parser
│       └── ea_communicator.py     # MT5 EA synchronization
│
├── components/                    # UI components
│   ├── __init__.py
│   ├── charts.py                  # Visualization components
│   ├── metrics.py                 # KPI displays
│   └── governor_components.py     # Portfolio Governor UI
│
├── logs/                          # Application logs (auto-created)
│   ├── mt5_platform.log
│   ├── mt5_platform_errors.log
│   └── ...
│
└── data/                          # Database (auto-created)
    └── trading.db                 # SQLite database (future)
```

---

## 🎯 Usage Guide

### Tab Navigation

The application has 7 tabs:

1. **📊 Dashboard**: Account overview, equity curve, open positions, recent trades
2. **📈 Analytics**: Comprehensive performance metrics and statistics
3. **🎨 Patterns**: Performance breakdown by trading patterns/comments
4. **🏛️ Governor**: Portfolio Governor interface with correlation matrix and group selection
5. **📉 Charts**: Symbol-specific candlestick charts with trade markers
6. **⏰ Time Analysis**: Performance by time of day, day of week, and month
7. **📋 Trades**: Detailed trade history table

### Portfolio Governor Workflow

1. **Navigate to Governor Tab**
2. **Click "Refresh Scores & Groups"**: Calculates symbol scores and generates valid groups
3. **Review Correlation Matrix**: Understand symbol relationships
4. **Browse Top Groups**: Ranked by composite score
5. **Select a Group**: Click to activate a specific group
6. **Sync with MT5** (optional): Push selection to Expert Advisors
7. **Lock Group** (optional): Prevent changes during trading session

### Operating Modes

- **AUTO**: Automatically selects best-ranked group
- **MANUAL**: User manually selects from candidate groups
- **LOCKED**: Group locked for session (no changes allowed)

---

## 📊 Supported Symbols

The platform supports 20 symbols across 4 asset classes:

### Forex Majors (7)
- EURUSD, GBPUSD, USDJPY, USDCHF, USDCAD, AUDUSD, NZDUSD

### Forex Minors (2)
- EURCHF, EURGBP

### Forex Crosses (8)
- EURJPY, GBPJPY, CADJPY, CHFJPY, NZDJPY, AUDJPY, EURAUD, GBPAUD

### Metals & Indices (3)
- XAUUSD (Gold), XAGUSD (Silver), US30 (Dow Jones)

Each symbol has metadata including:
- Asset class
- Risk profile (Risk-On, Risk-Off, Neutral)
- Volatility level
- Preferred trading sessions
- Base and quote currencies

---

## 🔧 Troubleshooting

### MT5 Connection Issues

**Problem**: "MT5 Initialization failed"

**Solutions**:
1. Ensure MT5 terminal is running
2. Check MT5 allows API access: Tools → Options → Expert Advisors → Allow automated trading
3. Run the app as Administrator (if needed)
4. Check logs in `logs/` directory for detailed errors

### No Data Displayed

**Problem**: Empty charts/tables

**Solutions**:
1. Verify you have trading history in MT5
2. Check the date range in the app
3. Ensure MT5 account has deal history loaded
4. Check logs for fetch errors

### Slow Performance

**Solutions**:
1. Reduce `CORRELATION_BARS` in config (default: 100)
2. Enable caching: `CACHE_ENABLED=true`
3. Reduce history fetch period
4. Close other MT5-connected applications

### Set Files Not Found

**Problem**: "Sets directory not found"

**Solutions**:
1. Update `MT5_SETS_PATH` in `.env`
2. Ensure .set files exist in the specified directory
3. Check path uses correct Windows path format (backslashes or raw strings)

---

## 🧪 Development

### Logging

Logs are written to `logs/` directory:
- `mt5_platform.log`: General application logs
- `mt5_platform_errors.log`: Error-only logs
- Component-specific logs for debugging

Set log level in `.env`:
```env
LOG_LEVEL=DEBUG  # DEBUG, INFO, WARNING, ERROR, CRITICAL
```

### Running Tests

```bash
# Install test dependencies
pip install pytest pytest-cov

# Run tests
pytest tests/ -v

# Run with coverage
pytest tests/ --cov=src --cov-report=html
```

### Adding New Symbols

1. Add symbol to `src/portfolio/symbol_metadata.py`:
   ```python
   SymbolInfo(
       symbol="NEWPAIR",
       base_currency="EUR",
       quote_currency="USD",
       symbol_class=SymbolClass.MAJOR,
       risk_profile=RiskProfile.NEUTRAL,
       volatility=VolatilityLevel.MEDIUM,
       sessions=[Session.LONDON, Session.NY]
   )
   ```

2. Add .set file to your sets directory
3. Update `MAX_SPREADS` in `symbol_scorer.py` if needed

---

## 📈 Performance Metrics Reference

### Sharpe Ratio
- **Formula**: `(Return - RiskFreeRate) / StdDev`
- **Interpretation**: Risk-adjusted return
  - \> 1.0: Good
  - \> 2.0: Very Good
  - \> 3.0: Excellent

### Profit Factor
- **Formula**: `GrossProfit / GrossLoss`
- **Interpretation**: Ratio of winning to losing money
  - \> 1.0: Profitable
  - \> 1.5: Good
  - \> 2.0: Excellent

### Expectancy
- **Formula**: `AvgWin * WinRate - AvgLoss * LossRate`
- **Interpretation**: Average expected profit per trade

### Max Drawdown
- **Definition**: Largest peak-to-trough decline
- **Important**: Keep below 20% for risk management

---

## 🛡️ Security & Best Practices

1. **Never commit `.env` file**: Contains sensitive paths and settings
2. **Use demo accounts first**: Test thoroughly before live trading
3. **Monitor drawdowns**: Set alerts at configured thresholds
4. **Regular backups**: Backup your MT5 data and logs
5. **Review logs**: Check error logs regularly for issues

---

## 📝 License

This project is proprietary software. All rights reserved.

---

## 🤝 Support

For issues, questions, or feature requests:
1. Check logs in `logs/` directory
2. Review troubleshooting section above
3. Check MT5 terminal for errors
4. Contact development team with log files

---

## 🚧 Roadmap

### Planned Enhancements
- [ ] SQLite database for historical data persistence
- [ ] Portfolio group performance tracking over time
- [ ] Machine learning for score weight optimization
- [ ] Monte Carlo simulation for risk assessment
- [ ] Real-time WebSocket updates
- [ ] Multi-account support
- [ ] PDF report export
- [ ] Mobile-responsive UI improvements
- [ ] Custom alert engine
- [ ] Backtesting framework for portfolio strategies

---

## 📚 Additional Resources

- [MetaTrader 5 Python Documentation](https://www.mql5.com/en/docs/python_metatrader5)
- [Streamlit Documentation](https://docs.streamlit.io/)
- [Plotly Python Documentation](https://plotly.com/python/)

---

**Built with ❤️ for professional traders**
