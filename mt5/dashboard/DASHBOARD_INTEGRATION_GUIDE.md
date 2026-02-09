# 📊 Dashboard Analytics Integration Guide

## Quick Integration Steps

### Step 1: Import Analytics Widgets

Add to the top of `app.py`:

```python
from analytics_widgets import (
    show_equity_curve,
    show_active_alerts,
    show_symbol_performance_matrix,
    show_regime_heatmap,
    show_optimization_priorities,
    show_correlation_warnings,
    show_drawdown_history
)
```

### Step 2: Enhance Live Control Center Page

Add to the **Live Control Center** page (after line 240):

```python
# ============================================================================
# EQUITY CURVE & ANALYTICS
# ============================================================================
st.markdown("---")
st.subheader("📈 Equity Curve")
show_equity_curve(db_manager, days=90)

st.markdown("---")
st.subheader("🔔 Performance Alerts")
show_active_alerts(db_manager)

st.markdown("---")
st.subheader("⚠️ Correlation Warnings")
show_correlation_warnings(db_manager)
```

### Step 3: Enhance Performance Page

Add to **Performance** page, **Tab 1: Portfolio Analytics** (after line 548):

```python
st.markdown("---")
st.subheader("📊 Symbol Performance Comparison")
show_symbol_performance_matrix(db_manager, days=30)

st.markdown("---")
st.subheader("🎯 Performance by Market Regime")
show_regime_heatmap(db_manager, days=30)

st.markdown("---")
st.subheader("📉 Drawdown History")
show_drawdown_history(db_manager)
```

### Step 4: Enhance Optimization Page

Add to **Optimization** page, **Tab 2: History** (after line 838):

```python
st.markdown("---")
st.subheader("🎯 Optimization Priority Queue")
show_optimization_priorities(db_manager)
```

---

## Complete Code Snippets

### For Live Control Center (Line ~240)

```python
    st.markdown("---")

    # ============================================================================
    # EQUITY CURVE (NEW)
    # ============================================================================
    st.subheader("📈 Portfolio Equity Curve")
    from analytics_widgets import show_equity_curve
    show_equity_curve(db_manager, days=90)

    st.markdown("---")

    # ============================================================================
    # PERFORMANCE ALERTS (NEW)
    # ============================================================================
    st.subheader("🔔 Active Performance Alerts")
    from analytics_widgets import show_active_alerts
    show_active_alerts(db_manager)

    st.markdown("---")

    # ============================================================================
    # CORRELATION WARNINGS (NEW)
    # ============================================================================
    from analytics_widgets import show_correlation_warnings
    show_correlation_warnings(db_manager)
```

### For Performance Page - Tab 1 (Line ~548)

```python
        except Exception as e:
            st.error(f"Error loading performance data: {e}")

    # ADD THIS SECTION
    st.markdown("---")
    st.markdown("### 📊 Enhanced Analytics")

    # Symbol performance matrix
    from analytics_widgets import show_symbol_performance_matrix
    show_symbol_performance_matrix(db_manager, days=30)

    st.markdown("---")

    # Regime heatmap
    from analytics_widgets import show_regime_heatmap
    show_regime_heatmap(db_manager, days=30)

    st.markdown("---")

    # Drawdown history
    from analytics_widgets import show_drawdown_history
    show_drawdown_history(db_manager)
```

### For Optimization Page - Tab 2 (Line ~838)

```python
        except Exception as e:
            st.warning(f"Could not load optimization history: {e}")

    # ADD THIS SECTION
    st.markdown("---")
    st.markdown("### 🎯 Priority Queue")
    from analytics_widgets import show_optimization_priorities
    show_optimization_priorities(db_manager)
```

---

## One-Time Setup Required

### 1. Run Database Migration

```bash
cd /root/advanced_fibonacci_pro_v7/mt5/dashboard

# Apply migrations
sqlite3 ../data/PortfolioGovernor.sqlite < database_migrations.sql
```

### 2. Install Dependencies

```bash
pip install apscheduler scikit-learn scipy
```

### 3. Backfill Historical Data

```bash
# Backfill last 30 days of analytics
python run_analytics.py backfill --days 30

# Or run full pipeline
python run_analytics.py full-pipeline --days 30
```

### 4. Start Analytics Scheduler

