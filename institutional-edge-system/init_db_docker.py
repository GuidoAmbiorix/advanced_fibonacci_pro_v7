"""
Database Initialization via Docker
This script runs the initialization directly in the Docker container to avoid local PostgreSQL conflicts
"""

import subprocess
import os
from pathlib import Path

project_root = Path(__file__).parent

print("=" * 70)
print("Institutional Edge PRO - Database Initialization (Docker Method)")
print("=" * 70)

# Read the SQL schema from models
print("\n[1/2] Generating database schema...")

sql_commands = """
-- Create users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR UNIQUE NOT NULL,
    username VARCHAR UNIQUE NOT NULL,
    hashed_password VARCHAR NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    is_admin BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create bot_configs table
CREATE TABLE IF NOT EXISTS bot_configs (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    name VARCHAR NOT NULL,
    mt5_login VARCHAR,
    mt5_server VARCHAR,
    symbol VARCHAR DEFAULT 'EURUSD',
    timeframe VARCHAR DEFAULT 'H1',
    risk_percent FLOAT DEFAULT 2.0,
    min_confluence_score INTEGER DEFAULT 6,
    max_trades INTEGER DEFAULT 3,
    is_active BOOLEAN DEFAULT FALSE,
    last_signal_time TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create trades table
CREATE TABLE IF NOT EXISTS trades (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    ticket INTEGER UNIQUE,
    symbol VARCHAR NOT NULL,
    trade_type VARCHAR NOT NULL,
    entry_price FLOAT NOT NULL,
    stop_loss FLOAT,
    take_profit_1 FLOAT,
    take_profit_2 FLOAT,
    take_profit_3 FLOAT,
    exit_price FLOAT,
    volume FLOAT NOT NULL,
    risk_percent FLOAT NOT NULL,
    confluence_score INTEGER NOT NULL,
    score_breakdown JSONB,
    status VARCHAR DEFAULT 'OPEN',
    profit_loss FLOAT DEFAULT 0.0,
    opened_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    closed_at TIMESTAMP
);

-- Create signals table
CREATE TABLE IF NOT EXISTS signals (
    id SERIAL PRIMARY KEY,
    symbol VARCHAR NOT NULL,
    timeframe VARCHAR NOT NULL,
    signal_type VARCHAR NOT NULL,
    price FLOAT NOT NULL,
    stop_loss FLOAT NOT NULL,
    take_profit FLOAT NOT NULL,
    confluence_score INTEGER NOT NULL,
    score_breakdown JSONB,
    trend VARCHAR NOT NULL,
    poc_level FLOAT,
    was_executed BOOLEAN DEFAULT FALSE,
    trade_id INTEGER REFERENCES trades(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_trades_user_id ON trades(user_id);
CREATE INDEX IF NOT EXISTS idx_trades_status ON trades(status);
CREATE INDEX IF NOT EXISTS idx_signals_created_at ON signals(created_at);
"""

# Write SQL to temp file
sql_file = project_root / "init_schema.sql"
with open(sql_file, 'w') as f:
    f.write(sql_commands)

print(f"Generated schema file: {sql_file}")

# Execute via Docker
print("\n[2/2] Creating tables in PostgreSQL...")
try:
    # Copy SQL file into container
    subprocess.run([
        "docker", "cp",
        str(sql_file),
        "institutional_edge_db:/tmp/init_schema.sql"
    ], check=True, capture_output=True)

    # Execute SQL
    result = subprocess.run([
        "docker", "exec", "institutional_edge_db",
        "psql", "-U", "postgres", "-d", "institutional_edge",
        "-f", "/tmp/init_schema.sql"
    ], check=True, capture_output=True, text=True)

    print("✓ Tables created successfully!")

    # Verify tables
    result = subprocess.run([
        "docker", "exec", "institutional_edge_db",
        "psql", "-U", "postgres", "-d", "institutional_edge",
        "-c", "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename;"
    ], check=True, capture_output=True, text=True)

    print("\nCreated tables:")
    print(result.stdout)

    # Create admin user
    print("\n[3/3] Creating admin user...")
    create_user_sql = """
INSERT INTO users (email, username, hashed_password, is_active, is_admin)
VALUES ('admin@institutional-edge.com', 'admin', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5SupWJVEEOm2e', TRUE, TRUE)
ON CONFLICT (email) DO NOTHING;
"""

    user_sql_file = project_root / "create_user.sql"
    with open(user_sql_file, 'w') as f:
        f.write(create_user_sql)

    subprocess.run([
        "docker", "cp",
        str(user_sql_file),
        "institutional_edge_db:/tmp/create_user.sql"
    ], check=True, capture_output=True)

    result = subprocess.run([
        "docker", "exec", "institutional_edge_db",
        "psql", "-U", "postgres", "-d", "institutional_edge",
        "-f", "/tmp/create_user.sql"
    ], check=True, capture_output=True, text=True)

    print("✓ Admin user created!")
    print("   Email: admin@institutional-edge.com")
    print("   Password: admin123")
    print("   (Change this after first login!)")

    # Cleanup temp files
    sql_file.unlink(missing_ok=True)
    user_sql_file.unlink(missing_ok=True)

    print("\n" + "=" * 70)
    print("✓ Database initialization completed successfully!")
    print("=" * 70)
    print("\nNext steps:")
    print("1. Start backend: cd backend/app && python main.py")
    print("2. API docs: http://localhost:8000/docs")
    print("3. PgAdmin: http://localhost:5050")
    print("=" * 70)

except subprocess.CalledProcessError as e:
    print(f"✗ Error: {e}")
    print(f"Output: {e.output if hasattr(e, 'output') else 'N/A'}")
    print("\nTroubleshooting:")
    print("1. Check if Docker is running: docker ps")
    print("2. Check containers: docker-compose ps")
    print("3. View logs: docker-compose logs postgres")
except Exception as e:
    print(f"✗ Unexpected error: {e}")
