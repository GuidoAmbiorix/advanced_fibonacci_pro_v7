"""
Monitor UI Components for EA Status and Governor Metrics.
"""

import streamlit as st
import pandas as pd
from datetime import datetime
from typing import Dict, List


def render_ea_status_grid(ea_statuses: Dict[str, Dict]):
    """
    Render grid showing status of all Symbol Engine EAs.
    
    Args:
        ea_statuses: Dict mapping symbol to status dict from EAStatusChecker
    """
    if not ea_statuses:
        st.info("No EA status data available")
        return
    
    # Convert to DataFrame for display
    rows = []
    for symbol, status in ea_statuses.items():
        # Status indicator
        if status['status'] == 'ACTIVE':
            status_icon = "🟢"
            status_text = "ACTIVE"
        elif status['status'] == 'INACTIVE':
            status_icon = "⚪"
            status_text = "INACTIVE"
        elif status['status'] == 'OFFLINE':
            status_icon = "🔴"
            status_text = "OFFLINE"
        else:
            status_icon = "❓"
            status_text = "UNKNOWN"
        
        # Last update time
        if status['last_update']:
            age = (datetime.now() - status['last_update']).total_seconds()
            if age < 60:
                last_update_str = f"{int(age)}s ago"
            elif age < 3600:
                last_update_str = f"{int(age/60)}m ago"
            else:
                last_update_str = status['last_update'].strftime("%H:%M:%S")
        else:
            last_update_str = "--:--:--"
        
        rows.append({
            'Status': f"{status_icon} {status_text}",
            'Symbol': symbol,
            'Last Update': last_update_str,
            'Magic': status['magic_number'] if status['magic_number'] else '--',
            'Positions': status['position_count'],
            'Governor': f"{status['governor_multiplier']:.1f}",
            'Risk %': f"{status['risk_percent']:.2f}" if status['risk_percent'] > 0 else '--'
        })
    
    df = pd.DataFrame(rows)
    
    # Display with styling
    st.dataframe(
        df,
        use_container_width=True,
        hide_index=True,
        column_config={
            'Status': st.column_config.TextColumn('Status', width='medium'),
            'Symbol': st.column_config.TextColumn('Symbol', width='small'),
            'Last Update': st.column_config.TextColumn('Last Update', width='small'),
            'Magic': st.column_config.NumberColumn('Magic', width='small'),
            'Positions': st.column_config.NumberColumn('Pos', width='small'),
            'Governor': st.column_config.TextColumn('Gov Mult', width='small'),
            'Risk %': st.column_config.TextColumn('Risk %', width='small')
        }
    )


def render_governor_metrics_card(metrics: Dict):
    """
    Render card with Portfolio Governor metrics.
    
    Args:
        metrics: Dict from GovernorMonitor.get_governor_metrics()
    """
    if not metrics or not metrics.get('active'):
        st.warning("📊 Portfolio Governor: OFFLINE")
        st.caption("Governor is not active. Start Portfolio_Governor.mq5 on MT5.")
        return
    
    # Status badge
    status = metrics.get('status', 'UNKNOWN')
    if status == 'ACTIVE':
        st.success(f"📊 Portfolio Governor: {status}", icon="✅")
    elif status == 'PAUSED':
        st.warning(f"📊 Portfolio Governor: {status}", icon="⏸️")
    elif status == 'PAUSED_DD':
        st.error(f"📊 Portfolio Governor: {status} (DD Limit)", icon="🛑")
    else:
        st.info(f"📊 Portfolio Governor: {status}")
    
    st.divider()
    
    # Metrics in columns
    col1, col2, col3, col4 = st.columns(4)
    
    with col1:
        dd = metrics.get('dd', 0.0)
        dd_delta = "normal" if dd < 5.0 else "inverse"
        st.metric(
            "Portfolio DD",
            f"{dd:.2f}%",
            delta=f"Max: 8.0%",
            delta_color=dd_delta
        )
    
    with col2:
        pf = metrics.get('pf', 0.0)
        pf_delta = "normal" if pf >= 1.0 else "inverse"
        st.metric(
            "Rolling PF",
            f"{pf:.2f}",
            delta="30 trades",
            delta_color="off"
        )
    
    with col3:
        exposure = metrics.get('exposure', 0.0)
        exposure_delta = "normal" if exposure < 2.0 else "inverse"
        st.metric(
            "Total Exposure",
            f"{exposure:.2f}%",
            delta=f"Max: 2.0%",
            delta_color=exposure_delta
        )
    
    with col4:
        risk_mult = metrics.get('risk_multiplier', 1.0)
        st.metric(
            "Risk Multiplier",
            f"{risk_mult*100:.0f}%",
            delta="Active" if metrics.get('trading_enabled') else "Paused",
            delta_color="normal" if metrics.get('trading_enabled') else "inverse"
        )
    
    st.divider()
    
    # Additional metrics
    col1, col2, col3 = st.columns(3)
    
    with col1:
        daily_dd = metrics.get('daily_dd', 0.0)
        st.metric("Daily DD", f"{daily_dd:.2f}%")
    
    with col2:
        weekly_dd = metrics.get('weekly_dd', 0.0)
        st.metric("Weekly DD", f"{weekly_dd:.2f}%")
    
    with col3:
        peak_equity = metrics.get('peak_equity', 0.0)
        if peak_equity > 0:
            st.metric("Peak Equity", f"${peak_equity:,.2f}")
        else:
            st.metric("Peak Equity", "N/A")
    
    # Last update info
    last_update = metrics.get('last_update')
    if last_update:
        age = (datetime.now() - last_update).total_seconds()
        st.caption(f"Last update: {last_update.strftime('%H:%M:%S')} ({int(age)}s ago)")
    else:
        st.caption("Last update: Unknown")


