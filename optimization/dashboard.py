import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import optuna
import os
import sys
from datetime import datetime, timedelta

# Add lib to path
sys.path.append(os.path.join(os.path.dirname(__file__), "lib"))
import optimizer_core

# Page config with custom theme
st.set_page_config(
    page_title="Optima - AI Trading Optimization",
    layout="wide",
    initial_sidebar_state="expanded",
    menu_items={
        'About': "Optima: Institutional-grade AI optimization for trading strategies"
    }
)

# Custom CSS for better styling
st.markdown("""
    <style>
    .main-header {
        font-size: 2.5rem;
        font-weight: 700;
        background: linear-gradient(120deg, #1e3c72 0%, #2a5298 100%);
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
        margin-bottom: 0.5rem;
    }
    .sub-header {
        color: #666;
        font-size: 1.1rem;
        margin-bottom: 2rem;
    }
    .metric-card {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        padding: 1.5rem;
        border-radius: 10px;
        color: white;
        text-align: center;
    }
    .stButton>button {
        width: 100%;
        border-radius: 8px;
        height: 3rem;
        font-weight: 600;
        font-size: 1.1rem;
    }
    .sidebar-section {
        background-color: #f8f9fa;
        padding: 1rem;
        border-radius: 8px;
        margin-bottom: 1rem;
    }
    </style>
""", unsafe_allow_html=True)

# Header
st.markdown('<p class="main-header">🛡️ Optima: AI Trading Optimization</p>', unsafe_allow_html=True)
st.markdown('<p class="sub-header">Institutional-grade parameter optimization powered by advanced AI</p>', unsafe_allow_html=True)

# Initialize session state
if "params" not in st.session_state:
    st.session_state.params = [
        {"name": "InpRisk_Reward_Ratio", "type": "float", "min": 2.0, "max": 5.0, "step": 0.5},
        {"name": "InpADX_Threshold", "type": "int", "min": 15, "max": 30, "step": 1},
        {"name": "InpCooldownMinutes", "type": "int", "min": 15, "max": 120, "step": 15}
    ]

if "optimization_running" not in st.session_state:
    st.session_state.optimization_running = False

# --- SIDEBAR: CONFIGURATION ---
with st.sidebar:
    st.image("https://via.placeholder.com/300x80/1e3c72/ffffff?text=OPTIMA", use_container_width=True)
    
    st.markdown("### 🎯 Configuration")
    
    # EA & Market Settings
    with st.expander("📊 EA & Market Settings", expanded=True):
        # Scan for EAs - check Docker path first, then local
        DATA_DIR = os.environ.get("DATA_DIR", "")
        if DATA_DIR and os.path.exists(f"{DATA_DIR}/ea_sources"):
            mt5_dir = f"{DATA_DIR}/ea_sources"
            compiled_dir = f"{DATA_DIR}/ea_compiled"
        else:
            # Local development path
            base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            mt5_dir = os.path.join(base_dir, "mt5")
            # Also check data/ea_sources for local Docker volume testing
            alt_path = os.path.join(os.path.dirname(__file__), "data", "ea_sources")
            if os.path.exists(alt_path):
                mt5_dir = alt_path
            compiled_dir = mt5_dir  # Same dir for local
        
        
        found_eas = []
        if os.path.exists(mt5_dir):
            for f in os.listdir(mt5_dir):
                if f.endswith(".mq5"): found_eas.append(f)
        
        selected_ea_file = st.selectbox(
            "Select Bot Source (.mq5)", 
            found_eas if found_eas else ["No .mq5 found"],
            help="MT5 can backtest directly from .mq5 source files"
        )
        
        # Use .mq5 file directly (no compilation needed for backtesting)
        if selected_ea_file and found_eas:
            ea_path_ex5 = os.path.join(mt5_dir, selected_ea_file)
        else:
            ea_path_ex5 = ""
        
        # Show selected path
        if ea_path_ex5:
            st.success(f"✅ EA Path: `{ea_path_ex5}`")
        else:
            st.error("❌ No EA file selected")
        
        col1, col2 = st.columns(2)
        with col1:
            symbol = st.selectbox("Symbol", ["XAUUSD", "EURUSD", "GBPUSD", "NZDUSD", "USDJPY"])
        with col2:
            timeframe = st.selectbox("Timeframe", ["PERIOD_M15", "PERIOD_M1", "PERIOD_M5", "PERIOD_M30", "PERIOD_H1", "PERIOD_H4", "PERIOD_D1"])
        
        col3, col4 = st.columns(2)
        with col3:
            date_from = st.date_input("From", pd.to_datetime("2025-01-01"))
        with col4:
            date_to = st.date_input("To", pd.to_datetime("2025-12-31"))
    
    
    # Optimization Settings
    with st.expander("⚙️ Optimization Settings", expanded=True):
        
        goal = st.selectbox(
            "Optimization Goal", 
            ["Max Win Rate", "Multi-Objective (Profit + DD + WinRate)", "Max Profit Factor", "Balanced (Profit/DD)"],
            index=1,
            help="Choose what the AI should prioritize."
        )
        
        n_trials = st.slider("Trials", 10, 1000, 50)
        col1, col2 = st.columns(2)
        with col1:
            deposit = st.number_input("Deposit ($)", 10, 10000000, 10000, 10)
        with col2:
            leverage = st.number_input("Leverage", 1, 1000, 500, 50, help="Account leverage (e.g., 500 = 1:500)")
            
        default_study_name = f"Study_{selected_ea_file.replace('.mq5','')}_{symbol}_{timeframe}_Lev{leverage}"
        study_name = st.text_input("Study Name", default_study_name, help="Unique identifier per configuration")



    st.markdown("---")
    st.markdown("### 📈 Quick Stats")
    try:
        DATA_DIR = os.environ.get("DATA_DIR", ".")
        db_path = os.path.abspath(os.path.join(DATA_DIR, "optimization.db"))
        db_url = f"sqlite:///{db_path}"
        storage = optuna.storages.RDBStorage(url=db_url)
        studies = [s.study_name for s in storage.get_all_studies()]
        st.metric("Total Studies", len(studies))
    except:
        st.metric("Total Studies", "0")

