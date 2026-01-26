"""
Alert and Notification UI Components.
"""

import streamlit as st
from typing import List, Dict
from datetime import datetime


def render_alert_panel(alerts: List[Dict], max_display: int = 10):
    """
    Render alert notification panel.
    
    Args:
        alerts: List of alert dicts from AlertManager
        max_display: Maximum alerts to display
    """
    if not alerts:
        st.info("🔕 No recent alerts")
        return
    
    st.markdown(f"### 🔔 Alerts & Notifications ({len(alerts)} recent)")
    
    # Display most recent first
    for alert in reversed(alerts[-max_display:]):
        icon = alert['icon']
        timestamp = alert['timestamp'].strftime('%H:%M:%S')
        title = alert['title']
        message = alert['message']
        severity = alert['severity']
        
        # Create alert box with appropriate styling
        if severity == 'CRITICAL':
            st.error(f"{icon} **{timestamp}** - {title}\\n\\n{message}")
        elif severity == 'WARNING':
            st.warning(f"{icon} **{timestamp}** - {title}\\n\\n{message}")
        else:
            st.success(f"{icon} **{timestamp}** - {title}\\n\\n{message}")
    
    # Clear button
    if st.button("🗑️ Clear All Alerts", key="clear_alerts"):
        return True  # Signal to clear
    
    return False


def render_health_dashboard(health_results: Dict):
    """
    Render system health dashboard.
    
    Args:
        health_results: Results from HealthChecker.run_full_diagnostic()
    """
    overall = health_results.get('overall', 'UNKNOWN')
    
    # Overall status badge
    if overall == 'HEALTHY':
        st.success("🏥 System Health: HEALTHY", icon="✅")
    elif overall == 'WARNING':
        st.warning("🏥 System Health: WARNING", icon="⚠️")
    else:
        st.error("🏥 System Health: CRITICAL", icon="🔴")
    
    st.divider()
    
    # Component status table
    st.markdown("### Component Status")
    
    components = {
        'MT5 Connection': health_results.get('mt5_connection', {}),
        'Portfolio Governor': health_results.get('governor_heartbeat', {}),
        'Database': health_results.get('database', {}),
        'Disk Space': health_results.get('disk_space', {}),
        'Error Logs': health_results.get('logs', {})
    }
    
    for comp_name, comp_data in components.items():
        if not comp_data:
            continue
        
        status = comp_data.get('status', 'UNKNOWN')
        message = comp_data.get('message', 'N/A')
        details = comp_data.get('details', '')
        
        # Status indicator
        if status == 'OK':
            indicator = "🟢"
        elif status == 'WARNING' or status == 'INFO':
            indicator = "🟡"
        else:
            indicator = "🔴"
        
        # Display
        col1, col2, col3 = st.columns([2, 2, 3])
        with col1:
            st.markdown(f"**{indicator} {comp_name}**")
        with col2:
            st.markdown(f"`{status}`")
        with col3:
            st.markdown(f"{message} - _{details}_")
    
    # Timestamp
    timestamp = health_results.get('timestamp')
    if timestamp:
        st.caption(f"Last check: {timestamp.strftime('%H:%M:%S')}")


def render_gv_inspector(filter_prefix: str = ""):
    """
    Render GlobalVariables inspector.
    
    Args:
        filter_prefix: Filter variables by prefix (e.g., "PG_")
    """
    import MetaTrader5 as mt5
    
    try:
        # Get all global variables
        gv_tuple = mt5.global_variables_get()
        
        if not gv_tuple:
            st.info("No GlobalVariables found")
            return
        
        # Filter if needed
        gv_list = []
        for var_name, var_value in gv_tuple:
            if not filter_prefix or var_name.startswith(filter_prefix):
                gv_list.append({'Variable': var_name, 'Value': f"{var_value:.4f}"})
        
        if not gv_list:
            st.info(f"No variables matching filter '{filter_prefix}'")
            return
        
        st.markdown(f"### 📊 GlobalVariables ({len(gv_list)} found)")
        
        # Display as dataframe
        import pandas as pd
        df = pd.DataFrame(gv_list)
        
        st.dataframe(
            df,
            use_container_width=True,
            hide_index=True,
            height=400
        )
        
    except Exception as e:
        st.error(f"Error reading GlobalVariables: {e}")


def render_quick_actions_sidebar():
    """
    Render quick actions in sidebar.
    
    Returns:
        Dict with action results
    """
    import MetaTrader5 as mt5
    
    st.sidebar.markdown("---")
    st.sidebar.header("⚡ Quick Actions")
    
    actions = {
        'emergency_stop': False,
        'pause_trading': False,
        'resume_trading': False,
        'force_sync': False
    }
    
    # Emergency Stop
    if st.sidebar.button("🔴 EMERGENCY STOP ALL", key="emergency_stop", type="primary"):
        with st.sidebar:
            confirm = st.warning("⚠️ This will stop ALL trading immediately!")
            if st.button("Yes, STOP ALL", key="confirm_emergency"):
                # Set TradingEnabled to 0
                mt5.global_variable_set("PG_TradingEnabled", 0.0)
                
                # Set all GovernorMultipliers to 0
                gv_tuple = mt5.global_variables_get()
                if gv_tuple:
                    for var_name, _ in gv_tuple:
                        if var_name.startswith("GovernorMultiplier_"):
                            mt5.global_variable_set(var_name, 0.0)
                
                st.sidebar.success("✅ All trading stopped!")
                actions['emergency_stop'] = True
    
    # Pause Trading
    if st.sidebar.button("🟡 Pause Trading", key="pause_trading"):
        mt5.global_variable_set("PG_TradingEnabled", 0.0)
        st.sidebar.success("✅ Trading paused!")
        actions['pause_trading'] = True
    
    # Resume Trading
    if st.sidebar.button("🟢 Resume Trading", key="resume_trading"):
        mt5.global_variable_set("PG_TradingEnabled", 1.0)
        st.sidebar.success("✅ Trading resumed!")
        actions['resume_trading'] = True
    
    # Force Sync
    if st.sidebar.button("🔄 Force Sync to MT5", key="force_sync"):
        st.sidebar.info("Sync functionality requires Portfolio Governor integration")
        actions['force_sync'] = True
    
    return actions
