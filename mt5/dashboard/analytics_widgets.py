"""
Analytics Widgets for Dashboard
================================
Streamlit components for displaying analytics from new tables.

Usage in app.py:
    from analytics_widgets import show_equity_curve, show_active_alerts, etc.
"""

import streamlit as st
import pandas as pd
import plotly.graph_objects as go
import plotly.express as px
from datetime import datetime, timedelta


def show_equity_curve(db_manager, days: int = 90):
    """Display equity curve from DailyPerformance table"""
    try:
        conn = db_manager.get_connection()
        if not conn:
            st.warning("Database not available")
            return

        cutoff_date = (datetime.now() - timedelta(days=days)).strftime('%Y-%m-%d')

        df = pd.read_sql("""
            SELECT date, cumulative_pnl, daily_pnl, sharpe_ratio
            FROM DailyPerformance
            WHERE date >= ?
            ORDER BY date
        """, conn, params=(cutoff_date,))

        conn.close()

        if df.empty:
            st.info(f"📊 No equity curve data available yet. Run: `python run_analytics.py backfill --days {days}`")
            return

        # Create plotly chart
        fig = go.Figure()

        # Equity curve
        fig.add_trace(go.Scatter(
            x=df['date'],
            y=df['cumulative_pnl'],
            mode='lines+markers',
            name='Cumulative P&L',
            line=dict(color='#00ff88', width=2),
            fill='tozeroy',
            fillcolor='rgba(0, 255, 136, 0.1)'
        ))

        fig.update_layout(
            title=f'Equity Curve (Last {days} Days)',
            xaxis_title='Date',
            yaxis_title='Cumulative P&L ($)',
            template='plotly_dark',
            height=400,
            hovermode='x unified'
        )

        st.plotly_chart(fig, use_container_width=True)

        # Stats below chart
        col1, col2, col3, col4 = st.columns(4)

        current_pnl = df['cumulative_pnl'].iloc[-1] if not df.empty else 0
        peak_pnl = df['cumulative_pnl'].max()
        drawdown = current_pnl - peak_pnl
        avg_sharpe = df['sharpe_ratio'].mean()

        col1.metric("Current P&L", f"${current_pnl:.2f}")
        col2.metric("Peak P&L", f"${peak_pnl:.2f}")
        col3.metric("Drawdown", f"${drawdown:.2f}", delta_color="inverse")
        col4.metric("Avg Sharpe", f"{avg_sharpe:.2f}" if pd.notna(avg_sharpe) else "N/A")

    except Exception as e:
        st.error(f"Error loading equity curve: {e}")


def show_active_alerts(db_manager):
    """Display active performance alerts"""
    try:
        conn = db_manager.get_connection()
        if not conn:
            return

        df = pd.read_sql("""
            SELECT
                severity,
                title,
                message,
                symbol,
                suggested_action,
                datetime(timestamp, 'unixepoch') as time
            FROM PerformanceAlerts
            WHERE acknowledged = 0 AND resolved = 0
            ORDER BY
                CASE severity
                    WHEN 'CRITICAL' THEN 1
                    WHEN 'WARNING' THEN 2
                    WHEN 'INFO' THEN 3
                END,
                timestamp DESC
            LIMIT 10
        """, conn)

        conn.close()

        if df.empty:
            st.success("✅ No active alerts - system running smoothly")
            return

        st.markdown(f"### 🔔 Active Alerts ({len(df)})")

        for _, alert in df.iterrows():
            severity_icon = {
                'CRITICAL': '🔴',
                'WARNING': '🟡',
                'INFO': '🔵'
            }.get(alert['severity'], '⚪')

            severity_color = {
                'CRITICAL': 'error',
                'WARNING': 'warning',
                'INFO': 'info'
            }.get(alert['severity'], 'info')

            with st.expander(f"{severity_icon} {alert['title']}", expanded=(alert['severity'] == 'CRITICAL')):
                st.markdown(f"**{alert['message']}**")

                if pd.notna(alert['symbol']):
                    st.caption(f"Symbol: {alert['symbol']}")

                if pd.notna(alert['suggested_action']):
                    st.info(f"💡 Suggested Action: {alert['suggested_action']}")

                st.caption(f"⏰ {alert['time']}")

    except Exception as e:
        st.error(f"Error loading alerts: {e}")


