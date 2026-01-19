"""
Bias Detection System

Detects common backtesting biases that can lead to overfitting.
Based on concepts from "Quantitative Trading" by Dr. Ernest P. Chan.

Bias Types:
1. Look-Ahead Bias: Using future information in past decisions
2. Survivorship Bias: Only testing on assets that still exist
3. Data Snooping Bias: Over-optimization on historical data
"""

import numpy as np
import pandas as pd
from typing import List, Dict, Optional, Callable
from dataclasses import dataclass, field
from datetime import datetime
from loguru import logger


@dataclass
class BiasCheckResult:
    """Result of a single bias check"""
    bias_type: str
    status: str          # PASS, WARN, FAIL
    severity: float      # 0-100
    message: str
    details: Dict = field(default_factory=dict)


@dataclass
class BiasReport:
    """Complete bias analysis report"""
    overall_status: str     # PASS, WARN, FAIL
    overall_score: float    # 0-100 (higher = less bias)
    checks: List[BiasCheckResult]
    recommendation: str
    timestamp: datetime = field(default_factory=datetime.utcnow)


class BiasDetector:
    """
    Detect common backtesting biases.
    
    Helps identify curve-fitting and overfitting issues.
    """
    
    @staticmethod
    def run_all_checks(
        trades: List[Dict],
        price_data: Optional[pd.DataFrame] = None,
        strategy_params: Optional[Dict] = None
    ) -> BiasReport:
        """
        Run all bias detection checks.
        
        Args:
            trades: List of backtest trades
            price_data: OHLCV data used in backtest
            strategy_params: Strategy parameters used
            
        Returns:
            BiasReport with all check results
        """
        checks = []
        
        # Check 1: Look-ahead bias detection
        look_ahead_check = BiasDetector.check_look_ahead_bias(trades, price_data)
        checks.append(look_ahead_check)
        
        # Check 2: Data snooping bias
        snooping_check = BiasDetector.check_data_snooping(trades, strategy_params)
        checks.append(snooping_check)
        
        # Check 3: Perfect trade detection (suspiciously good trades)
        perfect_trade_check = BiasDetector.check_perfect_trades(trades)
        checks.append(perfect_trade_check)
        
        # Check 4: Time distribution bias
        time_check = BiasDetector.check_time_distribution(trades)
        checks.append(time_check)
        
        # Check 5: Parameter sensitivity
        if strategy_params:
            param_check = BiasDetector.check_parameter_sensitivity(strategy_params)
            checks.append(param_check)
        
        # Calculate overall score
        severities = [c.severity for c in checks]
        overall_score = 100 - np.mean(severities) if severities else 100
        
        # Determine overall status
        fail_count = sum(1 for c in checks if c.status == 'FAIL')
        warn_count = sum(1 for c in checks if c.status == 'WARN')
        
        if fail_count > 0:
            overall_status = 'FAIL'
        elif warn_count > 1:
            overall_status = 'WARN'
        else:
            overall_status = 'PASS'
        
        # Generate recommendation
        if overall_status == 'PASS':
            recommendation = "No significant biases detected. Strategy appears sound."
        elif overall_status == 'WARN':
            issues = [c.bias_type for c in checks if c.status == 'WARN']
            recommendation = f"Minor issues detected: {', '.join(issues)}. Review before trading."
        else:
            issues = [c.bias_type for c in checks if c.status == 'FAIL']
            recommendation = f"Critical issues: {', '.join(issues)}. Do not trade until resolved."
        
        return BiasReport(
            overall_status=overall_status,
            overall_score=round(overall_score, 2),
            checks=checks,
            recommendation=recommendation
        )
    
    @staticmethod
    def check_look_ahead_bias(
        trades: List[Dict],
        price_data: Optional[pd.DataFrame] = None
    ) -> BiasCheckResult:
        """
        Check for look-ahead bias.
        
        Look-ahead bias occurs when future information is used in past decisions.
        
        Detection methods:
        1. Check if entry times are before price data availability
        2. Check if high/low prices are used at open (impossible in real trading)
        3. Check for impossible execution prices
        """
        issues = []
        severity = 0
        
        if not trades:
            return BiasCheckResult(
                bias_type="Look-Ahead Bias",
                status="PASS",
                severity=0,
                message="No trades to analyze",
                details={}
            )
        
        # Check 1: Suspiciously good fill prices
        for trade in trades:
            entry_price = trade.get('entry_price', 0)
            exit_price = trade.get('exit_price', 0)
            trade_type = trade.get('type', 'BUY')
            pnl = trade.get('pnl', 0)
            
            # Check if trade captured the full high-low range (impossible)
            if 'high' in trade and 'low' in trade:
                high = trade.get('high', entry_price)
                low = trade.get('low', entry_price)
                
                if trade_type == 'BUY' and entry_price == low and exit_price == high:
                    issues.append("Perfect buy at low, sell at high detected")
                    severity += 30
                elif trade_type == 'SELL' and entry_price == high and exit_price == low:
                    issues.append("Perfect sell at high, buy at low detected")
                    severity += 30
        
        # Check 2: Win rate too good to be true
        win_rate = len([t for t in trades if t.get('pnl', 0) > 0]) / len(trades) * 100
        if win_rate > 85:
            issues.append(f"Suspiciously high win rate ({win_rate:.1f}%)")
            severity += 25
        
        # Check 3: All entries at optimal prices
        if price_data is not None:
            # Additional checks with price data
            pass
        
        # Determine status
        if severity >= 50:
            status = 'FAIL'
            message = f"High look-ahead bias risk: {'; '.join(issues)}"
        elif severity >= 20:
            status = 'WARN'
            message = f"Possible look-ahead bias: {'; '.join(issues)}"
        else:
            status = 'PASS'
            message = "No significant look-ahead bias detected"
        
        return BiasCheckResult(
            bias_type="Look-Ahead Bias",
            status=status,
            severity=min(100, severity),
            message=message,
            details={'issues': issues, 'win_rate': round(win_rate, 2)}
        )
    
    @staticmethod
    def check_data_snooping(
        trades: List[Dict],
        strategy_params: Optional[Dict] = None
    ) -> BiasCheckResult:
        """
        Check for data snooping bias.
        
        Data snooping occurs when strategies are over-optimized on historical data.
        """
        severity = 0
        issues = []
        
        # Factor 1: Number of parameters
        num_params = len(strategy_params) if strategy_params else 5
        if num_params > 10:
            severity += 30
            issues.append(f"Too many parameters ({num_params})")
        elif num_params > 7:
            severity += 15
            issues.append(f"Moderate parameters ({num_params})")
        
        # Factor 2: Parameter precision (very precise values suggest over-optimization)
        if strategy_params:
            for key, value in strategy_params.items():
                if isinstance(value, float):
                    # Check for suspiciously precise values
                    decimal_places = len(str(value).split('.')[-1]) if '.' in str(value) else 0
                    if decimal_places > 3:
                        severity += 10
                        issues.append(f"Over-precise parameter: {key}={value}")
        
        # Factor 3: Number of trades relative to parameters
        trades_per_param = len(trades) / num_params if num_params > 0 else len(trades)
        if trades_per_param < 10:
            severity += 25
            issues.append(f"Low trades per parameter ratio ({trades_per_param:.1f})")
        
        # Determine status
        if severity >= 50:
            status = 'FAIL'
            message = "High data snooping risk detected"
        elif severity >= 20:
            status = 'WARN'
            message = "Moderate data snooping risk"
        else:
            status = 'PASS'
            message = "Low data snooping risk"
        
        return BiasCheckResult(
            bias_type="Data Snooping",
            status=status,
            severity=min(100, severity),
            message=message,
            details={
                'num_parameters': num_params,
                'trades_per_param': round(trades_per_param, 2),
                'issues': issues
            }
        )
    
    @staticmethod
    def check_perfect_trades(trades: List[Dict]) -> BiasCheckResult:
        """
        Check for suspiciously perfect trades.
        
        Perfect timing, no slippage, always hitting TP exactly suggests issues.
        """
        if not trades:
            return BiasCheckResult(
                bias_type="Perfect Trades",
                status="PASS",
                severity=0,
                message="No trades to analyze",
                details={}
            )
        
        severity = 0
        issues = []
        
        # Check 1: All trades profitable
        pnls = [t.get('pnl', 0) for t in trades]
        all_profitable = all(p >= 0 for p in pnls)
        if all_profitable:
            severity += 40
            issues.append("All trades are profitable (highly suspicious)")
        
        # Check 2: No drawdown
        cumulative = np.cumsum(pnls)
        running_max = np.maximum.accumulate(cumulative)
        drawdowns = running_max - cumulative
        max_dd = np.max(drawdowns)
        
        if max_dd == 0 and len(trades) > 10:
            severity += 30
            issues.append("Zero drawdown (impossible in real trading)")
        
        # Check 3: All exits at take profit
        tp_exits = sum(1 for t in trades if t.get('exit_reason', '') in ['TP', 'TAKE_PROFIT', 'TP1', 'TP2', 'TP3'])
        tp_rate = tp_exits / len(trades) * 100
        
        if tp_rate > 80:
            severity += 20
            issues.append(f"Unrealistic TP hit rate ({tp_rate:.1f}%)")
        
        # Determine status
        if severity >= 50:
            status = 'FAIL'
            message = "Unrealistic trade outcomes detected"
        elif severity >= 20:
            status = 'WARN'
            message = "Some trades appear too perfect"
        else:
            status = 'PASS'
            message = "Trade outcomes appear realistic"
        
        return BiasCheckResult(
            bias_type="Perfect Trades",
            status=status,
            severity=min(100, severity),
            message=message,
            details={
                'all_profitable': all_profitable,
                'max_drawdown': round(max_dd, 2),
                'tp_hit_rate': round(tp_rate, 2),
                'issues': issues
            }
        )
    
    @staticmethod
    def check_time_distribution(trades: List[Dict]) -> BiasCheckResult:
        """
        Check for time distribution bias.
        
        Trades should be distributed across the test period, not clustered.
        """
        if not trades or len(trades) < 10:
            return BiasCheckResult(
                bias_type="Time Distribution",
                status="PASS",
                severity=0,
                message="Insufficient trades for time analysis",
                details={}
            )
        
        severity = 0
        issues = []
        
        # Extract entry times
        entry_times = []
        for t in trades:
            entry = t.get('entry_time')
            if entry:
                if isinstance(entry, str):
                    try:
                        entry = datetime.fromisoformat(entry.replace('Z', '+00:00'))
                    except:
                        continue
                entry_times.append(entry)
        
        if len(entry_times) < 10:
            return BiasCheckResult(
                bias_type="Time Distribution",
                status="PASS",
                severity=0,
                message="Insufficient timestamped trades",
                details={}
            )
        
        # Calculate time gaps
        entry_times = sorted(entry_times)
        gaps = [(entry_times[i+1] - entry_times[i]).total_seconds() / 3600 
                for i in range(len(entry_times) - 1)]
        
        # Check for clustering
        avg_gap = np.mean(gaps)
        std_gap = np.std(gaps)
        
        # High variance suggests uneven distribution
        cv = std_gap / avg_gap if avg_gap > 0 else 0  # Coefficient of variation
        
        if cv > 3:
            severity += 25
            issues.append("Trades are highly clustered in time")
        elif cv > 2:
            severity += 10
            issues.append("Some trade clustering detected")
        
        # Check for trading only in favorable periods
        # (This would require market data to fully implement)
        
        # Determine status
        if severity >= 40:
            status = 'FAIL'
            message = "Significant time distribution bias"
        elif severity >= 20:
            status = 'WARN'
            message = "Minor time distribution issues"
        else:
            status = 'PASS'
            message = "Trades well distributed over time"
        
        return BiasCheckResult(
            bias_type="Time Distribution",
            status=status,
            severity=min(100, severity),
            message=message,
            details={
                'avg_gap_hours': round(avg_gap, 2),
                'gap_cv': round(cv, 2),
                'issues': issues
            }
        )
    
    @staticmethod
    def check_parameter_sensitivity(strategy_params: Dict) -> BiasCheckResult:
        """
        Check if strategy is overly sensitive to parameter values.
        
        A robust strategy should work with a range of similar parameters.
        """
        severity = 0
        issues = []
        
        # Count number of parameters
        num_params = len(strategy_params)
        
        if num_params > 15:
            severity += 40
            issues.append(f"Too many parameters ({num_params}) - hard to validate")
        elif num_params > 10:
            severity += 20
            issues.append(f"Many parameters ({num_params}) - validation challenging")
        
        # Check for extreme values
        for key, value in strategy_params.items():
            if isinstance(value, (int, float)):
                # Check for very small or large values
                if abs(value) > 1000:
                    severity += 5
                    issues.append(f"Large parameter value: {key}={value}")
                elif isinstance(value, float) and abs(value) < 0.001 and value != 0:
                    severity += 5
                    issues.append(f"Very small parameter: {key}={value}")
        
        # Determine status
        if severity >= 40:
            status = 'FAIL'
            message = "Strategy appears over-parameterized"
        elif severity >= 20:
            status = 'WARN'
            message = "Strategy has many parameters"
        else:
            status = 'PASS'
            message = "Parameter count is reasonable"
        
        return BiasCheckResult(
            bias_type="Parameter Sensitivity",
            status=status,
            severity=min(100, severity),
            message=message,
            details={
                'num_parameters': num_params,
                'issues': issues
            }
        )


# Convenience function for API
def check_biases(
    trades: List[Dict],
    strategy_params: Optional[Dict] = None
) -> Dict:
    """Check for backtesting biases"""
    report = BiasDetector.run_all_checks(
        trades=trades,
        strategy_params=strategy_params
    )
    
    return {
        "overall_status": report.overall_status,
        "overall_score": report.overall_score,
        "recommendation": report.recommendation,
        "checks": [
            {
                "bias_type": c.bias_type,
                "status": c.status,
                "severity": c.severity,
                "message": c.message,
                "details": c.details
            }
            for c in report.checks
        ],
        "timestamp": report.timestamp.isoformat()
    }