# --- MAIN AREA ---

# Create tabs
tab1, tab2, tab3, tab4, tab5 = st.tabs(["⚙️ Parameter Setup", "🚀 Optimization", "📊 Results", "🔬 Analytics", "🔧 Compile"])

with tab1:
    st.markdown("### Auto-Discovery & Configuration")
    
    col_scan, col_info = st.columns([1, 3])
    with col_scan:
        if st.button("🔍 Scan Bot Parameters", type="primary", use_container_width=True):
            if selected_ea_file and found_eas:
                import mq5_parser
                full_path = os.path.join(mt5_dir, selected_ea_file)
                
                with st.spinner(f"Parsing {selected_ea_file}..."):
                    raw_params = mq5_parser.parse_mq5_inputs(full_path)
                    optimized_config = mq5_parser.generate_optimization_config(raw_params)
                    
                    if optimized_config:
                        st.session_state.params = optimized_config
                        st.success(f"Found {len(optimized_config)} parameters!")
                    else:
                        st.warning("No optimizable parameters found (int/float inputs).")
            else:
                st.error("No valid .mq5 file selected.")

    with col_info:
        st.info("Click **Scan** to automatically extract inputs from the source code and generate intelligent ranges.")

    st.markdown("#### Active Parameters")
    
    col1, col2 = st.columns([3, 1])
    
    with col1:
        # Enhanced parameter editor
        edited_df = st.data_editor(
            st.session_state.params,
            column_config={
                "name": st.column_config.TextColumn("Parameter", disabled=True),
                "group": st.column_config.TextColumn("Group", disabled=True),
                "type": st.column_config.TextColumn("Type", disabled=True, width="small"),
                "min": st.column_config.NumberColumn("Min", required=True),
                "max": st.column_config.NumberColumn("Max", required=True),
                "step": st.column_config.NumberColumn("Step", required=True),
            },
            num_rows="dynamic",
            use_container_width=True,
            hide_index=True
        )
        st.session_state.params = edited_df
    
    with col2:
        st.markdown("#### Actions")
        if st.button("🧹 Clear All"):
            st.session_state.params = []
            st.rerun()
        if st.button("↩️ Undo Changes"):
            st.rerun()

