"""
Script to replace all SQLite syntax with PostgreSQL syntax across the codebase.
Replaces ? placeholders with %s and removes _convert_query_to_postgres calls.
"""
import os
import re
from pathlib import Path

def fix_file(filepath):
    """Fix SQLite syntax in a single file."""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    original_content = content

    # Replace ? with %s in SQL queries (but not in comments or strings that aren't queries)
    # This is a simple replacement - assumes ? only appears in SQL queries
    content = re.sub(r'\?', '%s', content)

    # Remove _convert_query_to_postgres calls
    # Pattern: query, params = self.db._convert_query_to_postgres(query, params)
    # or: query, params = db._convert_query_to_postgres(query, params)
    content = re.sub(
        r'(\w+),\s*(\w+)\s*=\s*(?:self\.)?db\._convert_query_to_postgres\(\1,\s*\2\)\s*\n',
        '',
        content
    )

    if content != original_content:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        return True
    return False

def main():
    """Fix all Python files in the project."""
    project_root = Path(__file__).parent

    # Files to fix
    target_files = [
        'src/features/mtf_analyzer.py',
        'src/trading/signal_confirmation_manager.py',
        'src/trading/prediction_service.py',
        'src/trading/signal_validator.py',
        'src/trading/auto_trader.py',
        'src/trading/cooldown_manager.py',
        'retrain_all.py',
        'src/training/train_model.py',
        'src/training/optimize_model.py',
        'src/trading/portfolio_manager.py',
    ]

    fixed_count = 0
    for file_path in target_files:
        full_path = project_root / file_path
        if full_path.exists():
            if fix_file(full_path):
                print(f"[OK] Fixed: {file_path}")
                fixed_count += 1
            else:
                print(f"  Skipped (no changes): {file_path}")
        else:
            print(f"[ERROR] Not found: {file_path}")

    print(f"\n{fixed_count} files fixed")

if __name__ == '__main__':
    main()
