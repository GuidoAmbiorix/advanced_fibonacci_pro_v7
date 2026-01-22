"""
Governor Components - Streamlit UI components for Portfolio Governor.
Renders symbol scores, correlation heatmaps, group cards, and controls.
"""

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from typing import Dict, List, Optional


def render_symbol_scores_table(scores_df: pd.DataFrame) -> None:
    """
    Render symbol scores table with color coding.
    
    Args:
        scores_df: DataFrame with symbol scores from SymbolScorer
    """
    if scores_df.empty:
        st.info("No symbol scores available")
        return
    
    # Format for display
    display_df = scores_df[[
        'symbol', 'total_score', 'session_score', 'trend_score', 
        'spread_score', 'volatility_score', 'class', 'risk_profile'
    ]].copy()
    
    display_df.columns = [
        'Symbol', 'Total', 'Session', 'Trend', 
        'Spread', 'Volatility', 'Class', 'Risk'
    ]
    
    # Add emoji indicators
    def score_emoji(score):
        if score >= 75:
            return "🟢"
        elif score >= 50:
            return "🟡"
        else:
            return "🔴"
    
    display_df['Status'] = display_df['Total'].apply(score_emoji)
    
    # Reorder columns
    display_df = display_df[['Status', 'Symbol', 'Total', 'Session', 'Trend', 'Spread', 'Volatility', 'Class', 'Risk']]
    
    # Apply styling
    styled = display_df.style.background_gradient(
        subset=['Total'], 
        cmap='RdYlGn',
        vmin=0,
        vmax=100
    ).format({
        'Total': '{:.1f}',
        'Session': '{:.1f}',
        'Trend': '{:.1f}',
        'Spread': '{:.1f}',
        'Volatility': '{:.1f}'
    })
    
    st.dataframe(styled, use_container_width=True, hide_index=True, height=400)


def render_correlation_heatmap(corr_matrix: pd.DataFrame, height: int = 500) -> None:
    """
    Render correlation heatmap using Plotly.
    
    Args:
        corr_matrix: Correlation DataFrame from CorrelationEngine
        height: Chart height in pixels
    """
    if corr_matrix.empty:
        st.info("No correlation data available")
        return
    
    fig = px.imshow(
        corr_matrix,
        labels=dict(x="Symbol", y="Symbol", color="Correlation"),
        x=corr_matrix.columns,
        y=corr_matrix.index,
        color_continuous_scale="RdBu_r",
        zmin=-1,
        zmax=1,
        aspect="auto"
    )
    
    fig.update_layout(
        title="Real-Time Symbol Correlations",
        height=height,
        margin=dict(l=80, r=20, t=50, b=80)
    )
    
    # Add text annotations
    fig.update_traces(
        text=corr_matrix.round(2).values,
        texttemplate="%{text}",
        textfont={"size": 8}
    )
    
    st.plotly_chart(fig, use_container_width=True)


def render_group_cards(
    groups: List[Dict], 
    active_id: int,
    on_select: Optional[callable] = None
) -> int:
    """
    Render group selection cards.
    
    Args:
        groups: List of group dicts from GroupRanker
        active_id: Currently active group index
        on_select: Callback function when group is selected
        
    Returns:
        Selected group ID
    """
    if not groups:
        st.info("No candidate groups available")
        return active_id
    
    selected = active_id
    
    # Create columns for groups
    cols = st.columns(len(groups))
    
    for i, (col, group) in enumerate(zip(cols, groups)):
        with col:
            is_active = i == active_id
            
            # Card styling
            border_color = "#4CAF50" if is_active else "#333"
            bg_color = "rgba(76, 175, 80, 0.1)" if is_active else "rgba(30, 30, 30, 0.5)"
            
            st.markdown(f"""
                <div style="
                    border: 2px solid {border_color};
                    border-radius: 10px;
                    padding: 15px;
                    background: {bg_color};
                    margin-bottom: 10px;
                ">
                    <h4 style="margin: 0; color: {'#4CAF50' if is_active else '#fff'};">
                        {'⭐ ' if is_active else ''}Group {chr(65 + i)}
                    </h4>
                    <p style="margin: 5px 0; font-size: 24px; font-weight: bold;">
                        {group['composite_score']:.1f}
                    </p>
                    <p style="margin: 5px 0; font-size: 12px; color: #888;">
                        Avg Score: {group['avg_symbol_score']:.1f}
                    </p>
                </div>
            """, unsafe_allow_html=True)
            
            # Symbols list
            for symbol in group["symbols"]:
                st.markdown(f"• **{symbol}**")
            
            st.caption(f"Corr: {group['avg_correlation']:.2f} | Risk: {group['risk_balance_score']:.0f}%")
            
            # Select button
            if st.button(
                "✓ Active" if is_active else "Select",
                key=f"select_group_{i}",
                disabled=is_active,
                use_container_width=True
            ):
                selected = i
                if on_select:
                    on_select(i)
    
    return selected


