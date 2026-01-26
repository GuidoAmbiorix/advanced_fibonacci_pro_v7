#!/usr/bin/env python3
"""
Script to fix all MetaTrader5 imports in the project.
Replaces 'import MetaTrader5 as mt5' with mt5_compat import.
"""

import os
import re
from pathlib import Path

# Files to fix (from grep search)
FILES_TO_FIX = [
    "app.py",
    "src/connector.py",
    "src/portfolio/symbol_scorer.py",
    "src/portfolio/ea_communicator.py",
    "src/portfolio/correlation_engine.py",
    "src/multi_account/account_manager.py",
    "src/monitor/mt5_helpers.py",
    "src/monitor/health_checker.py",
    "src/monitor/governor_monitor.py",
    "src/monitor/ea_status_checker.py",
    "src/monitor/alert_manager.py",
]

def fix_file(filepath):
    """Fix MetaTrader5 imports in a single file."""
    print(f"Fixing {filepath}...")
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original = content
    
    # Replace standalone import line
    content = re.sub(
        r'^import MetaTrader5 as mt5\s*$',
        'from src.mt5_compat import mt5, MT5_AVAILABLE',
        content,
        flags=re.MULTILINE
    )
    
    # Replace in try/except blocks (for mt5_direct.py, mt5_compat.py - don't touch these)
    # They handle it themselves
    
    if content != original:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"  ✅ Fixed {filepath}")
        return True
    else:
        print(f"  ⏭️  No changes needed for {filepath}")
        return False

def main():
    """Main function."""
    os.chdir(Path(__file__).parent)
    
    fixed_count = 0
    for file_path in FILES_TO_FIX:
        if os.path.exists(file_path):
            if fix_file(file_path):
                fixed_count += 1
        else:
            print(f"  ⚠️  File not found: {file_path}")
    
    print(f"\n✅ Fixed {fixed_count} files")

if __name__ == "__main__":
    main()
