# Restart script for MT5 Bridge with cache clearing
Write-Host "Stopping MT5 Bridge..."
Stop-Process -Name python -Force -ErrorAction SilentlyContinue

Write-Host "Clearing Python cache..."
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue .\src\__pycache__
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue .\src\database\__pycache__
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue .\bridge\__pycache__

Write-Host "Starting MT5 Bridge..."
Start-Process -FilePath "python" -ArgumentList "bridge\mt5_bridge.py" -WorkingDirectory "." -NoNewWindow

Write-Host "Bridge restarted successfully!"
