"""
============================================================================
Cryptography Utilities - Password Encryption
============================================================================
"""

from cryptography.fernet import Fernet
from app.core.config import settings
import base64
import hashlib


def get_encryption_key() -> bytes:
    """
    Generate a Fernet key from the JWT secret.
    Fernet requires a 32-byte base64-encoded key.
    """
    # Use JWT secret as the basis for encryption key
    secret = settings.JWT_SECRET_KEY.encode()
    # Hash to get consistent 32 bytes
    key = hashlib.sha256(secret).digest()
    # Fernet needs base64 encoding
    return base64.urlsafe_b64encode(key)


def encrypt_password(plain_password: str) -> str:
    """
    Encrypt a password using Fernet symmetric encryption.
    
    Args:
        plain_password: The plain text password
        
    Returns:
        Encrypted password as base64 string
    """
    key = get_encryption_key()
    fernet = Fernet(key)
    encrypted = fernet.encrypt(plain_password.encode())
    return encrypted.decode()


def decrypt_password(encrypted_password: str) -> str:
    """
    Decrypt a password that was encrypted with encrypt_password.
    
    Args:
        encrypted_password: The encrypted password string
        
    Returns:
        Plain text password
    """
    key = get_encryption_key()
    fernet = Fernet(key)
    decrypted = fernet.decrypt(encrypted_password.encode())
    return decrypted.decode()
