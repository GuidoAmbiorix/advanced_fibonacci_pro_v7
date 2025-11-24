"""
Simple Database Initialization Script
"""

import os
import sys
from pathlib import Path

# Setup paths
project_root = Path(__file__).parent
backend_path = project_root / "backend" / "app"
sys.path.insert(0, str(backend_path))

# Set working directory
os.chdir(str(project_root))

from sqlalchemy import create_engine, text
from sqlalchemy.exc import OperationalError
from dotenv import load_dotenv

# Load environment
load_dotenv()

DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql://postgres:postgres@localhost:5432/institutional_edge')

print("=" * 70)
print("Institutional Edge PRO - Database Initialization")
print("=" * 70)
print(f"\nDatabase URL: {DATABASE_URL.split('@')[1] if '@' in DATABASE_URL else DATABASE_URL}")

# Test connection
print("\n[1/3] Testing database connection...")
try:
    engine = create_engine(DATABASE_URL, pool_pre_ping=True)
    with engine.connect() as conn:
        result = conn.execute(text("SELECT version()"))
        version = result.fetchone()[0]
    print(f"[OK] Connected successfully!")
    print(f"PostgreSQL version: {version.split(',')[0]}")
except OperationalError as e:
    print(f"[ERROR] Connection failed: {e}")
    print("\nTroubleshooting:")
    print("1. Start Docker: docker-compose up -d")
    print("2. Check containers: docker-compose ps")
    print("3. View logs: docker-compose logs postgres")
    sys.exit(1)

# Create tables
print("\n[2/3] Creating database tables...")
try:
    from models.database import Base

    Base.metadata.create_all(bind=engine)

    # Verify tables
    with engine.connect() as conn:
        result = conn.execute(text(
            "SELECT tablename FROM pg_catalog.pg_tables "
            "WHERE schemaname = 'public' ORDER BY tablename"
        ))
        tables = [row[0] for row in result]

    print(f"[OK] Created {len(tables)} tables:")
    for table in tables:
        print(f"   - {table}")

except Exception as e:
    print(f"[ERROR] Failed to create tables: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

# Create initial admin user
print("\n[3/3] Creating initial data...")
try:
    from sqlalchemy.orm import sessionmaker
    from models.database import User, BotConfig
    import bcrypt

    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    db = SessionLocal()

    # Check if admin exists
    existing = db.query(User).filter(User.email == "admin@institutional-edge.com").first()

    if not existing:
        # Create admin user with bcrypt directly
        password = "admin123"
        hashed = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())

        admin = User(
            email="admin@institutional-edge.com",
            username="admin",
            hashed_password=hashed.decode('utf-8'),
            is_active=True,
            is_admin=True
        )
        db.add(admin)
        db.commit()
        db.refresh(admin)

        print("[OK] Created admin user:")
        print("   Email: admin@institutional-edge.com")
        print("   Password: admin123")
        print("   [WARNING] Change this password after first login!")

        # Create default bot config
        bot = BotConfig(
            user_id=admin.id,
            name="Default EURUSD Bot",
            symbol="EURUSD",
            timeframe="H1",
            risk_percent=2.0,
            min_confluence_score=6,
            max_trades=3,
            is_active=False
        )
        db.add(bot)
        db.commit()

        print("[OK] Created default bot configuration")
    else:
        print("[INFO] Admin user already exists")

    db.close()

except Exception as e:
    print(f"[WARNING] Could not create initial data: {e}")
    print("You can create users manually later")

# Success!
print("\n" + "=" * 70)
print("[OK] Database initialization completed successfully!")
print("=" * 70)
print("\nNext steps:")
print("1. Start backend: cd backend/app && python main.py")
print("2. API docs: http://localhost:8000/docs")
print("3. PgAdmin: http://localhost:5050")
print("=" * 70)
