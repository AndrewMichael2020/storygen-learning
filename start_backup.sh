#!/bin/bash

# Story Generation App Startup Script
# This script activates the virtual environment, builds the frontend, and starts the backend

set -e  # Exit on any error

echo "🚀 Starting Story Generation App..."

# Get the script directory and navigate to it
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Activate virtual environment from parent directory
echo "📦 Setting up virtual environment..."
if [ -f "../.venv/bin/activate" ]; then
    source ../.venv/bin/activate
    echo "✅ Virtual environment activated"
elif [ -f "../../.venv/bin/activate" ]; then
    # Try two levels up (in case we're in a subdirectory)
    source ../../.venv/bin/activate
    echo "✅ Virtual environment activated (found at ../../.venv)"
else
    echo "⚠️  Virtual environment not found. Setting up now..."
    echo "📋 Running shared virtual environment setup..."
    
    # Navigate to setup directory and run the setup script
    if [ -f "../00_Starting_Here/setup-shared-venv.sh" ]; then
        cd ../00_Starting_Here
        ./setup-shared-venv.sh
        cd "$SCRIPT_DIR"
        source ../.venv/bin/activate
        echo "✅ Virtual environment created and activated"
    else
        echo "❌ Setup script not found. Please run:"
        echo "  cd ../00_Starting_Here && ./setup-shared-venv.sh"
        echo "  Or manually create: cd .. && python -m venv .venv"
        exit 1
    fi
fi

# Setup Frontend
echo "🎨 Setting up frontend..."
cd frontend

# Install dependencies
echo "📥 Installing npm dependencies..."
npm install

# Build the frontend
echo "🏗️  Building frontend..."
npm run build

echo "✅ Frontend build completed"

# Start Backend
echo "🔧 Starting backend server..."
cd ../backend

# Check if main.py exists
if [ ! -f "main.py" ]; then
    echo "❌ main.py not found in backend directory"
    exit 1
fi

echo "🌟 Starting Python backend server..."
echo "Backend will be running at: http://localhost:8000"
echo "Press Ctrl+C to stop the server"
echo "----------------------------------------"

# Start the backend server
python main.py