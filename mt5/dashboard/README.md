# MT5 Portfolio Manager - Streamlit Monitoring Dashboard

Real-time monitoring dashboard for the MT5 Portfolio Governor trading system.

## Features

- **Account Overview**: Real-time balance, equity, P/L, and key metrics
- **Open Positions**: Live monitoring of active trades with floating P/L
- **Trade History**: Historical trade analysis with filters and equity curve
- **Symbol Performance**: Per-symbol metrics and performance analysis
- **Risk & Exposure**: Drawdown tracking, margin monitoring, and risk alerts

## Quick Start

### Using Docker Compose (Recommended)

The dashboard runs as a separate service that connects to the existing MT5 network and volume.

1. **Make sure MT5 is running first**:
```bash
cd mt5
docker-compose up -d
```

2. **Build and start the dashboard**:
```bash
cd mt5/dashboard
docker-compose up -d
```

3. **Access the dashboard**:
```
http://localhost:8501
```

4. **Stop the dashboard** (MT5 keeps running):
```bash
cd mt5/dashboard
docker-compose down
```

### Manual Setup (Development)

1. Install dependencies:
```bash
cd mt5/dashboard
pip install -r requirements.txt
```

2. Set database path (adjust to your MT5 installation):
```bash
export DB_PATH="/path/to/PortfolioGovernor.sqlite"
```

3. Run the dashboard:
```bash
streamlit run app.py
```

## Configuration

### Environment Variables

- `DB_PATH`: Path to the SQLite database file
  - Default (Docker): `/mt5_data/.wine/drive_c/users/Public/Documents/MetaQuotes/Terminal/Common/Files/PortfolioGovernor.sqlite`
  - Adjust based on your MT5 installation path

### Dashboard Settings

Access settings in the sidebar:
- **Auto-refresh**: Enable automatic data refresh every 10 seconds
- **Time Range**: Select period for trade history (1D, 7D, 30D, 90D, All)
- **Manual Refresh**: Click "Refresh Now" button to update data immediately

## Components

### 1. Account Overview
Displays key account metrics:
- Balance & Equity
- Daily and Total P/L
- Open Positions Count
- Win Rate & Profit Factor
- Margin Usage

### 2. Open Positions
Shows active trades:
- Symbol, Type (BUY/SELL), Lots
- Entry Price & Floating P/L
- Entry Time & Confluence Score
- Regime & Killzone classification

### 3. Symbol Performance
Per-symbol analytics:
- Total trades and Win Rate
- Profit Factor
- Total P/L and Average Win/Loss
- Best and Worst trades
- Current signal status

### 4. Risk & Exposure
Risk management metrics:
- Current and Maximum Drawdown
- Peak Equity tracking
- Margin Used percentage
- Position distribution by symbol
- 30-day equity curve
- Automated risk alerts

### 5. Trade History
Historical trade analysis:
- Filterable trade table (by symbol, regime, killzone, result)
- Cumulative P/L chart
- Export to CSV
- Performance summary statistics

## Database Schema

The dashboard reads from three tables:

### Trades Table
- Open positions: `close_time IS NULL`
- Closed trades: `close_time IS NOT NULL`

### Signals Table
- Trading signals with confluence scores
- Allowed/rejected status with reasons

### GovernorState Table
- System state key-value store
- Account balance, equity, margin data

## Troubleshooting

### "Could not connect to database"
- Verify MT5 container is running: `docker ps`
- Check database file exists in MT5 Common Files directory
- Verify volume mount in docker-compose-dashboard.yml
- Check DB_PATH environment variable

### "No data found in database"
- Ensure Portfolio_Governor.mq5 is running in MT5
- Verify database is being written to (check file timestamp)
- Check MT5 logs for database errors

### Dashboard shows stale data
- Enable auto-refresh in sidebar
- Click "Refresh Now" button
- Check if MT5 is actively trading/updating database

### Permission errors
- Ensure dashboard has read access to database file
- Check volume mount permissions in docker-compose

## Performance

- **Query Time**: <100ms for most queries
- **Memory Usage**: ~256MB baseline, <1GB with data
- **Refresh Rate**: Configurable (default: manual or 10s auto-refresh)

## Development

### Project Structure
```
dashboard/
├── app.py                  # Main Streamlit application
├── requirements.txt        # Python dependencies
├── Dockerfile             # Container configuration
├── components/            # Dashboard components
│   ├── __init__.py
│   ├── account_overview.py
│   ├── positions.py
│   ├── trade_history.py
│   ├── symbol_metrics.py
│   └── risk_metrics.py
└── utils/                 # Utility modules
    ├── __init__.py
    ├── db_reader.py       # Database access layer
    └── metrics.py         # Metric calculations
```

### Adding New Components

1. Create component file in `components/`:
```python
def render(db: DatabaseReader):
    st.subheader("My Component")
    # Component logic
```

2. Import in `app.py`:
```python
from components import my_component
my_component.render(db)
```

3. Update `components/__init__.py`

### Database Access

Use `DatabaseReader` class for all database queries:
```python
from utils.db_reader import DatabaseReader

db = DatabaseReader()
trades = db.get_trade_history(days=7)
positions = db.get_open_positions()
```

## Docker Deployment

### Build Only Dashboard
```bash
docker-compose -f docker-compose-dashboard.yml build dashboard
```

### Start All Services
```bash
docker-compose -f docker-compose-dashboard.yml up -d
```

### View Logs
```bash
docker-compose -f docker-compose-dashboard.yml logs -f dashboard
```

### Stop Dashboard
```bash
docker-compose -f docker-compose-dashboard.yml stop dashboard
```

### Remove Dashboard
```bash
docker-compose -f docker-compose-dashboard.yml down dashboard
```

## Future Enhancements

- [ ] Email/Telegram alerts for risk thresholds
- [ ] Performance comparison charts (daily/weekly/monthly)
- [ ] Backtesting comparison views
- [ ] User authentication for external access
- [ ] ML prediction monitoring panels
- [ ] Real-time tick data visualization
- [ ] Trade journal with notes
- [ ] Performance attribution analysis

## Requirements

- Python 3.11+
- Streamlit 1.31.0+
- Pandas 2.2.0+
- Plotly 5.18.0+
- MT5 Portfolio Governor running and writing to SQLite

## License

Part of the MT5 Portfolio Governor trading system.

## Support

For issues or questions:
1. Check troubleshooting section above
2. Review MT5 logs for database errors
3. Verify docker-compose configuration
4. Check dashboard container logs
