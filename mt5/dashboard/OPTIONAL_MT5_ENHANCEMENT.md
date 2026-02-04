# Optional MT5 Enhancement for Better Dashboard Integration

This document describes optional enhancements to the MQL5 code to improve real-time data availability in the dashboard.

## Enhancement: Periodic Account State Logging

Add periodic logging of account state to the GovernorState table for real-time monitoring.

### Location
File: `Portfolio_Governor.mq5`
Function: `OnTimer()`

### Code to Add

Add this code after the heartbeat log section (around line 324):

```mql5
// 1.6. Update Account State in Database (every 60 seconds for dashboard)
static datetime lastStateUpdate = 0;
if(TimeCurrent() - lastStateUpdate >= 60) // Every 60 seconds
{
    // Update account state values
    g_db.SetState("balance", account.Balance());
    g_db.SetState("equity", account.Equity());
    g_db.SetState("margin_used", account.MarginUsed());
    g_db.SetState("margin_free", account.FreeMargin());
    g_db.SetState("last_update", (double)TimeCurrent());

    lastStateUpdate = TimeCurrent();
}
```

### What This Does

1. **Updates every 60 seconds**: Logs current account state without impacting performance
2. **Stores account metrics**: Balance, equity, margin used, margin free
3. **Timestamp tracking**: Records when the last update occurred
4. **Dashboard integration**: Provides real-time data for the dashboard without querying MT5 directly

### Benefits

- **Real-time monitoring**: Dashboard shows current account state without lag
- **Minimal overhead**: 60-second update interval is lightweight
- **Debugging aid**: Track account state changes over time
- **Historical data**: Can query past account states from database

### Alternative: Less Frequent Updates

If you want to reduce database writes, change the interval:

```mql5
if(TimeCurrent() - lastStateUpdate >= 300) // Every 5 minutes
```

### Testing

After applying this enhancement:

1. Start MT5 and Portfolio Governor EA
2. Wait 60 seconds
3. Query the database:
```sql
SELECT * FROM GovernorState WHERE key IN ('balance', 'equity', 'margin_used', 'margin_free');
```
4. Verify values are being updated

### Rollback

If you want to remove this enhancement, simply delete the added code block. The dashboard will still work but will calculate values from trade data instead of reading real-time state.

## Enhancement 2: Symbol Status Logging (Advanced)

For advanced users who want to monitor which symbols are currently allowed/blocked.

### Code to Add

Add this in the ranking loop (after line 370 where symbols are processed):

```mql5
// Log current symbol status to database
for(int i = 0; i < ArraySize(ranked); i++)
{
    string stateKey = "symbol_status_" + ranked[i].symbol;
    g_db.SetState(stateKey, ranked[i].allowed ? 1.0 : 0.0);

    stateKey = "symbol_score_" + ranked[i].symbol;
    g_db.SetState(stateKey, ranked[i].score);
}
```

### Benefits

- Track which symbols are currently allowed for trading
- Monitor real-time confluence scores
- Debug why certain symbols aren't trading

### Dashboard Enhancement

To display this in the dashboard, modify `symbol_metrics.py`:

```python
def get_symbol_status(db: DatabaseReader, symbol: str) -> Dict[str, Any]:
    """Get current status for a symbol"""
    try:
        with db._get_connection() as conn:
            cursor = conn.cursor()

            # Get allowed status
            cursor.execute(
                "SELECT value_num FROM GovernorState WHERE key = ?",
                (f"symbol_status_{symbol}",)
            )
            row = cursor.fetchone()
            allowed = row['value_num'] if row else None

            # Get current score
            cursor.execute(
                "SELECT value_num FROM GovernorState WHERE key = ?",
                (f"symbol_score_{symbol}",)
            )
            row = cursor.fetchone()
            score = row['value_num'] if row else None

            return {
                'allowed': allowed == 1.0 if allowed is not None else False,
                'score': score if score is not None else 0.0
            }
    except Exception as e:
        print(f"Error getting symbol status: {e}")
        return {'allowed': False, 'score': 0.0}
```

## Notes

- **Optional**: The dashboard works without these enhancements using trade data
- **Performance**: Minimal impact (<1ms per update)
- **Data retention**: Consider cleaning old state entries if needed
- **Testing**: Always test on demo account first

## Recommendation

**Start with Enhancement 1 only**. It provides the most value with minimal complexity. Add Enhancement 2 only if you need detailed symbol status monitoring.
