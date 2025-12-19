import sys
import os
from sqlalchemy import text, inspect

# Add the parent directory to sys.path to allow importing app modules
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.api.database import engine

def verify_schema():
    print("Verifying schema...")
    inspector = inspect(engine)
    columns = inspector.get_columns('bot_configs')
    
    print("Columns in bot_configs table:")
    found_rsi = False
    for column in columns:
        print(f"- {column['name']} ({column['type']})")
        if column['name'] == 'rsi_period':
            found_rsi = True
            
    if found_rsi:
        print("\n✅ rsi_period column FOUND.")
    else:
        print("\n❌ rsi_period column NOT FOUND.")

if __name__ == "__main__":
    verify_schema()
