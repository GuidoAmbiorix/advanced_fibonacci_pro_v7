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
        ea_path = st.text_input(
            "EA Path (.ex5)",
            r"C:\Users\gamparo\Desktop\Projects\advanced_fibonacci_pro_v7\mt5\Adaptive_Forex_Majors.ex5",
            help="Full path to your Expert Advisor executable"
        )
        
        col1, col2 = st.columns(2)
        with col1:
            symbol = st.selectbox("Symbol", ["EURUSD", "GBPUSD", "NZDUSD", "USDJPY", "XAUUSD"])
        with col2:
            timeframe = st.selectbox("Timeframe", ["PERIOD_M15", "PERIOD_H1", "PERIOD_H4"])
        
        col3, col4 = st.columns(2)
        with col3:
            date_from = st.date_input(
                "From",
                pd.to_datetime("2024-01-01"),
                max_value=datetime.now()
            )
        with col4:
            date_to = st.date_input(
                "To",
                pd.to_datetime("2024-12-31"),
                max_value=datetime.now()
            )
    
    # Optimization Settings
    with st.expander("⚙️ Optimization Settings", expanded=True):
        study_name = st.text_input(
            "Study Name",
            "Study_EURUSD_v1",
            help="Unique identifier for this optimization run"
        )
        
        n_trials = st.slider(
            "Number of Trials",
            min_value=10,
            max_value=1000,
            value=100,
            step=10,
            help="More trials = better results but longer runtime"
        )
        
        deposit = st.number_input(
            "Initial Deposit ($)",
            min_value=1000,
            max_value=1000000,
            value=10000,
            step=1000
        )
    
    st.markdown("---")
    st.markdown("### 📈 Quick Stats")
    try:
        db_url = "sqlite:///optimization.db"
        storage = optuna.storages.RDBStorage(url=db_url)
        studies = storage.get_all_study_names()
        st.metric("Total Studies", len(studies))
    except:
        st.metric("Total Studies", "0")

# --- MAIN AREA ---

# Create tabs for better organization
tab1, tab2, tab3 = st.tabs(["⚙️ Parameter Setup", "🚀 Optimization", "📊 Results & Analytics"])

with tab1:
    st.markdown("### Define Parameter Search Space")
    st.info("💡 Configure the ranges for each parameter that the AI will explore to find optimal values.")
    
    col1, col2 = st.columns([3, 1])
    
    with col1:
        # Enhanced parameter editor
        edited_df = st.data_editor(
            st.session_state.params,
            column_config={
                "name": st.column_config.TextColumn("Parameter Name", required=True, width="medium"),
                "type": st.column_config.SelectboxColumn("Type", options=["int", "float"], required=True, width="small"),
                "min": st.column_config.NumberColumn("Min Value", required=True, width="small"),
                "max": st.column_config.NumberColumn("Max Value", required=True, width="small"),
                "step": st.column_config.NumberColumn("Step Size", required=True, width="small"),
            },
            num_rows="dynamic",
            use_container_width=True,
            hide_index=True
        )
        
        st.session_state.params = edited_df
    
    with col2:
        st.markdown("#### Quick Actions")
        if st.button("➕ Add Parameter"):
            st.session_state.params.append({
                "name": "NewParam",
                "type": "float",
                "min": 0.0,
                "max": 10.0,
                "step": 0.1
            })
            st.rerun()
        
        if st.button("🔄 Reset to Default"):
            st.session_state.params = [
                {"name": "InpRisk_Reward_Ratio", "type": "float", "min": 2.0, "max": 5.0, "step": 0.5},
                {"name": "InpADX_Threshold", "type": "int", "min": 15, "max": 30, "step": 1},
                {"name": "InpCooldownMinutes", "type": "int", "min": 15, "max": 120, "step": 15}
            ]
            st.rerun()
    
    # Parameter validation
    if len(edited_df) > 0:
        st.success(f"✅ {len(edited_df)} parameters configured and ready for optimization")
    else:
        st.warning("⚠️ Please add at least one parameter to optimize")

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
    can_start = len(edited_df) > 0 and ea_path and study_name
    
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
            'ea_path': ea_path,
            'symbol': symbol,
            'timeframe': timeframe,
            'date_from': str(date_from).replace("-", "."),
            'date_to': str(date_to).replace("-", "."),
            'deposit': deposit
        }
        
        # Progress tracking UI
        st.markdown("### 🔄 Optimization in Progress")
        progress_bar = st.progress(0)
        status_container = st.container()
        
        col1, col2, col3 = st.columns(3)
        metric_trial = col1.empty()
        metric_status = col2.empty()
        metric_pf = col3.empty()
        
        # Callback for progress updates
        def progress_callback(trial_num, total_trials, status, pf):
            progress = min((trial_num + 1) / total_trials, 1.0)
            progress_bar.progress(progress)
            
            metric_trial.metric("Current Trial", f"{trial_num + 1}/{total_trials}")
            metric_status.metric("Status", status)
            metric_pf.metric("Last Profit Factor", f"{pf:.2f}" if pf else "N/A")
        
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
        db_url = "sqlite:///optimization.db"
        storage = optuna.storages.RDBStorage(url=db_url)
        available_studies = storage.get_all_study_names()
        
        if available_studies:
            selected_study = st.selectbox(
                "Select Study to Analyze",
                available_studies,
                index=available_studies.index(study_name) if study_name in available_studies else 0
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
                
                viz_tab1, viz_tab2, viz_tab3, viz_tab4 = st.tabs([
                    "History", "Parameter Importance", "Parallel Coordinates", "Slice Plot"
                ])
                
                with viz_tab1:
                    fig1 = optuna.visualization.plot_optimization_history(study)
                    fig1.update_layout(height=500)
                    st.plotly_chart(fig1, use_container_width=True)
                
                with viz_tab2:
                    try:
                        fig2 = optuna.visualization.plot_param_importances(study)
                        fig2.update_layout(height=500)
                        st.plotly_chart(fig2, use_container_width=True)
                    except:
                        st.info("Not enough data to calculate parameter importance yet.")
                
                with viz_tab3:
                    fig3 = optuna.visualization.plot_parallel_coordinate(study)
                    fig3.update_layout(height=500)
                    st.plotly_chart(fig3, use_container_width=True)
                
                with viz_tab4:
                    fig4 = optuna.visualization.plot_slice(study)
                    fig4.update_layout(height=500)
                    st.plotly_chart(fig4, use_container_width=True)
                
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
                    best_params_json = json.dumps(study.best_params, indent=2)
                    st.download_button(
                        "📥 Download Best Params (JSON)",
                        best_params_json,
                        f"{selected_study}_best_params.json",
                        "application/json",
                        use_container_width=True
                    )
        
        except Exception as e:
            st.error(f"❌ Error loading study: {str(e)}")

# Footer
st.markdown("---")
st.markdown(
    "<div style='text-align: center; color: #666; padding: 2rem;'>"
    "Optima AI Optimization Platform • Built for Professional Traders"
    "</div>",
    unsafe_allow_html=True
)