import streamlit as st
import sqlite3
import pandas as pd
import os
import time
import json
import numpy as np
from optimizer import PortfolioOptimizer, WalkForwardOptimizer
from database_manager import DatabaseManager
from optimizer_config import OPTIMIZATION_SETTINGS, TIMEFRAMES
from metrics import PerformanceMetrics
from scheduler import get_scheduler

# Page Config
st.set_page_config(
    page_title="Portfolio Governor Brain",
    page_icon="🧠",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Constants
DB_PATH = os.getenv("DB_PATH", "PortfolioGovernor.sqlite")

# Database Connection
@st.cache_resource
def get_connection():
    # Helper to check if file exists
    if not os.path.exists(DB_PATH):
        return None
    return sqlite3.connect(DB_PATH, check_same_thread=False)

def load_data(query):
    conn = get_connection()
    if conn:
        try:
            return pd.read_sql(query, conn)
        except Exception as e:
            st.error(f"Error reading DB: {e}")
            return pd.DataFrame()
    return pd.DataFrame()

# Sidebar
st.sidebar.title("🧠 Governor v3.0")
st.sidebar.markdown(f"**DB Status:** {'🟢 Connected' if os.path.exists(DB_PATH) else '🔴 Not Found'}")
if st.sidebar.button("🔄 Refresh Data"):
    st.cache_data.clear()

st.sidebar.markdown("---")

# Scheduler Controls
st.sidebar.subheader("⏰ Auto-Optimization")

# Initialize scheduler
scheduler = get_scheduler(DB_PATH)
scheduler_status = scheduler.get_status()

# Initialize session state for scheduler
if 'scheduler_enabled' not in st.session_state:
    st.session_state.scheduler_enabled = scheduler_status['running']

# Display current status
if scheduler_status['running']:
    st.sidebar.success("🟢 Scheduler Active")
    if scheduler_status['next_run']:
        st.sidebar.caption(f"Next run: {scheduler_status['next_run'].strftime('%m-%d %H:%M')}")
else:
    st.sidebar.info("⚪ Scheduler Inactive")

# Scheduler configuration in expander
with st.sidebar.expander("⚙️ Scheduler Settings"):
    schedule_type = st.selectbox(
        "Schedule",
        ["daily", "weekly", "monthly"],
        key="schedule_type"
    )

    col1, col2 = st.columns(2)
    with col1:
        schedule_hour = st.number_input("Hour (UTC)", 0, 23, 2, key="schedule_hour")
    with col2:
        schedule_minute = st.number_input("Minute", 0, 59, 0, key="schedule_minute")

    if schedule_type == "weekly":
        schedule_weekday = st.selectbox(
            "Day",
            ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"],
            key="schedule_weekday"
        )
    else:
        schedule_weekday = "monday"

    if not scheduler_status['running']:
        if st.button("▶️ Start Scheduler", key="start_scheduler"):
            success = scheduler.start_scheduler(
                schedule_type=schedule_type,
                hour=schedule_hour,
                minute=schedule_minute,
                weekday=schedule_weekday
            )
            if success:
                st.session_state.scheduler_enabled = True
                st.success("✅ Scheduler started!")
                st.rerun()
            else:
                st.error("❌ Failed to start scheduler")
    else:
        if st.button("⏸️ Stop Scheduler", key="stop_scheduler"):
            success = scheduler.stop_scheduler()
            if success:
                st.session_state.scheduler_enabled = False
                st.success("✅ Scheduler stopped!")
                st.rerun()

        if st.button("⚡ Run Now", key="run_now"):
            with st.spinner("Running optimization..."):
                scheduler.run_now()
            st.success("✅ Manual optimization triggered!")

st.sidebar.markdown("---")

page = st.sidebar.radio("Navigation", [
    "Dashboard",
    "AI Optimization",
    "Optimization History",
    "Configuration",
    "Trade Logs",
    "System Health"
])

# Main Layout
if page == "Dashboard":
    st.title("📊 Portfolio Overview")
    
    # 1. High Level Metrics from Configs
    df_configs = load_data("SELECT * FROM SymbolConfigs")
    
    if not df_configs.empty:
        col1, col2, col3, col4 = st.columns(4)
        col1.metric("Active Pairs", len(df_configs))
        col2.metric("Avg Risk Base", f"{df_configs['risk_base'].mean():.2f}%")
        col3.metric("Adaptive Risk", f"{len(df_configs[df_configs['enable_adaptive_risk'] == 1])}")
        col4.metric("Max Positions", df_configs['max_positions'].sum())

        st.subheader("🔥 Active Symbols & Confluence")
        st.dataframe(
            df_configs[['symbol', 'magic_number', 'risk_base', 'fixed_tp_r', 'min_confluence_entry']].style.format({'risk_base': '{:.2f}%', 'fixed_tp_r': '{:.1f}R'}),
            use_container_width=True
        )
    else:
        st.warning("No Symbol Configurations found in Database.")

elif page == "AI Optimization":
    st.title("🧠 AI Optimization Engine")
    st.markdown("Use Optuna to find the optimal parameters for your portfolio based on recent market data.")

    # Initialize database manager
    db_manager = DatabaseManager(DB_PATH)

    # Load available symbols
    df_configs = load_data("SELECT symbol FROM SymbolConfigs")

    if df_configs.empty:
        st.error("❌ No symbols configured in database. Please add symbols first.")
    else:
        available_symbols = df_configs['symbol'].tolist()

        st.subheader("⚙️ Optimization Settings")

        col1, col2 = st.columns(2)

        with col1:
            selected_symbol = st.selectbox(
                "Symbol",
                available_symbols,
                help="Choose the currency pair to optimize"
            )

        with col2:
            # Timeframe selector
            timeframe_options = {
                "M1 (1-Minute)": 1,
                "M5 (5-Minute)": 5,
                "M15 (15-Minute) ⭐ Recommended": 15,
                "M30 (30-Minute)": 30,
                "H1 (1-Hour)": 60,
                "H4 (4-Hour)": 240,
                "D1 (Daily)": 1440
            }

            selected_tf_name = st.selectbox(
                "Timeframe",
                list(timeframe_options.keys()),
                index=2,  # Default to M15
                help="Timeframe for optimization. Different timeframes need different parameters!"
            )

            selected_timeframe = timeframe_options[selected_tf_name]

        col1, col2, col3, col4 = st.columns(4)
        with col1:
            st.metric("Optimization Trials", OPTIMIZATION_SETTINGS["n_trials"])
        with col2:
            st.metric("Timeframe", selected_tf_name.split()[0])
        with col3:
            st.metric("Training Days", OPTIMIZATION_SETTINGS["train_days"])
        with col4:
            st.metric("Target Metric", OPTIMIZATION_SETTINGS["target_metric"].upper())

        st.info("💡 **Important:** Parameters optimized for M15 will NOT work well on H1 or D1. Always optimize for your actual trading timeframe!")

        # Timeframe impact explanation
        with st.expander("📚 Understanding Timeframe Selection"):
            st.markdown("""
            ### Why Timeframe Matters

            **Different timeframes require different parameters:**

            - **M1-M5 (Scalping):**
              - Need tight stops and quick exits
              - Many trades per day (50-100+)
              - Lower RSI periods (7-10)
              - Shorter EMA periods (20-50)

            - **M15-M30 (Day Trading) ⭐ Recommended:**
              - Balanced parameters
              - 5-15 trades per day
              - Standard RSI (14)
              - Medium EMA (50-100)

            - **H1-H4 (Swing Trading):**
              - Wider stops and targets
              - 2-5 trades per day
              - Higher RSI periods (14-21)
              - Longer EMA (100-200)

            - **D1 (Position Trading):**
              - Very wide stops
              - 1-3 trades per week
              - Long lookback periods
              - Large EMA (200+)

            **Data Requirements:**
            - M5: 5000 bars ≈ 17 days
            - M15: 3000 bars ≈ 31 days
            - H1: 1500 bars ≈ 62 days
            - H4: 1000 bars ≈ 166 days
            - D1: 500 bars ≈ 1.4 years

            **💡 Tip:** Start with M15, optimize for 2 weeks, then adjust based on results.
            """)

        st.info("💡 Note: The Optimizer uses recent history stored in 'MarketData'. Ensure you have run the EA to populate this data.")

        # Load current configuration for selected symbol
        current_config_df = load_data(f"SELECT * FROM SymbolConfigs WHERE symbol='{selected_symbol}'")

        if not current_config_df.empty:
            st.subheader("📊 Current Configuration")
            current_config = current_config_df.iloc[0].to_dict()

            # Display key parameters
            key_params = ['risk_base', 'fixed_tp_r', 'rsi_period', 'ema_period',
                         'trail_start_r', 'trail_atr_mult', 'min_confluence_entry']

            cols = st.columns(len(key_params))
            for i, param in enumerate(key_params):
                if param in current_config:
                    cols[i].metric(param.replace('_', ' ').title(), f"{current_config[param]}")

        st.markdown("---")

        # Optimization controls
        if 'optimization_running' not in st.session_state:
            st.session_state.optimization_running = False
        if 'optimization_results' not in st.session_state:
            st.session_state.optimization_results = None
        if 'bulk_optimization_results' not in st.session_state:
            st.session_state.bulk_optimization_results = None

        col_btn1, col_btn2, col_btn3 = st.columns([1, 1, 2])

        with col_btn1:
            if st.button("🚀 Start Optimization", disabled=st.session_state.optimization_running, type="primary"):
                st.session_state.optimization_running = True
                st.session_state.optimization_results = None

                # Create progress indicators
                progress_bar = st.progress(0)
                status_text = st.empty()

                try:
                    status_text.text(f"🔍 Loading market data for {selected_symbol}...")
                    progress_bar.progress(10)

                    # Check if market data exists
                    from optimizer_config import get_timeframe_settings
                    tf_settings = get_timeframe_settings(selected_timeframe)
                    df_market = db_manager.get_market_data(selected_symbol, selected_timeframe, limit=tf_settings['data_limit'])

                    if df_market.empty or len(df_market) < 100:
                        st.error(f"❌ Insufficient market data for {selected_symbol}. Please run the EA to collect data.")
                        st.session_state.optimization_running = False
                    else:
                        st.success(f"✅ Loaded {len(df_market)} data points")
                        progress_bar.progress(20)

                        status_text.text(f"🧠 Running Optuna optimization ({OPTIMIZATION_SETTINGS['n_trials']} trials on {tf_settings['timeframe_name']})...")

                        # Run optimization with selected timeframe
                        optimizer = PortfolioOptimizer(db_manager, timeframe=selected_timeframe)
                        results_dict = optimizer.run_optimization(selected_symbol)

                        progress_bar.progress(80)

                        if results_dict:
                            best_params = results_dict.get('best_params', {})
                            study = results_dict.get('study')
                            status_text.text("💾 Saving results to database...")

                            # Update database
                            success, message = optimizer.update_db(selected_symbol, best_params)

                            progress_bar.progress(100)

                            if success:
                                st.session_state.optimization_results = {
                                    'symbol': selected_symbol,
                                    'best_params': best_params,
                                    'message': message,
                                    'timestamp': time.time(),
                                    'study': study,
                                    'train_sharpe': results_dict.get('train_sharpe'),
                                    'test_sharpe': results_dict.get('test_sharpe'),
                                    'oos_degradation': results_dict.get('oos_degradation'),
                                    'overfitting_risk': results_dict.get('overfitting_risk')
                                }

                                # Log event
                                db_manager.log_event("Optimizer", "INFO",
                                    f"Optimization completed for {selected_symbol}")

                                status_text.text("✅ Optimization complete!")
                                st.success(message)

                                # Clear cache to reload data
                                st.cache_data.clear()

                            else:
                                st.error(f"❌ Failed to save results: {message}")
                        else:
                            st.error("❌ Optimization failed to produce results")

                except Exception as e:
                    st.error(f"❌ Optimization error: {str(e)}")
                    import traceback
                    st.code(traceback.format_exc())

                finally:
                    st.session_state.optimization_running = False

        with col_btn2:
            if st.button("🔥 Optimize All Pairs", disabled=st.session_state.optimization_running, type="secondary"):
                st.session_state.optimization_running = True
                st.session_state.bulk_optimization_results = []

                # Create main progress container
                main_progress = st.progress(0)
                main_status = st.empty()

                results_container = st.container()

                try:
                    # Use selected timeframe for bulk optimization too
                    from optimizer_config import get_timeframe_settings
                    tf_settings = get_timeframe_settings(selected_timeframe)

                    optimizer = PortfolioOptimizer(db_manager, timeframe=selected_timeframe)
                    total_symbols = len(available_symbols)
                    successful = 0
                    failed = 0

                    for idx, symbol in enumerate(available_symbols):
                        main_status.text(f"⚡ Optimizing {symbol} on {tf_settings['timeframe_name']} ({idx+1}/{total_symbols})...")

                        with results_container:
                            st.markdown(f"### 🎯 {symbol} ({tf_settings['timeframe_name']})")
                            symbol_progress = st.progress(0)
                            symbol_status = st.empty()

                        try:
                            # Load market data
                            symbol_status.text(f"📊 Loading {tf_settings['timeframe_name']} data...")
                            symbol_progress.progress(20)

                            df_market = db_manager.get_market_data(symbol, selected_timeframe, limit=tf_settings['data_limit'])

                            if df_market.empty or len(df_market) < 100:
                                symbol_status.warning(f"⚠️ Insufficient data - Skipped")
                                failed += 1
                                st.session_state.bulk_optimization_results.append({
                                    'symbol': symbol,
                                    'status': 'skipped',
                                    'reason': 'Insufficient market data'
                                })
                                continue

                            # Run optimization
                            symbol_status.text(f"🧠 Optimizing ({OPTIMIZATION_SETTINGS['n_trials']} trials)...")
                            symbol_progress.progress(40)

                            best_params = optimizer.run_optimization(symbol)
                            symbol_progress.progress(80)

                            if best_params:
                                # Save to database
                                symbol_status.text("💾 Saving results...")
                                success, message = optimizer.update_db(symbol, best_params)
                                symbol_progress.progress(100)

                                if success:
                                    symbol_status.success(f"✅ Optimized successfully!")
                                    successful += 1

                                    # Log event
                                    db_manager.log_event("BulkOptimizer", "INFO",
                                        f"Bulk optimization completed for {symbol}")

                                    st.session_state.bulk_optimization_results.append({
                                        'symbol': symbol,
                                        'status': 'success',
                                        'params': best_params,
                                        'timestamp': time.time()
                                    })
                                else:
                                    symbol_status.error(f"❌ Save failed: {message}")
                                    failed += 1
                                    st.session_state.bulk_optimization_results.append({
                                        'symbol': symbol,
                                        'status': 'failed',
                                        'reason': message
                                    })
                            else:
                                symbol_status.error("❌ Optimization failed")
                                failed += 1
                                st.session_state.bulk_optimization_results.append({
                                    'symbol': symbol,
                                    'status': 'failed',
                                    'reason': 'No results produced'
                                })

                        except Exception as e:
                            symbol_status.error(f"❌ Error: {str(e)}")
                            failed += 1
                            st.session_state.bulk_optimization_results.append({
                                'symbol': symbol,
                                'status': 'error',
                                'reason': str(e)
                            })

                        # Update main progress
                        main_progress.progress((idx + 1) / total_symbols)

                    # Final summary
                    main_status.success(f"🎉 Bulk Optimization Complete: {successful} successful, {failed} failed/skipped")

                    # Clear cache
                    st.cache_data.clear()

                except Exception as e:
                    st.error(f"❌ Bulk optimization error: {str(e)}")
                    import traceback
                    st.code(traceback.format_exc())

                finally:
                    st.session_state.optimization_running = False

        with col_btn3:
            if st.button("🔄 Refresh Data"):
                st.cache_data.clear()
                st.rerun()

        # Display optimization results
        if st.session_state.optimization_results:
            st.markdown("---")
            st.subheader("✨ Optimization Results")

            results = st.session_state.optimization_results

            st.success(f"✅ {results['message']}")

            # Load updated configuration
            updated_config_df = load_data(f"SELECT * FROM SymbolConfigs WHERE symbol='{results['symbol']}'")

            if not updated_config_df.empty:
                updated_config = updated_config_df.iloc[0].to_dict()

                # Before/After Comparison
                st.subheader("📈 Parameter Changes")

                comparison_data = []
                for param, new_value in results['best_params'].items():
                    old_value = current_config.get(param, 'N/A')

                    if old_value != 'N/A' and old_value != new_value:
                        try:
                            if isinstance(new_value, (int, float)) and isinstance(old_value, (int, float)):
                                delta = ((new_value - old_value) / old_value * 100) if old_value != 0 else 0
                                delta_str = f"{delta:+.1f}%"
                            else:
                                delta_str = "Changed"
                        except:
                            delta_str = "Changed"
                    else:
                        delta_str = "No change"

                    comparison_data.append({
                        'Parameter': param,
                        'Old Value': f"{old_value}",
                        'New Value': f"{new_value}",
                        'Change': delta_str
                    })

                df_comparison = pd.DataFrame(comparison_data)
                st.dataframe(df_comparison, use_container_width=True, hide_index=True)

                # Show OOS validation metrics if available
                if results.get('train_sharpe') is not None:
                    st.subheader("🧪 Out-of-Sample Validation")

                    col1, col2, col3, col4 = st.columns(4)
                    col1.metric("Train Sharpe", f"{results['train_sharpe']:.3f}")
                    col2.metric("Test Sharpe", f"{results['test_sharpe']:.3f}")
                    col3.metric("Degradation", f"{results['oos_degradation']:.3f}")

                    risk = results.get('overfitting_risk', 'UNKNOWN')
                    risk_emoji = {"LOW": "🟢", "MEDIUM": "🟡", "HIGH": "🔴"}.get(risk, "⚪")
                    col4.metric("Overfitting Risk", f"{risk_emoji} {risk}")

                    if risk == "HIGH":
                        st.warning("⚠️ High overfitting risk detected. Parameters may not generalize well to new data.")
                    elif risk == "MEDIUM":
                        st.info("ℹ️ Moderate overfitting detected. Monitor performance carefully.")
                    else:
                        st.success("✅ Low overfitting risk. Parameters show good generalization.")

                # Show parameter importance if study is available
                if results.get('study') is not None:
                    st.subheader("🎯 Parameter Importance Analysis")
                    st.markdown("Which parameters had the biggest impact on performance?")

                    try:
                        importance_data = optimizer.analyze_parameter_importance(results['study'])

                        if importance_data['importances']:
                            # Create DataFrame for visualization
                            df_importance = pd.DataFrame([
                                {'Parameter': k, 'Importance': v}
                                for k, v in list(importance_data['importances'].items())[:10]
                            ])

                            # Bar chart
                            st.bar_chart(df_importance.set_index('Parameter')['Importance'])

                            # Highlight top 5
                            top_5_names = [p[0] for p in importance_data['top_5']]
                            st.success(f"🔝 **Top 5 most important:** {', '.join(top_5_names)}")

                            # Full table in expander
                            with st.expander("📊 View All Parameter Importances"):
                                st.dataframe(df_importance, use_container_width=True, hide_index=True)
                        else:
                            st.info("Parameter importance analysis not available for this optimization.")
                    except Exception as e:
                        st.warning(f"Could not calculate parameter importance: {e}")

                st.info(f"⏰ Optimized at: {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(results['timestamp']))}")

        # Display bulk optimization results
        if st.session_state.bulk_optimization_results:
            st.markdown("---")
            st.subheader("📊 Bulk Optimization Summary")

            bulk_results = st.session_state.bulk_optimization_results

            # Count statuses
            successful = sum(1 for r in bulk_results if r['status'] == 'success')
            failed = sum(1 for r in bulk_results if r['status'] in ['failed', 'error'])
            skipped = sum(1 for r in bulk_results if r['status'] == 'skipped')

            # Display metrics
            col1, col2, col3, col4 = st.columns(4)
            col1.metric("Total Pairs", len(bulk_results))
            col2.metric("✅ Successful", successful)
            col3.metric("❌ Failed", failed)
            col4.metric("⚠️ Skipped", skipped)

            # Display detailed results table
            st.subheader("📋 Detailed Results")

            summary_data = []
            for result in bulk_results:
                if result['status'] == 'success':
                    param_count = len(result.get('params', {}))
                    status_emoji = "✅"
                    details = f"{param_count} parameters optimized"
                elif result['status'] == 'skipped':
                    status_emoji = "⚠️"
                    details = result.get('reason', 'Skipped')
                else:
                    status_emoji = "❌"
                    details = result.get('reason', 'Failed')

                summary_data.append({
                    'Status': status_emoji,
                    'Symbol': result['symbol'],
                    'Result': result['status'].upper(),
                    'Details': details
                })

            df_summary = pd.DataFrame(summary_data)
            st.dataframe(df_summary, use_container_width=True, hide_index=True)

            # Show expanded view for successful optimizations
            if successful > 0:
                st.subheader("🎯 Successful Optimizations")

                for result in bulk_results:
                    if result['status'] == 'success':
                        with st.expander(f"📈 {result['symbol']} - View Changes"):
                            # Load current and updated configs
                            current_cfg = load_data(f"SELECT * FROM SymbolConfigs WHERE symbol='{result['symbol']}'")

                            if not current_cfg.empty:
                                current_dict = current_cfg.iloc[0].to_dict()
                                params = result['params']

                                change_data = []
                                for param, new_val in params.items():
                                    old_val = current_dict.get(param, 'N/A')
                                    if old_val != 'N/A' and old_val != new_val:
                                        try:
                                            if isinstance(new_val, (int, float)) and isinstance(old_val, (int, float)):
                                                delta = ((new_val - old_val) / old_val * 100) if old_val != 0 else 0
                                                delta_str = f"{delta:+.1f}%"
                                            else:
                                                delta_str = "Changed"
                                        except:
                                            delta_str = "Changed"

                                        change_data.append({
                                            'Parameter': param,
                                            'Before': f"{old_val}",
                                            'After': f"{new_val}",
                                            'Δ': delta_str
                                        })

                                if change_data:
                                    df_changes = pd.DataFrame(change_data)
                                    st.dataframe(df_changes, use_container_width=True, hide_index=True)
                                else:
                                    st.info("No parameter changes detected")

                            st.caption(f"⏰ Optimized at: {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(result.get('timestamp', 0)))}")

            if st.button("🗑️ Clear Bulk Results"):
                st.session_state.bulk_optimization_results = None
                st.rerun()

elif page == "Optimization History":
    st.title("📜 Optimization History")
    st.markdown("Track and compare past optimization runs")

    # Initialize database manager
    db_manager = DatabaseManager(DB_PATH)

    # Load optimization history
    df_history = db_manager.get_optimization_history(limit=100)

    if not df_history.empty:
        # Filters
        st.subheader("🔍 Filters")
        col1, col2, col3, col4 = st.columns(4)

        with col1:
            symbols = ["All"] + sorted(df_history['symbol'].unique().tolist())
            filter_symbol = st.selectbox("Symbol", symbols)

        with col2:
            modes = ["All", "single", "bulk", "multi_objective", "portfolio"]
            filter_mode = st.selectbox("Mode", modes)

        with col3:
            statuses = ["All", "completed", "running", "failed"]
            filter_status = st.selectbox("Status", statuses)

        with col4:
            risk_levels = ["All", "LOW", "MEDIUM", "HIGH"]
            filter_risk = st.selectbox("Overfitting Risk", risk_levels)

        # Apply filters
        df_filtered = df_history.copy()
        if filter_symbol != "All":
            df_filtered = df_filtered[df_filtered['symbol'] == filter_symbol]
        if filter_mode != "All":
            df_filtered = df_filtered[df_filtered['mode'] == filter_mode]
        if filter_status != "All":
            df_filtered = df_filtered[df_filtered['status'] == filter_status]
        if filter_risk != "All":
            df_filtered = df_filtered[df_filtered['overfitting_risk'] == filter_risk]

        # Display summary metrics
        st.subheader("📊 Summary Metrics")
        col1, col2, col3, col4 = st.columns(4)

        col1.metric("Total Runs", len(df_filtered))

        if len(df_filtered) > 0:
            avg_sharpe = df_filtered['best_sharpe'].mean()
            col2.metric("Avg Sharpe", f"{avg_sharpe:.3f}" if not pd.isna(avg_sharpe) else "N/A")

            avg_oos = df_filtered['oos_degradation'].mean()
            col3.metric("Avg OOS Degradation", f"{avg_oos:.3f}" if not pd.isna(avg_oos) else "N/A")

            success_rate = (df_filtered['status'] == 'completed').sum() / len(df_filtered) * 100
            col4.metric("Success Rate", f"{success_rate:.1f}%")

        # Sharpe evolution chart
        if len(df_filtered) > 0 and 'started_at' in df_filtered.columns:
            st.subheader("📈 Performance Over Time")

            # Convert timestamp to datetime
            df_chart = df_filtered.copy()
            df_chart['date'] = pd.to_datetime(df_chart['started_at'], unit='s')

            # Plot train vs test sharpe if available
            chart_cols = []
            if 'train_sharpe' in df_chart.columns and df_chart['train_sharpe'].notna().any():
                chart_cols.append('train_sharpe')
            if 'test_sharpe' in df_chart.columns and df_chart['test_sharpe'].notna().any():
                chart_cols.append('test_sharpe')
            if 'best_sharpe' in df_chart.columns:
                chart_cols.append('best_sharpe')

            if chart_cols:
                chart_data = df_chart[['date'] + chart_cols].set_index('date')
                st.line_chart(chart_data)

        # Detailed table
        st.subheader("📋 Run Details")

        # Format the display dataframe
        display_df = df_filtered[[
            'id', 'symbol', 'mode', 'status', 'started_at',
            'n_trials', 'best_sharpe', 'train_sharpe', 'test_sharpe',
            'oos_degradation', 'overfitting_risk'
        ]].copy()

        # Convert timestamp to readable format
        display_df['started_at'] = pd.to_datetime(display_df['started_at'], unit='s').dt.strftime('%Y-%m-%d %H:%M')

        st.dataframe(display_df, use_container_width=True, hide_index=True)

        # Click to view individual run details
        st.subheader("🔍 Detailed Run Analysis")

        selected_run_id = st.selectbox("Select Run ID to View Details", df_filtered['id'].tolist())

        if selected_run_id:
            run_data = df_filtered[df_filtered['id'] == selected_run_id].iloc[0]

            with st.expander(f"📊 Run #{selected_run_id} - {run_data['symbol']}", expanded=True):
                col1, col2, col3 = st.columns(3)

                with col1:
                    st.metric("Mode", run_data['mode'])
                    st.metric("Status", run_data['status'])
                    st.metric("Trials", run_data['n_trials'])

                with col2:
                    if not pd.isna(run_data.get('train_sharpe')):
                        st.metric("Train Sharpe", f"{run_data['train_sharpe']:.3f}")
                    if not pd.isna(run_data.get('test_sharpe')):
                        st.metric("Test Sharpe", f"{run_data['test_sharpe']:.3f}")
                    st.metric("Best Sharpe", f"{run_data['best_sharpe']:.3f}")

                with col3:
                    if not pd.isna(run_data.get('oos_degradation')):
                        st.metric("OOS Degradation", f"{run_data['oos_degradation']:.3f}")
                    if run_data.get('overfitting_risk'):
                        risk = run_data['overfitting_risk']
                        risk_emoji = {"LOW": "🟢", "MEDIUM": "🟡", "HIGH": "🔴"}.get(risk, "⚪")
                        st.metric("Overfitting Risk", f"{risk_emoji} {risk}")
                    st.metric("Parameters Optimized", run_data.get('param_count', 'N/A'))

                # Show parameters if available
                if run_data.get('best_params'):
                    st.subheader("🔧 Optimized Parameters")
                    try:
                        params = json.loads(run_data['best_params']) if isinstance(run_data['best_params'], str) else run_data['best_params']

                        # Create a nice display
                        param_cols = st.columns(3)
                        for idx, (param, value) in enumerate(params.items()):
                            col_idx = idx % 3
                            with param_cols[col_idx]:
                                st.text(f"{param}: {value}")
                    except Exception as e:
                        st.error(f"Could not parse parameters: {e}")

                # Show error message if failed
                if run_data['status'] == 'failed' and run_data.get('error_message'):
                    st.error(f"Error: {run_data['error_message']}")

        # Parameter comparison tool
        st.markdown("---")
        st.subheader("🔬 Parameter Explorer")
        st.markdown("Compare parameters across multiple runs")

        # Filter to completed runs only for comparison
        completed_runs = df_filtered[df_filtered['status'] == 'completed']

        if len(completed_runs) >= 2:
            # Allow selection of up to 5 runs
            max_runs = min(5, len(completed_runs))
            selected_runs = st.multiselect(
                "Select runs to compare (max 5)",
                completed_runs['id'].tolist(),
                max_selections=max_runs
            )

            if len(selected_runs) >= 2:
                comparison_data = []

                for run_id in selected_runs:
                    run = completed_runs[completed_runs['id'] == run_id].iloc[0]
                    try:
                        params = json.loads(run['best_params']) if isinstance(run['best_params'], str) else run['best_params']

                        row = {
                            'Run ID': run_id,
                            'Symbol': run['symbol'],
                            'Sharpe': run['best_sharpe'],
                            'Date': pd.to_datetime(run['started_at'], unit='s').strftime('%Y-%m-%d')
                        }
                        row.update(params)
                        comparison_data.append(row)
                    except:
                        continue

                if comparison_data:
                    df_comparison = pd.DataFrame(comparison_data)
                    st.dataframe(df_comparison, use_container_width=True, hide_index=True)

                    # Visualize key parameter changes
                    st.subheader("📊 Parameter Evolution")
                    key_params = ['risk_base', 'fixed_tp_r', 'rsi_period', 'ema_period', 'trail_start_r']

                    available_params = [p for p in key_params if p in df_comparison.columns]

                    if available_params:
                        selected_param = st.selectbox("Select parameter to visualize", available_params)

                        if selected_param:
                            chart_data = df_comparison[['Run ID', selected_param]].set_index('Run ID')
                            st.line_chart(chart_data)
                    else:
                        st.info("No common parameters found across selected runs.")
        else:
            st.info("Need at least 2 completed optimization runs to enable parameter comparison.")

    else:
        st.info("No optimization history available yet. Run some optimizations to see results here!")

        st.markdown("""
        ### 💡 Tips for Using Optimization History

        - Track performance improvements over time
        - Compare different optimization strategies
        - Identify overfitting trends
        - Find optimal parameter ranges for your symbols
        - Monitor out-of-sample degradation
        """)

elif page == "Configuration":
    st.title("⚙️ Symbol Configuration")
    st.markdown("View and Edit Symbol Parameters stored in SQLite.")

    col1, col2 = st.columns([3, 1])
    with col2:
        if st.button("🔄 Reload from Database"):
            st.cache_data.clear()
            st.rerun()

    df = load_data("SELECT * FROM SymbolConfigs")

    if not df.empty:
        st.subheader(f"📋 {len(df)} Symbol(s) Configured")

        # Add optimization status if available from SystemLogs
        try:
            db_manager = DatabaseManager(DB_PATH)
            recent_logs = db_manager.get_logs(limit=50)

            if not recent_logs.empty:
                # Find recent optimization events
                opt_logs = recent_logs[recent_logs['source'] == 'Optimizer']

                if not opt_logs.empty:
                    st.info(f"🧠 Last optimization activity: {opt_logs.iloc[0]['message']}")
        except:
            pass

        # Display editable configuration
        st.data_editor(df, num_rows="dynamic", use_container_width=True)

        st.markdown("---")

        # Configuration Management Section
        st.subheader("🔄 Configuration Management")

        # Create tabs for different management features
        tab1, tab2, tab3 = st.tabs(["📦 Backup & Restore", "🧪 A/B Testing", "📊 Portfolio Optimization"])

        with tab1:
            st.markdown("### Backup & Restore Configurations")

            col1, col2 = st.columns(2)

            with col1:
                st.markdown("#### 📦 Backups")

                # Select symbol to view backups
                backup_symbol = st.selectbox("Select Symbol", df['symbol'].tolist(), key="backup_symbol")

                if backup_symbol:
                    # Load backups for this symbol
                    backups_df = db_manager.get_backups(backup_symbol, limit=10)

                    if not backups_df.empty:
                        st.dataframe(backups_df, use_container_width=True, hide_index=True)

                        # Restore functionality
                        selected_backup = st.selectbox(
                            "Select backup to restore",
                            backups_df['backup_id'].tolist(),
                            format_func=lambda x: f"Backup #{x} - {backups_df[backups_df['backup_id']==x]['backed_up_at'].iloc[0]}"
                        )

                        if st.button("🔙 Restore This Backup", type="primary"):
                            with st.spinner("Restoring configuration..."):
                                success = db_manager.restore_config(backup_symbol, selected_backup)

                            if success:
                                st.success(f"✅ Configuration restored for {backup_symbol}!")
                                st.cache_data.clear()
                                time.sleep(1)
                                st.rerun()
                            else:
                                st.error("❌ Restore failed. Check logs.")
                    else:
                        st.info(f"No backups available for {backup_symbol}")

                        # Manual backup button
                        if st.button("📸 Create Manual Backup"):
                            success = db_manager.backup_config(backup_symbol, reason="manual_backup")
                            if success:
                                st.success(f"✅ Backup created for {backup_symbol}")
                                st.rerun()
                            else:
                                st.error("❌ Backup failed")

            with col2:
                st.markdown("#### ℹ️ Backup Information")
                st.info("""
                **Automatic Backups:**
                - Created before each optimization
                - Created by scheduled optimizations
                - Stored in SymbolConfigsBackup table

                **Manual Backups:**
                - Create backups before making changes
                - Restore any previous configuration
                - Keep up to 10 most recent backups

                **Use Cases:**
                - Revert after failed optimization
                - Compare performance of different configs
                - Safety net for configuration changes
                """)

        with tab2:
            st.markdown("### 🧪 A/B Testing")
            st.info("A/B Testing allows you to compare current vs optimized parameters in live trading")

            # A/B test creation
            st.markdown("#### Create New A/B Test")

            ab_symbol = st.selectbox("Select Symbol", df['symbol'].tolist(), key="ab_symbol")

            if ab_symbol:
                # Load current config
                current_config_df = load_data(f"SELECT * FROM SymbolConfigs WHERE symbol='{ab_symbol}'")

                if not current_config_df.empty:
                    current_config = current_config_df.iloc[0].to_dict()

                    # Load latest optimization for this symbol
                    latest_opt = db_manager.get_optimization_history(symbol=ab_symbol, limit=1)

                    if not latest_opt.empty and latest_opt.iloc[0].get('best_params'):
                        latest_params = json.loads(latest_opt.iloc[0]['best_params']) if isinstance(latest_opt.iloc[0]['best_params'], str) else latest_opt.iloc[0]['best_params']

                        col1, col2 = st.columns(2)

                        with col1:
                            st.markdown("**Config A (Current)**")
                            st.json({k: v for k, v in current_config.items() if k in ['risk_base', 'fixed_tp_r', 'rsi_period', 'ema_period']})

                        with col2:
                            st.markdown("**Config B (Optimized)**")
                            st.json({k: v for k, v in latest_params.items() if k in ['risk_base', 'fixed_tp_r', 'rsi_period', 'ema_period']})

                        # Test duration
                        test_duration_days = st.slider("Test Duration (days)", 7, 30, 14)

                        if st.button("🚀 Start A/B Test", type="primary"):
                            # Create A/B test entry
                            try:
                                conn = get_connection()
                                if conn:
                                    cursor = conn.cursor()

                                    start_time = int(time.time())
                                    end_time = start_time + (test_duration_days * 86400)

                                    cursor.execute("""
                                        INSERT INTO ABTests (
                                            symbol, start_time, end_time,
                                            config_a, config_b,
                                            status
                                        ) VALUES (?, ?, ?, ?, ?, ?)
                                    """, (
                                        ab_symbol,
                                        start_time,
                                        end_time,
                                        json.dumps(current_config),
                                        json.dumps(latest_params),
                                        'running'
                                    ))

                                    conn.commit()
                                    conn.close()

                                    st.success(f"✅ A/B test started for {ab_symbol}! Duration: {test_duration_days} days")
                                    st.info("📊 Results will be available after the test period. Monitor both configurations in live trading.")

                                    # Log event
                                    db_manager.log_event("ABTest", "INFO", f"A/B test started for {ab_symbol}")
                                else:
                                    st.error("❌ Database connection failed")
                            except Exception as e:
                                st.error(f"❌ Failed to create A/B test: {e}")
                    else:
                        st.warning(f"⚠️ No optimized parameters available for {ab_symbol}. Run optimization first.")

                # Show active A/B tests
                st.markdown("---")
                st.markdown("#### Active A/B Tests")

                try:
                    active_tests = load_data("SELECT * FROM ABTests WHERE status='running' ORDER BY start_time DESC")

                    if not active_tests.empty:
                        for idx, test in active_tests.iterrows():
                            with st.expander(f"🧪 {test['symbol']} - Test #{test['test_id']}"):
                                start_date = pd.to_datetime(test['start_time'], unit='s')
                                end_date = pd.to_datetime(test['end_time'], unit='s')

                                st.write(f"**Started:** {start_date.strftime('%Y-%m-%d %H:%M')}")
                                st.write(f"**Ends:** {end_date.strftime('%Y-%m-%d %H:%M')}")

                                # Progress bar
                                current_time = int(time.time())
                                progress = min(1.0, (current_time - test['start_time']) / (test['end_time'] - test['start_time']))
                                st.progress(progress)

                                col1, col2 = st.columns(2)
                                with col1:
                                    st.metric("Config A Trades", test.get('trades_a', 0))
                                    st.metric("Config A Sharpe", f"{test.get('sharpe_a', 0):.3f}")

                                with col2:
                                    st.metric("Config B Trades", test.get('trades_b', 0))
                                    st.metric("Config B Sharpe", f"{test.get('sharpe_b', 0):.3f}")

                                if st.button(f"🛑 Stop Test #{test['test_id']}", key=f"stop_test_{test['test_id']}"):
                                    # Update test status
                                    conn = get_connection()
                                    if conn:
                                        cursor = conn.cursor()
                                        cursor.execute("UPDATE ABTests SET status='stopped' WHERE test_id=?", (test['test_id'],))
                                        conn.commit()
                                        conn.close()

                                        st.success("✅ Test stopped")
                                        st.rerun()
                    else:
                        st.info("No active A/B tests. Create one above to get started!")

                except Exception as e:
                    st.warning(f"Could not load A/B tests: {e}")

        with tab3:
            st.markdown("### 📊 Portfolio-Level Optimization")
            st.info("Optimize parameters across all symbols considering correlations")

            if st.button("🎯 Run Portfolio Optimization", type="primary"):
                with st.spinner("Running portfolio optimization..."):
                    try:
                        from optimizer import PortfolioLevelOptimizer

                        symbols = df['symbol'].tolist()

                        portfolio_optimizer = PortfolioLevelOptimizer(db_manager, symbols)
                        results = portfolio_optimizer.run_portfolio_optimization(n_trials=50)

                        if results:
                            st.success("✅ Portfolio optimization complete!")

                            col1, col2, col3 = st.columns(3)
                            col1.metric("Portfolio Sharpe", f"{results['portfolio_sharpe']:.3f}")
                            col2.metric("Symbols Analyzed", results['symbols_count'])
                            col3.metric("High Correlation Pairs", len(results.get('high_correlation_pairs', [])))

                            st.subheader("🔧 Optimal Portfolio Parameters")
                            st.json(results['best_params'])

                            # Show correlation matrix
                            if results.get('correlation_matrix'):
                                st.subheader("🔗 Correlation Matrix")
                                corr_df = pd.DataFrame(results['correlation_matrix'])
                                st.dataframe(corr_df.style.background_gradient(cmap='coolwarm', vmin=-1, vmax=1))

                            # Show high correlation pairs
                            if results.get('high_correlation_pairs'):
                                st.warning("⚠️ High Correlation Pairs (Consider reducing position sizes)")
                                for pair in results['high_correlation_pairs']:
                                    st.write(f"  • {pair['symbol1']} ↔ {pair['symbol2']}: {pair['correlation']:.3f}")
                        else:
                            st.error("❌ Portfolio optimization failed")

                    except Exception as e:
                        st.error(f"❌ Error: {e}")
                        import traceback
                        st.code(traceback.format_exc())

        st.markdown("---")
        st.caption("💡 Tip: Use the AI Optimization page to automatically tune parameters based on historical data.")

    else:
        st.info("No configurations available.")

elif page == "Trade Logs":
    st.title("📜 Trade History")
    # Placeholder query - assumes we might have a trades table later
    # For now, show structure of DB
    conn = get_connection()
    if conn:
        tables = pd.read_sql("SELECT name FROM sqlite_master WHERE type='table';", conn)
        st.write("Available Tables:", tables)
        
        selected_table = st.selectbox("Select Table to Inspect", tables['name'].tolist())
        if selected_table:
            df_table = load_data(f"SELECT * FROM {selected_table} ORDER BY rowid DESC LIMIT 100")
            st.dataframe(df_table, use_container_width=True)

elif page == "System Health":
    st.title("💓 System Heartbeat")

    # Get current timestamp
    current_time = int(time.time())

    # Get Governor State
    df_state = load_data("SELECT * FROM GovernorState")

    # Get trade statistics
    df_stats = load_data("""
        SELECT
            COUNT(*) as total_trades,
            SUM(CASE WHEN profit > 0 THEN 1 ELSE 0 END) as winning_trades,
            SUM(CASE WHEN profit < 0 THEN 1 ELSE 0 END) as losing_trades,
            SUM(profit) as total_profit,
            AVG(profit) as avg_profit,
            MAX(close_time) as last_trade_time
        FROM Trades
    """)

    # System Status Indicators
    st.subheader("🔍 System Status")

    if not df_stats.empty and df_stats.iloc[0]['last_trade_time']:
        last_trade_time = int(df_stats.iloc[0]['last_trade_time'])
        time_since_last_trade = current_time - last_trade_time

        # Status indicator based on last activity
        if time_since_last_trade < 3600:  # Less than 1 hour
            status_color = "🟢"
            status_text = "Active"
        elif time_since_last_trade < 86400:  # Less than 1 day
            status_color = "🟡"
            status_text = "Idle"
        else:
            status_color = "🔴"
            status_text = "Inactive"

        col1, col2, col3, col4 = st.columns(4)
        col1.metric("System Status", f"{status_color} {status_text}")
        col2.metric("Last Trade", f"{time_since_last_trade // 60} min ago" if time_since_last_trade < 3600 else f"{time_since_last_trade // 3600} hrs ago")
        col3.metric("DB Status", "🟢 Connected")

        df_symbol_count = load_data("SELECT COUNT(*) as count FROM SymbolConfigs")
        symbol_count = int(df_symbol_count.iloc[0]['count']) if not df_symbol_count.empty else 0
        col4.metric("Total Symbols", symbol_count)

    # Trading Performance Metrics
    st.subheader("📊 Trading Performance")

    if not df_stats.empty:
        total = int(df_stats.iloc[0]['total_trades'])
        wins = int(df_stats.iloc[0]['winning_trades'])
        losses = int(df_stats.iloc[0]['losing_trades'])
        win_rate = (wins / total * 100) if total > 0 else 0

        col1, col2, col3, col4, col5 = st.columns(5)
        col1.metric("Total Trades", total)
        col2.metric("Winning", wins, delta=f"{win_rate:.1f}%")
        col3.metric("Losing", losses, delta=f"{100-win_rate:.1f}%", delta_color="inverse")
        col4.metric("Total P/L", f"${df_stats.iloc[0]['total_profit']:.2f}", delta="Cumulative")
        col5.metric("Avg P/L", f"${df_stats.iloc[0]['avg_profit']:.2f}", delta="Per Trade")

    # Symbol Activity Breakdown
    st.subheader("📈 Symbol Activity")

    df_symbol_stats = load_data("""
        SELECT
            symbol,
            COUNT(*) as trades,
            SUM(CASE WHEN profit > 0 THEN 1 ELSE 0 END) as wins,
            SUM(profit) as total_profit,
            AVG(profit) as avg_profit,
            MAX(close_time) as last_trade
        FROM Trades
        GROUP BY symbol
        ORDER BY total_profit DESC
    """)

    if not df_symbol_stats.empty:
        df_symbol_stats['win_rate'] = (df_symbol_stats['wins'] / df_symbol_stats['trades'] * 100).round(1)
        st.dataframe(
            df_symbol_stats[['symbol', 'trades', 'wins', 'win_rate', 'total_profit', 'avg_profit']].style.format({
                'win_rate': '{:.1f}%',
                'total_profit': '${:.2f}',
                'avg_profit': '${:.2f}'
            }),
            use_container_width=True
        )

    # Recent Activity Log
    st.subheader("📜 Recent Activity")

    df_recent = load_data("""
        SELECT
            ticket,
            symbol,
            DATETIME(entry_time, 'unixepoch') as entry_time,
            DATETIME(close_time, 'unixepoch') as close_time,
            type,
            lots,
            profit,
            magic
        FROM Trades
        ORDER BY close_time DESC
        LIMIT 15
    """)

    if not df_recent.empty:
        st.dataframe(
            df_recent.style.format({'lots': '{:.2f}', 'profit': '${:.2f}'}),
            use_container_width=True
        )
    else:
        st.info("No recent trading activity.")

    # Governor State
    if not df_state.empty:
        st.subheader("⚙️ Governor State")
        st.dataframe(df_state, use_container_width=True)

    # System Logs
    st.subheader("📝 System Logs")
    
    # Auto-refresh mechanism
    if st.checkbox("Auto-refresh Logs (5s)", value=False):
        time.sleep(5)
        st.rerun()
    
    df_logs = load_data("SELECT * FROM SystemLogs ORDER BY time DESC LIMIT 200")
    
    if not df_logs.empty:
        # Convert timestamp
        df_logs['time'] = pd.to_datetime(df_logs['time'], unit='s')
        
        # Color coding
        def color_row(row):
            if row['level'] == 'ERROR':
                return ['background-color: #ffcccc'] * len(row)
            elif row['source'] == 'Heartbeat':
                return ['background-color: #e6f3ff'] * len(row)
            return [''] * len(row)
            
        st.dataframe(
            df_logs[['time', 'source', 'level', 'message']].style.apply(color_row, axis=1),
            use_container_width=True,
            height=400
        )
    else:
        st.info("No system logs found yet. Waiting for Governor startup...")
