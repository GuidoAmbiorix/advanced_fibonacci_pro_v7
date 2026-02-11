"""
Script to replace pd.read_sql_query with execute + DataFrame pattern.
"""
import re
from pathlib import Path

def fix_file(filepath):
    """Fix pd.read_sql_query in a single file."""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    original_content = content

    # Pattern 1: df = pd.read_sql_query(query, conn, params=(param1, param2))
    # Replace with cursor approach
    pattern1 = r'(\s+)(df\s*=\s*)pd\.read_sql_query\((\w+),\s*conn,\s*params=\(([^)]+)\)\)'
    replacement1 = r'''\1cursor = conn.execute(\3, (\4))
\1rows = cursor.fetchall()
\1\2pd.DataFrame([dict(row) for row in rows]) if rows else pd.DataFrame()'''

    content = re.sub(pattern1, replacement1, content)

    # Pattern 2: df = pd.read_sql_query(query, conn)
    pattern2 = r'(\s+)(df\s*=\s*)pd\.read_sql_query\((\w+),\s*conn\)'
    replacement2 = r'''\1cursor = conn.execute(\3)
\1rows = cursor.fetchall()
\1\2pd.DataFrame([dict(row) for row in rows]) if rows else pd.DataFrame()'''

    content = re.sub(pattern2, replacement2, content)

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
        'src/trading/signal_validator.py',
        'src/training/optimize_model.py',
        'src/training/train_model.py',
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
