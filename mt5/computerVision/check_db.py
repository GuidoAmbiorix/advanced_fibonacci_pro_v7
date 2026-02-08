import sys
sys.path.append('.')
from src.database import DatabaseManager

db = DatabaseManager()
conn = db.get_connection()
cursor = conn.execute('SELECT symbol, timeframe, COUNT(*) as cnt FROM market_data GROUP BY symbol, timeframe')

print('Data in database:')
rows = cursor.fetchall()
if len(rows) == 0:
    print('  No data found!')
else:
    for row in rows:
        print(f'  {row[0]} {row[1]}: {row[2]} bars')

conn.close()
