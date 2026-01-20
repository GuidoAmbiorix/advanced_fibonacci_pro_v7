"""
Backend Startup Script
"""
import sys
import os
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables from project root
project_root = Path(__file__).parent.parent
env_file = project_root / ".env"
load_dotenv(env_file)

# Add app directory to Python path
app_dir = Path(__file__).parent / "app"
sys.path.insert(0, str(app_dir))

# Change to app directory for proper module resolution
os.chdir(str(app_dir))

# Now import and run
if __name__ == "__main__":
    import uvicorn
    from core.config import settings

    print(f"Starting {settings.APP_NAME} v{settings.APP_VERSION}")
    print(f"Server: http://{settings.HOST}:{settings.PORT}")
    print(f"API Docs: http://{settings.HOST}:{settings.PORT}/docs")

    uvicorn.run(
        "main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
        log_level="info"
    )
