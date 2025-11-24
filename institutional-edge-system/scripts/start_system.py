"""
============================================================================
Institutional Edge PRO - Complete System Startup Script
============================================================================
This script:
1. Checks database connectivity
2. Runs migrations (adds AI columns)
3. Trains initial AI model (if no model exists)
4. Starts the backend server
"""

import os
import sys
import subprocess
from pathlib import Path
from loguru import logger

project_root = Path(__file__).parent

def run_command(cmd, description):
    """Run a command and log output"""
    logger.info("=" * 70)
    logger.info(description)
    logger.info("=" * 70)

    try:
        result = subprocess.run(cmd, shell=True, check=True, capture_output=True, text=True)
        if result.stdout:
            print(result.stdout)
        return True
    except subprocess.CalledProcessError as e:
        logger.error(f"Error: {e}")
        if e.stderr:
            print(e.stderr)
        return False

def main():
    logger.info("")
    logger.info("=" * 70)
    logger.info("INSTITUTIONAL EDGE PRO - AI-POWERED TRADING SYSTEM")
    logger.info("=" * 70)
    logger.info("")

    os.chdir(str(project_root))

    # Step 1: Install/upgrade dependencies
    logger.info("Step 1: Installing dependencies...")
    if not run_command(
        "pip install -r requirements.txt",
        "Installing Python packages (includes XGBoost for AI)"
    ):
        logger.warning("Dependency installation had issues, continuing anyway...")

    # Step 2: Database migration - add AI columns
    logger.info("\nStep 2: Running database migrations...")
    if not run_command(
        "python add_ai_columns.py",
        "Adding AI confidence columns to database"
    ):
        logger.error("Database migration failed!")
        return False

    # Step 3: Train AI model
    logger.info("\nStep 3: Training AI model...")
    model_path = project_root / "backend" / "app" / "ml" / "models" / "signal_predictor.pkl"

    if model_path.exists():
        logger.info("[INFO] AI model already exists at: {}", model_path)
        logger.info("[INFO] Skipping training. Delete model file to retrain.")
    else:
        logger.info("[INFO] No AI model found. Training initial model...")
        if not run_command(
            "python backend/app/ml/train_model.py",
            "Training initial AI model with synthetic data"
        ):
            logger.warning("Model training failed. AI features will be disabled.")
            logger.warning("System will continue without AI predictions.")

    # Step 4: Start backend
    logger.info("\n" + "=" * 70)
    logger.info("✅ Setup complete! Starting backend server...")
    logger.info("=" * 70)
    logger.info("")
    logger.info("Backend API: http://localhost:8000")
    logger.info("API Docs: http://localhost:8000/docs")
    logger.info("Frontend: http://localhost:5173 (if running)")
    logger.info("")
    logger.info("Press CTRL+C to stop")
    logger.info("")

    os.chdir(str(project_root / "backend"))

    try:
        subprocess.run(
            "uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload",
            shell=True,
            check=True
        )
    except KeyboardInterrupt:
        logger.info("\n\nShutting down gracefully...")
    except Exception as e:
        logger.error(f"Backend error: {e}")
        return False

    return True

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
