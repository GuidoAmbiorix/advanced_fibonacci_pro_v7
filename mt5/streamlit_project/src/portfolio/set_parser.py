"""
Set Parser - Parse MT5 .set files to extract EA configuration.
Extracts magic numbers, risk settings, killzone preferences, and header comments.
"""

from pathlib import Path
from typing import Dict, Any, Optional, List
import re


def parse_set_file(file_path: Path) -> Dict[str, Any]:
    """
    Parse a single .set file and extract relevant configuration.
    
    Returns dict with:
        - symbol: str (derived from filename)
        - magic_number: int
        - risk_base: float
        - killzones: dict of enabled sessions
        - header_comments: list of header comment lines
        - all_params: dict of all parameters
    """
    result = {
        "symbol": file_path.stem.upper(),
        "magic_number": 0,
        "risk_base": 0.5,
        "killzones": {
            "asian": False,
            "london": False,
            "ny": False,
            "london_close": False
        },
        "header_comments": [],
        "all_params": {}
    }
    
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        return result
    
    in_header = True
    
    for line in lines:
        line = line.strip()
        
        # Skip empty lines
        if not line:
            continue
        
        # Parse comments (header section)
        if line.startswith(';'):
            if in_header:
                result["header_comments"].append(line[1:].strip())
            continue
        
        # No longer in header after first parameter
        in_header = False
        
        # Parse key=value pairs
        if '=' in line:
            key, value = line.split('=', 1)
            key = key.strip()
            value = value.strip()
            
            # Store all parameters
            result["all_params"][key] = value
            
            # Extract specific important values
            if key == "InpMagicNumber":
                result["magic_number"] = int(value)
            elif key == "InpRiskBase":
                result["risk_base"] = float(value)
            elif key == "InpEnableAsianKZ":
                result["killzones"]["asian"] = value.lower() == "true"
            elif key == "InpEnableLondonOpenKZ":
                result["killzones"]["london"] = value.lower() == "true"
            elif key == "InpEnableNYKZ":
                result["killzones"]["ny"] = value.lower() == "true"
            elif key == "InpEnableLondonCloseKZ":
                result["killzones"]["london_close"] = value.lower() == "true"
    
    return result


def parse_all_sets(sets_dir: Path) -> Dict[str, Dict[str, Any]]:
    """
    Parse all .set files in a directory.
    
    Returns dict mapping symbol name to parsed configuration.
    """
    result = {}
    
    if not sets_dir.exists():
        print(f"Sets directory not found: {sets_dir}")
        return result
    
    for set_file in sets_dir.glob("*.set"):
        parsed = parse_set_file(set_file)
        symbol = parsed["symbol"]
        result[symbol] = parsed
    
    return result


def extract_correlation_hints(header_comments: List[str]) -> Dict[str, float]:
    """
    Extract correlation hints from header comments.
    
    Looks for patterns like:
    - "Correlation: +0.70 with GBPUSD"
    - "Correlation: +0.95 with EURUSD, -0.80 with USDJPY"
    
    Returns dict mapping symbol to correlation value.
    """
    correlations = {}
    
    for comment in header_comments:
        if "correlation" in comment.lower():
            # Pattern: +0.XX or -0.XX followed by optional "with" and symbol
            pattern = r'([+-]?\d+\.?\d*)\s*(?:with\s+)?([A-Z]{6}|[A-Z]{2}\d{2})'
            matches = re.findall(pattern, comment, re.IGNORECASE)
            
            for value, symbol in matches:
                try:
                    correlations[symbol.upper()] = float(value)
                except ValueError:
                    pass
    
    return correlations


def extract_target_metrics(header_comments: List[str]) -> Dict[str, Any]:
    """
    Extract target performance metrics from header comments.
    
    Looks for patterns like:
    - "Target: Win Rate 62-72%, Profit Factor 2.0+"
    
    Returns dict with target_win_rate_low, target_win_rate_high, target_pf.
    """
    targets = {
        "target_win_rate_low": 0.0,
        "target_win_rate_high": 0.0,
        "target_pf": 0.0
    }
    
    for comment in header_comments:
        if "target" in comment.lower():
            # Win rate pattern: XX-YY% or XX%
            wr_pattern = r'win\s*rate\s*(\d+)[-–]?(\d+)?%'
            wr_match = re.search(wr_pattern, comment, re.IGNORECASE)
            if wr_match:
                targets["target_win_rate_low"] = float(wr_match.group(1))
                if wr_match.group(2):
                    targets["target_win_rate_high"] = float(wr_match.group(2))
                else:
                    targets["target_win_rate_high"] = targets["target_win_rate_low"]
            
            # Profit factor pattern: X.X+
            pf_pattern = r'profit\s*factor\s*(\d+\.?\d*)\+?'
            pf_match = re.search(pf_pattern, comment, re.IGNORECASE)
            if pf_match:
                targets["target_pf"] = float(pf_match.group(1))
    
    return targets


def get_symbol_from_magic(magic_number: int, sets_data: Dict[str, Dict]) -> Optional[str]:
    """
    Find symbol by magic number.
    
    Returns symbol name or None if not found.
    """
    for symbol, data in sets_data.items():
        if data.get("magic_number") == magic_number:
            return symbol
    return None
