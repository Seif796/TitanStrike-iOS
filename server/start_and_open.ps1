# CyberFort Auto-Start and Browser Launcher
$GameDir = "c:\Users\Administrator\OneDrive\Desktop\Game"
Set-Location -Path $GameDir

# Check if port 8080 is already active
$portActive = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue

if (-not $portActive) {
    # Start python server in background
    Start-Process -FilePath "python.exe" -ArgumentList "server/update_server.py" -WorkingDirectory $GameDir -WindowStyle Hidden
    Start-Sleep -Seconds 2
}

# Open the website / dashboard in default browser
Start-Process "http://localhost:8080"
