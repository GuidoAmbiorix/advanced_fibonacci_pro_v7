#!/bin/bash
################################################################################
# Analytics System Installation Script
################################################################################
# This script installs dependencies and sets up the analytics system
# Usage: bash INSTALL_ANALYTICS.sh
################################################################################

echo "================================================================================"
echo "DATABASE MAXIMIZATION SYSTEM - INSTALLATION"
echo "================================================================================"
echo ""

# Check if we're in the right directory
if [ ! -f "analytics_scheduler.py" ]; then
    echo "❌ Error: analytics_scheduler.py not found"
    echo "   Please run this script from the dashboard directory"
    exit 1
fi

echo "📦 Step 1: Installing Python dependencies..."
echo "--------------------------------------------------------------------------------"

# Try different pip commands
if command -v pip3 &> /dev/null; then
    pip3 install apscheduler scikit-learn scipy
elif command -v pip &> /dev/null; then
    pip install apscheduler scikit-learn scipy
elif command -v python3 &> /dev/null; then
    python3 -m pip install apscheduler scikit-learn scipy
elif command -v python &> /dev/null; then
    python -m pip install apscheduler scikit-learn scipy
else
    echo "❌ Error: pip not found. Please install pip first:"
    echo "   sudo apt-get install python3-pip"
    exit 1
fi

if [ $? -ne 0 ]; then
    echo "❌ Failed to install dependencies"
    exit 1
fi

echo ""
echo "✅ Dependencies installed successfully!"
echo ""

echo "🧪 Step 2: Validating Python modules..."
echo "--------------------------------------------------------------------------------"

python3 -c "
import sys
errors = []

try:
    from analytics_scheduler import AnalyticsScheduler
    print('✅ analytics_scheduler.py')
except Exception as e:
    print(f'❌ analytics_scheduler.py: {e}')
    errors.append('analytics_scheduler')

try:
    from ml_predictor import MLPredictor
    print('✅ ml_predictor.py')
except Exception as e:
    print(f'❌ ml_predictor.py: {e}')
    errors.append('ml_predictor')

try:
    from analytics_engine import AnalyticsEngine
    print('✅ analytics_engine.py')
except Exception as e:
    print(f'❌ analytics_engine.py: {e}')
    errors.append('analytics_engine')

try:
    from alerts_system import AlertsSystem
    print('✅ alerts_system.py')
except Exception as e:
    print(f'❌ alerts_system.py: {e}')
    errors.append('alerts_system')

if errors:
    print(f'\n❌ Some modules failed to load: {errors}')
    sys.exit(1)
else:
    print('\n✅ All modules validated successfully!')
"

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Module validation failed"
    exit 1
fi

echo ""
echo "📝 Step 3: Checking database..."
echo "--------------------------------------------------------------------------------"

if [ -f "PortfolioGovernor.sqlite" ]; then
    echo "✅ Database found: PortfolioGovernor.sqlite"
else
    echo "⚠️  Database not found: PortfolioGovernor.sqlite"
    echo "   The system will look for it at runtime"
fi

echo ""
echo "================================================================================"
echo "✅ INSTALLATION COMPLETE!"
echo "================================================================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Run initial backfill (populate analytics for last 30 days):"
echo "   python run_analytics.py backfill --days 30"
echo ""
echo "2. Check for alerts:"
echo "   python run_analytics.py alerts"
echo ""
echo "3. Train ML model (optional, requires historical data):"
echo "   python run_analytics.py ml-train --save ml_model.pkl"
echo ""
echo "4. Start scheduler (runs in background):"
echo "   python run_analytics.py schedule --immediate"
echo ""
echo "5. OR run full pipeline:"
echo "   python run_analytics.py full-pipeline --days 30"
echo ""
echo "For help with any command:"
echo "   python run_analytics.py --help"
echo ""
echo "Documentation:"
echo "   - ANALYTICS_README.md (comprehensive guide)"
echo "   - MODULES_CREATED.txt (detailed summary)"
echo ""
echo "================================================================================"