def show_symbol_performance_matrix(db_manager, days: int = 30):
    """Display symbol comparison matrix"""
    try:
        conn = db_manager.get_connection()
        if not conn:
            return

        cutoff_date = (datetime.now() - timedelta(days=days)).strftime('%Y-%m-%d')

        df = pd.read_sql("""
            SELECT
                symbol,
                SUM(total_trades) as trades,
                AVG(win_rate) as win_rate,
                SUM(total_pnl) as total_pnl,
                AVG(sharpe_ratio) as sharpe_ratio,
                AVG(avg_confluence_score) as avg_confluence
            FROM SymbolPerformance
            WHERE date >= ?
            GROUP BY symbol
            ORDER BY total_pnl DESC
        """, conn, params=(cutoff_date,))

        conn.close()

        if df.empty:
            st.info("📊 No symbol performance data yet")
            return

        # Format for display
        df_display = df.copy()
        df_display['win_rate'] = df_display['win_rate'].apply(lambda x: f"{x:.1f}%")
        df_display['total_pnl'] = df_display['total_pnl'].apply(lambda x: f"${x:.2f}")
        df_display['sharpe_ratio'] = df_display['sharpe_ratio'].apply(lambda x: f"{x:.2f}" if pd.notna(x) else "N/A")
        df_display['avg_confluence'] = df_display['avg_confluence'].apply(lambda x: f"{x:.1f}" if pd.notna(x) else "N/A")

        # Add status column
        df['status'] = df['sharpe_ratio'].apply(lambda x:
            "✅ Excellent" if pd.notna(x) and x > 1.0 else
            "✅ Good" if pd.notna(x) and x > 0.6 else
            "⚠️ Weak" if pd.notna(x) and x > 0.3 else
            "🔴 Poor"
        )

        df_display['status'] = df['status']

        st.dataframe(df_display, use_container_width=True, height=400)

        # Summary
        st.markdown("---")
        col1, col2, col3 = st.columns(3)

        good_symbols = (df['sharpe_ratio'] > 0.6).sum() if 'sharpe_ratio' in df.columns else 0
        weak_symbols = ((df['sharpe_ratio'] > 0.3) & (df['sharpe_ratio'] <= 0.6)).sum() if 'sharpe_ratio' in df.columns else 0
        poor_symbols = (df['sharpe_ratio'] <= 0.3).sum() if 'sharpe_ratio' in df.columns else 0

        col1.metric("Good Performers", good_symbols, "Sharpe > 0.6")
        col2.metric("Weak Performers", weak_symbols, "Sharpe 0.3-0.6")
        col3.metric("Poor Performers", poor_symbols, "Sharpe < 0.3")

    except Exception as e:
        st.error(f"Error loading symbol performance: {e}")


def show_regime_heatmap(db_manager, days: int = 30):
    """Display regime performance heatmap"""
    try:
        conn = db_manager.get_connection()
        if not conn:
            return

        cutoff_date = (datetime.now() - timedelta(days=days)).strftime('%Y-%m-%d')

        df = pd.read_sql("""
            SELECT
                symbol,
                regime,
                AVG(win_rate) as win_rate,
                AVG(profit_factor) as profit_factor
            FROM RegimePerformance
            WHERE period >= ?
            GROUP BY symbol, regime
        """, conn, params=(cutoff_date,))

        conn.close()

        if df.empty:
            st.info("📊 No regime performance data yet")
            return

        # Pivot for heatmap
        df_pivot = df.pivot(index='symbol', columns='regime', values='win_rate')

        # Create heatmap
        fig = go.Figure(data=go.Heatmap(
            z=df_pivot.values,
            x=df_pivot.columns,
            y=df_pivot.index,
            colorscale='RdYlGn',
            text=df_pivot.values,
            texttemplate='%{text:.1f}%',
            textfont={"size": 10},
            colorbar=dict(title="Win Rate %")
        ))

        fig.update_layout(
            title='Win Rate by Symbol & Regime',
            xaxis_title='Market Regime',
            yaxis_title='Symbol',
            height=400,
            template='plotly_dark'
        )

        st.plotly_chart(fig, use_container_width=True)

    except Exception as e:
        st.error(f"Error loading regime heatmap: {e}")


