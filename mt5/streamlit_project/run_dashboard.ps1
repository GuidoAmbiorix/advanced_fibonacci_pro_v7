# Elite MT5 Trading Intelligence Platform - PowerShell Launcher
# Enhanced launcher with full validation and error handling

param(
    [switch]$SkipChecks,
    [switch]$Debug,
    [switch]$NoBrowser
)

# Set console colors
$Host.UI.RawUI.BackgroundColor = "Black"
$Host.UI.RawUI.ForegroundColor = "Green"
Clear-Host

# Navigate to script directory
Set-Location $PSScriptRoot

# Helper functions
function Write-Step {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "   ✓ $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "   ⚠ $Message" -ForegroundColor Yellow
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "   ❌ $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "   → $Message" -ForegroundColor Gray
}

# Banner
Write-Host ""
Write-Host "====================================================================" -ForegroundColor Green
Write-Host "      Elite MT5 Trading Intelligence Platform - Launcher" -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Green
Write-Host ""
Write-Step "Starting initialization..."
Write-Host ""

# Step 1: Check Python
Write-Host "[1/7] Checking Python installation..." -ForegroundColor Cyan
try {
    $pythonVersion = python --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Python found: $pythonVersion"
    } else {
        throw "Python not found"
    }
} catch {
    Write-Error-Custom "Python is not installed or not in PATH"
    Write-Host ""
    Write-Host "Please install Python 3.8+ from: https://www.python.org/downloads/" -ForegroundColor Yellow
    Write-Host "Make sure to check 'Add Python to PATH' during installation" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host ""

# Step 2: Check Configuration
Write-Host "[2/7] Checking configuration..." -ForegroundColor Cyan
if (-not (Test-Path ".env")) {
    Write-Warning ".env file not found"
    if (Test-Path ".env.example") {
        Write-Info "Creating .env from .env.example..."
        Copy-Item ".env.example" ".env"
        Write-Success ".env file created"
        Write-Host ""
        Write-Warning "IMPORTANT: Please edit .env and update MT5_SETS_PATH"
        Write-Info "Default path: C:\Users\gamparo\Desktop\Projects\advanced_fibonacci_pro_v7\mt5\portafolio_manager\sets"
        Write-Host ""
    } else {
        Write-Warning ".env.example not found - using default configuration"
    }
} else {
    Write-Success ".env file found"
}
Write-Host ""

# Step 3: Create Directories
Write-Host "[3/7] Creating required directories..." -ForegroundColor Cyan
@("logs", "data") | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
        Write-Info "Created $_ directory"
    }
}
Write-Success "Directories ready"
Write-Host ""

# Step 4: Check Dependencies
Write-Host "[4/7] Checking dependencies..." -ForegroundColor Cyan
$streamlitInstalled = pip show streamlit 2>&1 | Select-String "Name: streamlit"
if (-not $streamlitInstalled) {
    Write-Warning "Dependencies not installed"
    Write-Info "Installing required packages..."
    Write-Host ""
    pip install -r requirements.txt
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "Failed to install dependencies"
        Write-Host ""
        Write-Host "Please manually run: pip install -r requirements.txt" -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Success "Dependencies installed"
} else {
    Write-Success "Dependencies already installed"
}
Write-Host ""

# Step 5: Check MT5 Terminal
Write-Host "[5/7] Checking MetaTrader 5..." -ForegroundColor Cyan
$mt5Process = Get-Process -Name "terminal64" -ErrorAction SilentlyContinue
if ($mt5Process) {
    Write-Success "MT5 Terminal is running (PID: $($mt5Process.Id))"
} else {
    Write-Warning "MT5 Terminal (terminal64.exe) not detected"
    Write-Info "Please ensure MT5 is running before connecting"
}
Write-Host ""

# Step 6: Validate Configuration (if not skipped)
if (-not $SkipChecks) {
    Write-Host "[6/7] Validating configuration..." -ForegroundColor Cyan
    if (Test-Path ".env") {
        $envContent = Get-Content ".env" -Raw
        if ($envContent -match 'MT5_SETS_PATH=(.+)') {
            $setsPath = $matches[1].Trim()
            if (Test-Path $setsPath) {
                $setFiles = Get-ChildItem -Path $setsPath -Filter "*.set" -ErrorAction SilentlyContinue
                if ($setFiles) {
                    Write-Success "MT5 sets directory valid ($($setFiles.Count) .set files found)"
                } else {
                    Write-Warning "No .set files found in $setsPath"
                }
            } else {
                Write-Warning "MT5 sets path not found: $setsPath"
                Write-Info "Update MT5_SETS_PATH in .env file"
            }
        } else {
            Write-Warning "MT5_SETS_PATH not configured in .env"
        }
    }
    Write-Host ""
} else {
    Write-Host "[6/7] Skipping configuration validation (--SkipChecks)" -ForegroundColor Gray
    Write-Host ""
}

# Step 7: Launch Application
Write-Host "[7/7] Launching application..." -ForegroundColor Cyan
Write-Host ""
Write-Host "====================================================================" -ForegroundColor Green
Write-Host "   Application starting on http://localhost:8501" -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "   • Configuration: .env"
Write-Host "   • Logs: logs/mt5_platform.log"
Write-Host "   • Errors: logs/mt5_platform_errors.log"
Write-Host ""
Write-Host "   Press Ctrl+C to stop the application"
Write-Host ""
Write-Host "====================================================================" -ForegroundColor Green
Write-Host ""

# Build Streamlit command
$streamlitArgs = @("run", "app.py")
if ($NoBrowser) {
    $streamlitArgs += "--server.headless", "true"
}
if ($Debug) {
    $streamlitArgs += "--logger.level", "debug"
}

# Launch Streamlit
try {
    python -m streamlit @streamlitArgs
} catch {
    Write-Host ""
    Write-Host "====================================================================" -ForegroundColor Red
    Write-Host "❌ Application failed to start" -ForegroundColor Red
    Write-Host "====================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting steps:"
    Write-Host "1. Check logs/mt5_platform_errors.log for details"
    Write-Host "2. Verify .env configuration (especially MT5_SETS_PATH)"
    Write-Host "3. Ensure MT5 Terminal is running"
    Write-Host "4. Try reinstalling: pip install -r requirements.txt"
    Write-Host ""
    Write-Host "For detailed help, see UPGRADE_GUIDE.md"
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# Normal exit
Write-Host ""
Write-Host "====================================================================" -ForegroundColor Green
Write-Host "Application closed normally" -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Green
Read-Host "Press Enter to exit"
