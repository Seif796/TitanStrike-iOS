"""
Titan Strike 3D - Hugging Face Spaces Entrypoint (Port 7860).
Runs the 24/7 Update Server, Admin Dashboard, and Ultra-Fast Telegram Gemini Bot Agent.
"""
import os
import sys
from pathlib import Path

# Ensure root and server directory are on Python path
BASE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(BASE_DIR))
sys.path.insert(0, str(BASE_DIR / "server"))

# Hugging Face Spaces listens on port 7860 by default
if not os.environ.get("PORT"):
    os.environ["PORT"] = "7860"

os.environ["HUGGINGFACE"] = "true"

import update_server

if __name__ == "__main__":
    print("=" * 70)
    print("🚀 Launching Titan Strike 3D Cloud Server & Telegram Bot on Hugging Face Spaces!")
    print(f"📡 Serving on Port: {os.environ.get('PORT')}")
    print("=" * 70)
    update_server.run_server()