**Option A: Standalone Process**

```bash
# Run scheduler in background
nohup python analytics_scheduler.py > analytics.log 2>&1 &
```

**Option B: Integrate into Dashboard**

Add to `app.py` at the top level (before page routing):

```python
import analytics_scheduler

# Start scheduler on first run
if 'scheduler_started' not in st.session_state:
    analytics_scheduler.start_scheduler()
    st.session_state.scheduler_started = True
```

---

## Testing the Integration

### 1. Check Database Tables

```bash
sqlite3 PortfolioGovernor.sqlite "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"
```

Expected output should include all 14 new tables:
- CorrelationMatrix
- DailyPerformance
- DrawdownHistory
- KillzonePerformance
- MarketConditions
- OptimizationSchedule
- ParameterImportance
- PerformanceAlerts
- PortfolioMetrics
- PredictedPerformance
- RegimePerformance
- SymbolCorrelationHistory
- SymbolPerformance
- TradePatterns

### 2. Verify Data Population

```bash
# Check if DailyPerformance has data
sqlite3 PortfolioGovernor.sqlite "SELECT COUNT(*) FROM DailyPerformance;"

# Check alerts
sqlite3 PortfolioGovernor.sqlite "SELECT COUNT(*) FROM PerformanceAlerts;"

# Check optimization schedule
sqlite3 PortfolioGovernor.sqlite "SELECT symbol, priority_score FROM OptimizationSchedule ORDER BY priority_score DESC LIMIT 5;"
```

### 3. Test Dashboard

```bash
# Restart dashboard
docker compose restart dashboard

# Or if running locally
streamlit run app.py
```

Visit each page and verify:
- ✅ Live Control Center shows equity curve
- ✅ Live Control Center shows active alerts
- ✅ Performance page shows symbol comparison matrix
- ✅ Performance page shows regime heatmap
- ✅ Optimization page shows priority queue

---

## Troubleshooting

### "No equity curve data available"

**Solution:** Run backfill command
```bash
python run_analytics.py backfill --days 30
```

### "No optimization schedule data"

**Solution:** Update optimization schedule
```bash
python run_analytics.py alerts
```

### "ModuleNotFoundError: analytics_widgets"

**Solution:** Ensure file exists and Python can find it
```bash
ls -la analytics_widgets.py
# Should show the file exists in dashboard directory
```

### Dashboard doesn't show new widgets

**Solution:** Clear Streamlit cache and restart
```python
# In app.py, add this temporarily
st.cache_data.clear()
```

Then restart dashboard:
```bash
docker compose restart dashboard
```

---

## Performance Optimization

For large databases (>100k trades):

1. **Add indexes** (already included in migration):
   - All tables have appropriate indexes
   - No action needed

2. **Archive old data** (optional):
   ```python
   # In analytics_engine.py, add retention policy
   def cleanup_old_analytics(days_to_keep=365):
       # Delete analytics older than 1 year
       pass
   ```

3. **Use date filters** in widgets:
   - All widgets accept `days` parameter
   - Default is 30-90 days
   - Adjust based on performance

---

## Next Steps

1. ✅ Apply database migrations
2. ✅ Install dependencies
3. ✅ Run backfill
4. ✅ Integrate widgets into app.py
5. ✅ Start scheduler
6. ✅ Test dashboard
7. 🚀 Monitor and enjoy enhanced analytics!

---

## Maintenance Schedule

**Daily (Automated):**
- Analytics aggregation (midnight)
- Alert checks (hourly)
- Correlation updates (2am)

**Weekly (Automated):**
- Regime/killzone analysis (Sunday 1am)
- Optimization schedule updates

**Monthly (Manual):**
- Review and acknowledge alerts
- Train ML models with new data
- Adjust alert thresholds if needed

---

## Support

If you encounter issues:

1. Check logs: `tail -f analytics.log`
2. Run test scripts: `python analytics_engine.py`
3. Verify database: `sqlite3 PortfolioGovernor.sqlite ".schema DailyPerformance"`
4. Check dependencies: `pip list | grep -E "(apscheduler|scikit|scipy)"`

For questions, refer to:
- `ANALYTICS_README.md` - Comprehensive documentation
- `MODULES_CREATED.txt` - Technical details
- Module docstrings - In-code documentation
