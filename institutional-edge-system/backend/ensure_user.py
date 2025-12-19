"""
Ensure default admin user exists in the database.
Run this before starting the backend.
"""
import os
import sys

# Add backend to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.api.database import get_db, SessionLocal, engine
from app.models.database import User, Base

def ensure_default_user():
    """Create default admin user if not exists"""
    
    # Create all tables first
    print("Creating database tables if they don't exist...")
    Base.metadata.create_all(bind=engine)
    print("✓ Database tables ready")
    
    db = SessionLocal()
    
    try:
        # Check if any user exists
        existing_user = db.query(User).filter(User.id == 1).first()
        
        if existing_user:
            print(f"✓ Default user already exists: {existing_user.username}")
            return True
        
        # Create default admin user
        default_user = User(
            id=1,
            email="admin@institutional-edge.local",
            username="admin",
            hashed_password="not_used_for_local_development",
            is_active=True,
            is_admin=True
        )
        
        db.add(default_user)
        db.commit()
        print("✓ Created default admin user (id=1, username=admin)")
        return True
        
    except Exception as e:
        print(f"✗ Error creating default user: {e}")
        db.rollback()
        return False
    finally:
        db.close()

if __name__ == "__main__":
    print("=" * 50)
    print("Checking default user...")
    print("=" * 50)
    success = ensure_default_user()
    if success:
        print("Database user check complete!")
    else:
        print("Warning: Could not verify/create default user")
        sys.exit(1)