with tab2:
    st.markdown("### Launch Optimization")
    
    # Pre-flight check
    col1, col2, col3 = st.columns(3)
    with col1:
        st.metric("Parameters", len(edited_df), delta=None)
    with col2:
        st.metric("Trials Planned", n_trials)
    with col3:
        days = (date_to - date_from).days
        st.metric("Backtest Period", f"{days} days")
    
    st.markdown("---")
    
    # Start button with validation
    can_start = len(edited_df) > 0 and ea_path_ex5 and study_name
    
    if not can_start:
        st.error("❌ Please configure all required settings before starting optimization")
    
    if st.button("🚀 Start Optimization", disabled=not can_start, type="primary"):
        st.session_state.optimization_running = True
        
        # Convert DataFrame to Config Dict
        param_config = {}
        for entry in edited_df:
            param_config[entry['name']] = {
                'type': entry['type'],
                'min': float(entry['min']),
                'max': float(entry['max']),
                'step': float(entry['step'])
            }
        
        ea_config = {
            'ea_path': ea_path_ex5,
            'symbol': symbol,
            'timeframe': timeframe,
            'date_from': str(date_from).replace("-", "."),
            'date_to': str(date_to).replace("-", "."),
            'deposit': deposit,
            'leverage': leverage,
            'optimization_goal': goal
        }
        
        # Progress tracking UI
        st.markdown("### 🔄 Optimization in Progress")
        progress_bar = st.progress(0)
        status_container = st.container()
        
        col1, col2, col3 = st.columns(3)
        metric_trial = col1.empty()
        metric_status = col2.empty()
        metric_pf = col3.empty()
        
        # Real-time results table
        results_header = st.empty()
        results_table = st.empty()
        
        # Use a dict to track unique trials by trial_number
        if 'trial_results_dict' not in st.session_state:
            st.session_state.trial_results_dict = {}
        
        # Callback for progress updates
        def progress_callback(trial_num, total_trials, status, data):
            progress = min((trial_num + 1) / total_trials, 1.0)
            progress_bar.progress(progress)
            
            # Handle data (dict or float)
            if isinstance(data, dict):
                pf = data.get('profit_factor', 0.0)
                net = data.get('net_profit', 0.0)
                trades = data.get('trades', 0)
                dd = data.get('max_drawdown', 0.0)
                wr = data.get('win_rate', 0.0)
                tf = data.get('timeframe', '')
                lev = data.get('leverage', 0)
                dep = data.get('deposit', 0)
                vol = data.get('volume', '-')
            else:
                pf = float(data) if data else 0.0
                net = 0.0
                trades = 0
                dd = 0.0
                wr = 0.0
                tf = ''
                lev = 0
                dep = 0
                vol = '-'
                
            metric_trial.metric("Current Trial", f"{trial_num + 1}/{total_trials}")
            metric_status.metric("Status", status)
            metric_pf.metric("Last Profit Factor", f"{pf:.2f}")
            
            # Update results table - Only add if trades > 0 (valid run)
            if status == "Completed" and trades > 0:
                trial_id = trial_num + 1
                row = {
                    "Trial": trial_id,
                    "Profit Factor": round(pf, 2),
                    "Net Profit": f"${net:.2f}",
                    "Max DD": f"{dd:.2f}%",
                    "Win Rate": f"{wr:.1f}%",
                    "Trades": trades,
                    "Vol": vol,
                    "TF": tf,
                    "Lev": lev,
                    "Dep": f"${dep}"
                }
                
                # Update or add result
                st.session_state.trial_results_dict[trial_id] = row
                
                # Convert dict back to list for DataFrame
                results_list = list(st.session_state.trial_results_dict.values())
                df_results = pd.DataFrame(results_list)
                
                if not df_results.empty:
                    # Sort dynamically based on goal
                    if "Win Rate" in goal:
                        df_results['WinRateVal'] = df_results['Win Rate'].str.rstrip('%').astype(float)
                        df_results = df_results.sort_values(by="WinRateVal", ascending=False).drop(columns=['WinRateVal']).head(20)
                    else:
                        df_results = df_results.sort_values(by="Profit Factor", ascending=False).head(20)
                    
                    results_header.markdown(f"### 🏆 Top Results (Live) - Sorted by {'Win Rate' if 'Win Rate' in goal else 'Profit Factor'}")
                    results_table.dataframe(df_results, use_container_width=True, hide_index=True)
        
        # Run optimization
        try:
            with st.spinner("🤖 AI is analyzing thousands of parameter combinations..."):
                optimizer_core.run_optimization_task(
                    study_name,
                    n_trials,
                    param_config,
                    ea_config,
                    progress_callback
                )
            
            st.balloons()
            st.success("✅ Optimization Complete! Check the Results tab for detailed analysis.")
            st.session_state.optimization_running = False
            
        except Exception as e:
            st.error(f"❌ Optimization failed: {str(e)}")
            st.session_state.optimization_running = False