def show_optimization_priorities(db_manager):
    """Display optimization priority list"""
    try:
        conn = db_manager.get_connection()
        if not conn:
            return

        df = pd.read_sql("""
            SELECT
                symbol,
                priority_score,
                current_sharpe,
                degradation_pct,
                degradation_reason,
                CASE
                    WHEN needs_reoptimization = 1 THEN '🔴 URGENT'
                    ELSE '🟢 OK'
                END as status
            FROM OptimizationSchedule
            ORDER BY priority_score DESC
            LIMIT 10
        """, conn)

        conn.close()

        if df.empty:
            st.info("📊 No optimization schedule data. Run: `python run_analytics.py alerts`")
            return

        st.markdown("### 🎯 Optimization Priority List")

        # Format
        df_display = df.copy()
        df_display['priority_score'] = df_display['priority_score'].apply(lambda x: f"{x:.3f}" if pd.notna(x) else "N/A")
        df_display['current_sharpe'] = df_display['current_sharpe'].apply(lambda x: f"{x:.2f}" if pd.notna(x) else "N/A")
        df_display['degradation_pct'] = df_display['degradation_pct'].apply(lambda x: f"{x:.1f}%" if pd.notna(x) else "N/A")

        st.dataframe(df_display, use_container_width=True)

        # Show urgent symbols
        urgent = df[df['status'] == '🔴 URGENT']
        if not urgent.empty:
            st.error(f"⚠️ {len(urgent)} symbols need urgent re-optimization!")
            for _, row in urgent.iterrows():
                st.markdown(f"- **{row['symbol']}**: {row['degradation_reason']}")

    except Exception as e:
        st.error(f"Error loading optimization priorities: {e}")


def show_correlation_warnings(db_manager):
    """Display correlation warnings"""
    try:
        conn = db_manager.get_connection()
        if not conn:
            return

        df = pd.read_sql("""
            SELECT
                symbol_a,
                symbol_b,
                correlation
            FROM CorrelationMatrix
            WHERE timestamp = (SELECT MAX(timestamp) FROM CorrelationMatrix)
            AND ABS(correlation) > 0.75
            ORDER BY ABS(correlation) DESC
        """, conn)

        conn.close()

        if df.empty:
            st.success("✅ No high correlations detected (all < 0.75)")
            return

        st.warning(f"⚠️ {len(df)} symbol pairs have high correlation (> 0.75)")

        for _, row in df.iterrows():
            st.markdown(f"- **{row['symbol_a']} ↔ {row['symbol_b']}**: {row['correlation']:.2f}")

        st.info("💡 High correlation reduces diversification. Consider optimizing symbol selection.")

    except Exception as e:
        st.error(f"Error loading correlations: {e}")


def show_drawdown_history(db_manager):
    """Display drawdown history chart"""
    try:
        conn = db_manager.get_connection()
        if not conn:
            return

        df = pd.read_sql("""
            SELECT
                datetime(start_time, 'unixepoch') as start_date,
                datetime(end_time, 'unixepoch') as end_date,
                drawdown_pct,
                duration_days,
                status
            FROM DrawdownHistory
            ORDER BY start_time
        """, conn)

        conn.close()

        if df.empty:
            st.info("📊 No drawdown history available yet")
            return

        # Create chart
        fig = go.Figure()

        recovered = df[df['status'] == 'recovered']
        ongoing = df[df['status'] == 'ongoing']

        if not recovered.empty:
            fig.add_trace(go.Bar(
                x=recovered['start_date'],
                y=recovered['drawdown_pct'],
                name='Recovered Drawdowns',
                marker_color='orange',
                text=recovered['duration_days'].apply(lambda x: f"{x:.0f}d" if pd.notna(x) else ""),
                textposition='auto'
            ))

        if not ongoing.empty:
            fig.add_trace(go.Bar(
                x=ongoing['start_date'],
                y=ongoing['drawdown_pct'],
                name='Ongoing Drawdown',
                marker_color='red',
                text=['ONGOING'] * len(ongoing),
                textposition='auto'
            ))

        fig.update_layout(
            title='Drawdown History',
            xaxis_title='Date',
            yaxis_title='Drawdown %',
            template='plotly_dark',
            height=300,
            showlegend=True
        )

        st.plotly_chart(fig, use_container_width=True)

        # Stats
        if not df.empty:
            avg_dd = df['drawdown_pct'].mean()
            max_dd = df['drawdown_pct'].max()
            avg_recovery = df[df['status'] == 'recovered']['duration_days'].mean()

            col1, col2, col3 = st.columns(3)
            col1.metric("Avg Drawdown", f"{avg_dd:.1f}%")
            col2.metric("Max Drawdown", f"{max_dd:.1f}%")
            col3.metric("Avg Recovery", f"{avg_recovery:.0f} days" if pd.notna(avg_recovery) else "N/A")

    except Exception as e:
        st.error(f"Error loading drawdown history: {e}")
