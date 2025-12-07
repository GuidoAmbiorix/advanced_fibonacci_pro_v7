from app.api import database
from app.models.database import User, Base
from sqlalchemy.orm import Session
from passlib.context import CryptContext

# Use pbkdf2_sha256 to avoid bcrypt issues on Windows
pwd_context = CryptContext(schemes=["pbkdf2_sha256"], deprecated="auto")

def create_default_user():
    db = database.SessionLocal()
    try:
        # Check existing
        existing = db.query(User).filter(User.id == 1).first()
        if existing:
            print(f"User 1 already exists: {existing.username}")
            return

        print("Creating default user (ID 1)...")
        hashed_password = pwd_context.hash("admin")
        user = User(
            id=1,
            email="admin@example.com",
            username="admin",
            hashed_password=hashed_password,
            is_active=True,
            is_admin=True
        )
        db.add(user)
        db.commit()
        print("Commit successful.")
        
        # Verify
        check = db.query(User).filter(User.id == 1).first()
        if check:
            print(f"VERIFIED: User {check.id} created successfully.")
        else:
            print("ERROR: User was committed but cannot be found!")
            
    except Exception as e:
        print(f"Error creating user: {e}")
        import traceback
        traceback.print_exc()
    finally:
        db.close()

if __name__ == "__main__":
    create_default_user()