with tab3:
    st.markdown("### Results & Analytics")
    
    # Study selector
    try:
        DATA_DIR = os.path.join(os.path.dirname(__file__), "data")
        db_path = os.path.abspath(os.path.join(DATA_DIR, "optimization.db"))
        db_url = f"sqlite:///{db_path}"
        storage = optuna.storages.RDBStorage(url=db_url)
        available_studies = [s.study_name for s in storage.get_all_studies()]
        
        if available_studies:
            # Filter studies
            filter_text = st.text_input("🔍 Filter Studies", placeholder="Type to search (e.g. XAUUSD, H1, Lev500)...")
            filtered_studies = [s for s in available_studies if filter_text.lower() in s.lower()] if filter_text else available_studies
            
            if not filtered_studies:
                st.warning("No studies match your filter.")
                selected_study = None
            else:
                selected_study = st.selectbox(
                    "Select Study to Analyze",
                    filtered_studies,
                    index=0 # Reset index on filter change
                )
        else:
            st.info("📭 No optimization studies found yet. Run an optimization to see results here.")
            selected_study = None
    except:
        st.warning("⚠️ Unable to load studies. Database may not exist yet.")
        selected_study = None
    
    if selected_study:
        try:
            study = optuna.load_study(study_name=selected_study, storage=db_url)
            
            # Key metrics
            st.markdown("#### 🎯 Best Results")
            col1, col2, col3, col4 = st.columns(4)
            
            with col1:
                st.metric("Best Profit Factor", f"{study.best_value:.3f}")
            with col2:
                st.metric("Total Trials", len(study.trials))
            with col3:
                completed = len([t for t in study.trials if t.state == optuna.trial.TrialState.COMPLETE])
                st.metric("Completed", completed)
            with col4:
                st.metric("Best Trial #", study.best_trial.number)
            
            # Best parameters
            st.markdown("#### 🏆 Optimal Parameters")
            params_df = pd.DataFrame([study.best_params]).T
            params_df.columns = ["Value"]
            params_df.index.name = "Parameter"
            st.dataframe(params_df, use_container_width=True)
            
            # Visualizations
            if len(study.trials) > 0:
                st.markdown("---")
                st.markdown("#### 📈 Optimization Analysis")
                
                is_multi_objective = len(study.directions) > 1
                
                tabs_list = ["History", "Parameter Importance", "Parallel Coordinates", "Slice Plot"]
                if is_multi_objective:
                     tabs_list.insert(0, "Pareto Front")
                
                viz_tabs = st.tabs(tabs_list)
                
                current_tab = 0
                if is_multi_objective:
                    with viz_tabs[current_tab]:
                        try:
                            # Detect objectives count
                            n_objs = len(study.directions)
                            if n_objs == 3:
                                targets = ["Profit Factor", "Max Drawdown", "Win Rate"]
                            else:
                                targets = ["Profit Factor", "Max Drawdown"]
                                
                            fig_pareto = optuna.visualization.plot_pareto_front(study, target_names=targets)
                            fig_pareto.update_layout(height=600) # Taller for 3D
                            st.plotly_chart(fig_pareto, use_container_width=True)
                            st.info(f"👆 Optimal trade-offs: {', '.join(targets)}")
                        except Exception as e:
                            st.warning(f"Could not plot Pareto Front: {e}")
                    current_tab += 1

                with viz_tabs[current_tab]:
                    try:
                        # For multi-objective, default to first objective (Profit) if not specified
                        fig1 = optuna.visualization.plot_optimization_history(study, target=lambda t: t.values[0] if is_multi_objective else t.value, target_name="Profit Factor")
                        fig1.update_layout(height=500)
                        st.plotly_chart(fig1, use_container_width=True)
                    except: st.warning("Graph not available")
                
                with viz_tabs[current_tab+1]:
                    try:
                        fig2 = optuna.visualization.plot_param_importances(study, target=lambda t: t.values[0] if is_multi_objective else t.value, target_name="Profit Factor")
                        fig2.update_layout(height=500)
                        st.plotly_chart(fig2, use_container_width=True)
                    except:
                        st.info("Not enough data to calculate parameter importance yet.")
                
                with viz_tabs[current_tab+2]:
                    try:
                        fig3 = optuna.visualization.plot_parallel_coordinate(study, target=lambda t: t.values[0] if is_multi_objective else t.value, target_name="Profit Factor")
                        fig3.update_layout(height=500)
                        st.plotly_chart(fig3, use_container_width=True)
                    except: st.warning("Graph not available")
                
                with viz_tabs[current_tab+3]:
                    try:
                        fig4 = optuna.visualization.plot_slice(study, target=lambda t: t.values[0] if is_multi_objective else t.value, target_name="Profit Factor")
                        fig4.update_layout(height=500)
                        st.plotly_chart(fig4, use_container_width=True)
                    except: st.warning("Graph not available")
                
                # Export options
                st.markdown("---")
                st.markdown("#### 💾 Export Results")
                col1, col2 = st.columns(2)
                
                with col1:
                    # Create trials dataframe
                    trials_data = []
                    for trial in study.trials:
                        trial_dict = {"trial": trial.number, "value": trial.value}
                        trial_dict.update(trial.params)
                        trials_data.append(trial_dict)
                    
                    trials_df = pd.DataFrame(trials_data)
                    csv = trials_df.to_csv(index=False)
                    st.download_button(
                        "📥 Download Trials (CSV)",
                        csv,
                        f"{selected_study}_trials.csv",
                        "text/csv",
                        use_container_width=True
                    )
                
                with col2:
                    import json
                    try:
                        best_params = study.best_params
                    except RuntimeError:
                        # Handle Multi-Objective Study (Pareto Front)
                        # Pick the solution with highest Profit Factor (Objective 0)
                        # Obj 0: Profit (max), Obj 1: DD (min), Obj 2: WinRate (max)
                        best_trials = study.best_trials
                        # Sort by Profit Factor desc
                        best_trial = sorted(best_trials, key=lambda t: t.values[0], reverse=True)[0]
                        best_params = best_trial.params
                        st.info("ℹ️ Multi-Objective (3D): Showing params for Max Profit Factor solution from Pareto Set")
                        
                    best_params_json = json.dumps(best_params, indent=2)
                    st.download_button(
                        "📥 Download Best Params (JSON)",
                        best_params_json,
                        f"{selected_study}_best_params.json",
                        "application/json",
                        use_container_width=True
                    )
        
        except Exception as e:
            st.error(f"❌ Error loading study: {str(e)}")