def render_group_risk_bars(group_risks: Dict[str, float], max_risk: float = 1.0):
    """
    Render progress bars for correlation group risks.
    
    Args:
        group_risks: Dict mapping group name to risk %
        max_risk: Maximum risk per group (default 1.0%)
    """
    st.markdown("### 💱 Correlation Group Risks")
    
    if not group_risks:
        st.info("No group risk data available")
        return
    
    for group_name, risk_pct in group_risks.items():
        # Skip if no risk
        if risk_pct == 0.0:
            continue
        
        # Calculate percentage of max
        pct_of_max = (risk_pct / max_risk) * 100 if max_risk > 0 else 0
        
        # Color based on utilization
        if pct_of_max >= 90:
            color = "🔴"
        elif pct_of_max >= 70:
            color = "🟡"
        else:
            color = "🟢"
        
        # Create columns for label and bar
        col1, col2 = st.columns([1, 3])
        
        with col1:
            st.markdown(f"**{color} {group_name}**")
        
        with col2:
            st.progress(
                min(pct_of_max / 100, 1.0),
                text=f"{risk_pct:.2f}% / {max_risk:.2f}% ({pct_of_max:.0f}%)"
            )


def render_ea_summary_stats(summary: Dict):
    """
    Render summary statistics for EA monitoring.
    
    Args:
        summary: Dict from EAStatusChecker.get_summary_stats()
    """
    col1, col2, col3, col4 = st.columns(4)
    
    with col1:
        st.metric("Total Symbols", summary.get('total_symbols', 0))
    
    with col2:
        active = summary.get('active_count', 0)
        st.metric("Active EAs", active, delta="🟢")
    
    with col3:
        inactive = summary.get('inactive_count', 0)
        delta_color = "normal" if inactive == 0 else "inverse"
        st.metric("Inactive EAs", inactive, delta="⚪", delta_color=delta_color)
    
    with col4:
        positions = summary.get('total_positions', 0)
        st.metric("Total Positions", positions)
    
    # Last check time
    last_check = summary.get('last_check')
    if last_check:
        age = (datetime.now() - last_check).total_seconds()
        st.caption(f"Last check: {last_check.strftime('%H:%M:%S')} ({int(age)}s ago)")


def render_active_symbol_chips(active_symbols: List[str]):
    """
    Render chips/badges for active symbols.
    
    Args:
        active_symbols: List of active symbol names
    """
    if not active_symbols:
        st.info("No active symbols")
        return
    
    st.markdown("**Active Symbols:**")
    
    # Create HTML for chips
    chips_html = '<div style="display: flex; flex-wrap: wrap; gap: 8px;">'
    
    for symbol in sorted(active_symbols):
        chips_html += f'''
        <div style="
            background-color: #4CAF50;
            color: white;
            padding: 6px 12px;
            border-radius: 16px;
            font-size: 14px;
            font-weight: 500;
        ">
            🟢 {symbol}
        </div>
        '''
    
    chips_html += '</div>'
    
    st.markdown(chips_html, unsafe_allow_html=True)


def render_inactive_symbol_chips(inactive_symbols: List[str]):
    """
    Render chips/badges for inactive symbols.
    
    Args:
        inactive_symbols: List of inactive symbol names
    """
    if not inactive_symbols:
        return
    
    st.markdown("**Inactive Symbols:**")
    
    # Create HTML for chips
    chips_html = '<div style="display: flex; flex-wrap: wrap; gap: 8px;">'
    
    for symbol in sorted(inactive_symbols):
        chips_html += f'''
        <div style="
            background-color: #757575;
            color: white;
            padding: 6px 12px;
            border-radius: 16px;
            font-size: 14px;
            font-weight: 500;
        ">
            ⚪ {symbol}
        </div>
        '''
    
    chips_html += '</div>'
    
    st.markdown(chips_html, unsafe_allow_html=True)