def render_currency_exposure(exposure: Dict[str, float]) -> None:
    """
    Render currency exposure chart.
    
    Args:
        exposure: Dict mapping currency to net exposure value
    """
    if not exposure:
        st.info("No active group selected")
        return
    
    # Prepare data
    currencies = list(exposure.keys())
    values = list(exposure.values())
    colors = ['#4CAF50' if v >= 0 else '#ef5350' for v in values]
    
    fig = go.Figure()
    
    fig.add_trace(go.Bar(
        x=currencies,
        y=values,
        marker_color=colors,
        text=[f"{v:+.1f}" for v in values],
        textposition='outside'
    ))
    
    fig.update_layout(
        title="Currency Exposure (Net)",
        xaxis_title="Currency",
        yaxis_title="Exposure",
        showlegend=False,
        height=300,
        yaxis=dict(zeroline=True, zerolinecolor='white', zerolinewidth=2)
    )
    
    st.plotly_chart(fig, use_container_width=True)


def render_governor_controls(
    mode: str,
    is_locked: bool
) -> Dict:
    """
    Render governor control panel.
    
    Args:
        mode: Current governor mode
        is_locked: Whether group is locked
        
    Returns:
        Dict with control values
    """
    st.markdown("### ⚙️ Governor Controls")
    
    col1, col2, col3 = st.columns(3)
    
    with col1:
        auto_select = st.checkbox(
            "Auto-select best group",
            value=mode == "auto",
            disabled=is_locked
        )
    
    with col2:
        lock_button = st.button(
            "🔓 Unlock" if is_locked else "🔒 Lock for Session",
            disabled=False,
            use_container_width=True
        )
    
    with col3:
        sync_button = st.button(
            "🔄 Sync with MT5",
            use_container_width=True,
            type="primary"
        )
    
    return {
        "auto_select": auto_select,
        "lock_clicked": lock_button,
        "sync_clicked": sync_button
    }


def render_sync_status(sync_result: Dict) -> None:
    """
    Render MT5 sync status.
    
    Args:
        sync_result: Dict from EACommunicator.sync_with_mt5()
    """
    if not sync_result:
        return
    
    if sync_result.get("success"):
        st.success(f"✅ Synced with MT5 at {sync_result.get('timestamp', 'N/A')}")
        
        with st.expander("Sync Details"):
            st.write("**Active Symbols:**", ", ".join(sync_result.get("active_symbols", [])))
            st.write("**File Written:**", "✓" if sync_result.get("file_written") else "✗")
            
            # Global variables status
            vars_status = sync_result.get("global_vars", {})
            if vars_status:
                success_count = sum(1 for v in vars_status.values() if v)
                st.write(f"**Global Variables:** {success_count}/{len(vars_status)} set")
    else:
        st.error("❌ Sync failed")
        if sync_result.get("errors"):
            for error in sync_result["errors"]:
                st.error(error)


def render_active_group_summary(
    symbols: List[str],
    symbol_scores: Dict[str, float],
    group_info: Dict
) -> None:
    """
    Render summary card for active group.
    
    Args:
        symbols: List of active symbols
        symbol_scores: Dict of symbol scores
        group_info: Group details dict
    """
    st.markdown("### 🎯 Active Portfolio")
    
    # Summary metrics
    col1, col2, col3, col4 = st.columns(4)
    
    with col1:
        avg_score = sum(symbol_scores.get(s, 0) for s in symbols) / len(symbols)
        st.metric("Avg Score", f"{avg_score:.1f}")
    
    with col2:
        st.metric("Max Correlation", f"{group_info.get('max_correlation', 0):.2f}")
    
    with col3:
        st.metric("Risk Balance", f"{group_info.get('risk_balance_score', 0):.0f}%")
    
    with col4:
        st.metric("Symbols", len(symbols))
    
    # Symbol chips
    st.markdown("**Active Symbols:**")
    chips_html = " ".join([
        f'<span style="background: #4CAF50; padding: 5px 12px; border-radius: 15px; margin: 2px; display: inline-block;">{s}</span>'
        for s in symbols
    ])
    st.markdown(chips_html, unsafe_allow_html=True)


def render_group_comparison_table(groups: List[Dict]) -> None:
    """
    Render comparison table for all candidate groups.
    
    Args:
        groups: List of group dicts
    """
    if not groups:
        return
    
    # Build comparison data
    rows = []
    for i, g in enumerate(groups):
        rows.append({
            "Group": chr(65 + i),
            "Symbols": ", ".join(g["symbols"]),
            "Score": g["composite_score"],
            "Avg Symbol": g["avg_symbol_score"],
            "Correlation": g["avg_correlation"],
            "Max Corr": g["max_correlation"],
            "Risk Balance": g["risk_balance_score"],
            "Sessions": g["session_coverage_score"]
        })
    
    df = pd.DataFrame(rows)
    
    styled = df.style.background_gradient(
        subset=['Score'],
        cmap='Greens'
    ).format({
        'Score': '{:.1f}',
        'Avg Symbol': '{:.1f}',
        'Correlation': '{:.3f}',
        'Max Corr': '{:.3f}',
        'Risk Balance': '{:.0f}%',
        'Sessions': '{:.0f}%'
    })
    
    st.dataframe(styled, use_container_width=True, hide_index=True)