# --- TAB 4: ADVANCED ANALYTICS ---
with tab4:
    st.markdown("### 🔬 Advanced Analytics")
    st.info("Use SHAP to understand *why* certain parameters perform better.")
    
    # Study selector for SHAP
    try:
        DATA_DIR = os.environ.get("DATA_DIR", ".")
        db_path = os.path.abspath(os.path.join(DATA_DIR, "optimization.db"))
        db_url = f"sqlite:///{db_path}"
        storage = optuna.storages.RDBStorage(url=db_url)
        available_studies_shap = [s.study_name for s in storage.get_all_studies()]
        
        if available_studies_shap:
            selected_study_shap = st.selectbox(
                "Select Study for SHAP Analysis",
                available_studies_shap,
                key="shap_study_selector"
            )
            
            if st.button("🧠 Run SHAP Analysis", type="primary"):
                try:
                    import analytics
                    study_shap = optuna.load_study(study_name=selected_study_shap, storage=db_url)
                    
                    with st.spinner("Training explainability model... (requires 10+ trials)"):
                        shap_values, feature_names, explainer, X = analytics.explain_optuna_params(study_shap)
                    
                    st.success("SHAP analysis complete!")
                    
                    # Feature Importance Table
                    st.markdown("#### 📊 Parameter Importance Ranking")
                    importance_df = analytics.get_feature_importance_df(shap_values, feature_names)
                    st.dataframe(importance_df, use_container_width=True, hide_index=True)
                    
                    # SHAP Summary Plot
                    st.markdown("#### 🎨 SHAP Summary Plot")
                    fig = analytics.get_shap_summary_fig(shap_values, feature_names, X)
                    st.pyplot(fig)
                    
                    st.markdown("""
                    **How to Read This:**
                    - Each dot is one trial
                    - Red = high parameter value, Blue = low value
                    - Position on X-axis shows impact on Profit Factor
                    - Parameters at top are most important
                    """)
                    
                except ValueError as ve:
                    st.warning(f"⚠️ {str(ve)}")
                except Exception as e:
                    st.error(f"❌ SHAP Analysis Error: {str(e)}")
        else:
            st.info("📭 No studies available. Run an optimization first.")
    except:
        st.warning("⚠️ Database not accessible.")

