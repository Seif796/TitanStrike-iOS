"""
Titan Strike 3D - Hugging Face Spaces Entrypoint (Port 7860).
Runs the 24/7 Update Server, Admin Dashboard, and Ultra-Fast Telegram Gemini Bot Agent.
"""
import os
import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent

# Check both server/ directory and root directory
if (BASE_DIR / "server").exists():
    sys.path.insert(0, str(BASE_DIR / "server"))
sys.path.insert(0, str(BASE_DIR))

# Hugging Face Spaces listens on port 7860 by default
if not os.environ.get("PORT"):
    os.environ["PORT"] = "7860"

os.environ["HUGGINGFACE"] = "true"

try:
    import update_server
except ImportError:
    # Try importing from server folder explicitly
    from server import update_server

if __name__ == "__main__":
    print("=" * 70)
    print("🚀 Launching Titan Strike 3D Cloud Server & Telegram Bot on Hugging Face Spaces!")
    print(f"📡 Serving on Port: {os.environ.get('PORT')}")
    print("=" * 70)
    update_server.run_server()