# --- TAB 5: COMPILE ---
with tab5:
    st.markdown("### 🔧 MQL5 Compiler")
    st.info("Compile your .mq5 source files to .ex5 executables directly from the dashboard.")
    
    # Configuration
    MT5_API_URL = os.environ.get("MT5_API_URL", "http://localhost:8080")
    
    # Check MT5 API Status
    col_status, col_refresh = st.columns([3, 1])
    with col_status:
        try:
            import requests
            status_resp = requests.get(f"{MT5_API_URL}/status", timeout=5)
            if status_resp.ok:
                status_data = status_resp.json()
                if status_data.get("metaeditor_installed"):
                    st.success("✅ MT5 Container Connected - MetaEditor Available")
                else:
                    st.warning("⚠️ MT5 Connected but MetaEditor not found. Please install MT5 via VNC (port 5900)")
            else:
                st.error("❌ MT5 API returned error")
        except requests.exceptions.ConnectionError:
            st.error("❌ Cannot connect to MT5 container. Is it running? (`docker-compose up`)")
        except Exception as e:
            st.error(f"❌ API Error: {e}")
    
    with col_refresh:
        if st.button("🔄 Refresh"):
            st.rerun()
    
    st.markdown("---")
    
    # File Lists
    col_sources, col_compiled = st.columns(2)
    
    try:
        files_resp = requests.get(f"{MT5_API_URL}/files", timeout=5)
        files_data = files_resp.json() if files_resp.ok else {"sources": [], "compiled": []}
    except:
        files_data = {"sources": [], "compiled": []}
    
    with col_sources:
        st.markdown("#### 📄 Source Files (.mq5)")
        sources = files_data.get("sources", [])
        
        if sources:
            for mq5_file in sources:
                col_name, col_btn = st.columns([3, 1])
                with col_name:
                    st.text(f"📝 {mq5_file}")
                with col_btn:
                    if st.button("Compile", key=f"compile_{mq5_file}"):
                        with st.spinner(f"Compiling {mq5_file}..."):
                            try:
                                resp = requests.get(f"{MT5_API_URL}/compile", params={"file": mq5_file}, timeout=120)
                                result = resp.json()
                                if result.get("success"):
                                    st.success(f"✅ Compiled: {mq5_file}")
                                else:
                                    st.error(f"❌ Failed: {result.get('output', 'Unknown error')}")
                            except Exception as e:
                                st.error(f"❌ Error: {e}")
        else:
            st.info("No .mq5 files found in `/data/ea_sources/`")
    
    with col_compiled:
        st.markdown("#### ✅ Compiled Files (.ex5)")
        compiled = files_data.get("compiled", [])
        
        if compiled:
            for ex5_file in compiled:
                st.text(f"✓ {ex5_file}")
        else:
            st.info("No compiled files yet")
    
    # Compilation Log
    st.markdown("---")
    st.markdown("#### 📋 Last Compilation Log")
    
    try:
        log_resp = requests.get(f"{MT5_API_URL}/log", timeout=5)
        if log_resp.ok:
            log_data = log_resp.json()
            if log_data.get("file"):
                status_icon = "✅" if log_data.get("success") else "❌"
                st.markdown(f"**{status_icon} {log_data.get('file')}**")
                st.code(log_data.get("output", "No output"), language="text")
            else:
                st.info("No compilation logs yet")
        else:
            st.info("Log not available")
    except:
        st.info("Cannot fetch logs - MT5 container may not be running")

# Footer
st.markdown("---")
st.markdown(
    "<div style='text-align: center; color: #666; padding: 2rem;'>"
    "Optima AI Optimization Platform • Built for Professional Traders"
    "</div>",
    unsafe_allow_html=True
)
