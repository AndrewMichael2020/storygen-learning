#!/bin/bash

# 🚀 StoryGen Complete Startup Script (with Authentication)
# =========================================================
# This script handles Google Cloud re-authentication and starts the Story Generation App
# It combines authentication checks with application startup for a seamless experience
#
# Prerequisites:
# 1. gcloud CLI installed
# 2. Valid Google Cloud Project (configured previously)
# 3. Node.js and npm installed
# 4. Python environment setup
#
# Usage:
#   ./start-with-auth.sh [PROJECT_ID]
#
# The script will automatically load configuration from ../.env if available:
#   GOOGLE_CLOUD_PROJECT_ID=your-project-id
#
# Examples:
#   ./start-with-auth.sh                    # Loads from .env or prompts
#   ./start-with-auth.sh my-project-id      # Use specific project

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Function to prompt for input with default
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    read -p "$prompt [$default]: " input
    if [ -z "$input" ]; then
        eval "$var_name=\"$default\""
    else
        eval "$var_name=\"$input\""
    fi
}

# Function to load environment variables from .env file
load_env_file() {
    local env_file="../.env"
    if [ -f "$env_file" ]; then
        echo -e "${GREEN}🔧 Loading configuration from $env_file${NC}"
        # Load environment variables, ignoring comments and empty lines
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip comments, empty lines, and lines without '='
            if [[ ! "$line" =~ ^[[:space:]]*# ]] && [[ -n "$line" ]] && [[ "$line" == *"="* ]]; then
                # Export the variable (remove quotes if present)
                export "$line"
            fi
        done < "$env_file"
        return 0
    else
        echo -e "${YELLOW}⚠️ No .env file found at $env_file${NC}"
        return 1
    fi
}

echo -e "${CYAN}🚀 StoryGen Complete Startup (with Authentication)${NC}"
echo -e "${CYAN}=================================================${NC}"
echo ""

# Get the script directory and navigate to it
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load .env file first (if available)
load_env_file

# ================================
# AUTHENTICATION SECTION
# ================================
echo -e "${MAGENTA}🔐 AUTHENTICATION PHASE${NC}"
echo -e "${MAGENTA}========================${NC}"

# Get project ID from command line, .env file, or prompt
if [ -n "$1" ]; then
    PROJECT_ID="$1"
elif [ -n "$GOOGLE_CLOUD_PROJECT_ID" ]; then
    PROJECT_ID="$GOOGLE_CLOUD_PROJECT_ID"
    echo -e "${GREEN}✅ Using PROJECT_ID from .env: $PROJECT_ID${NC}"
else
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
    if [ -n "$CURRENT_PROJECT" ]; then
        prompt_with_default "Google Cloud Project ID" "$CURRENT_PROJECT" "PROJECT_ID"
    else
        read -p "Google Cloud Project ID: " PROJECT_ID
    fi
fi

echo -e "${BLUE}Configuration:${NC}"
echo "  Project: $PROJECT_ID"
echo ""

# Prerequisites check
echo -e "${BLUE}📋 Checking Prerequisites${NC}"
echo "=========================="

if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}❌ gcloud CLI not found${NC}"
    echo "Please install: https://cloud.google.com/sdk/docs/install"
    exit 1
fi
echo -e "${GREEN}✅ gcloud CLI found${NC}"

if ! command -v node &> /dev/null; then
    echo -e "${RED}❌ Node.js not found${NC}"
    echo "Please install Node.js: https://nodejs.org/"
    exit 1
fi
echo -e "${GREEN}✅ Node.js found ($(node --version))${NC}"

if ! command -v npm &> /dev/null; then
    echo -e "${RED}❌ npm not found${NC}"
    echo "Please install npm (usually comes with Node.js)"
    exit 1
fi
echo -e "${GREEN}✅ npm found ($(npm --version))${NC}"

if ! command -v python &> /dev/null; then
    echo -e "${RED}❌ Python not found${NC}"
    echo "Please install Python 3.7+"
    exit 1
fi
echo -e "${GREEN}✅ Python found ($(python --version))${NC}"

# Check current authentication status
echo ""
echo -e "${BLUE}🔑 Checking Google Cloud Authentication${NC}"
CURRENT_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 2>/dev/null || echo "")

if [ -z "$CURRENT_ACCOUNT" ]; then
    echo -e "${YELLOW}⚠️ No active authentication found${NC}"
    echo -e "${BLUE}🔑 Starting authentication process...${NC}"
    
    # Start authentication
    gcloud auth login
    
    # Get the authenticated account
    CURRENT_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    
    if [ -z "$CURRENT_ACCOUNT" ]; then
        echo -e "${RED}❌ Authentication failed${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ Already authenticated as: ${CURRENT_ACCOUNT}${NC}"
    
    # Ask if user wants to re-authenticate with a different account
    echo ""
    read -p "Do you want to authenticate with a different account? (y/N): " re_auth
    if [[ "$re_auth" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}🔑 Re-authenticating...${NC}"
        gcloud auth login
        
        # Get the new authenticated account
        CURRENT_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
        echo -e "${GREEN}✅ Re-authenticated as: ${CURRENT_ACCOUNT}${NC}"
    fi
fi

# Validate project access
echo ""
echo "🔍 Validating project access..."
if ! gcloud projects describe "$PROJECT_ID" > /dev/null 2>&1; then
    echo -e "${RED}❌ Project '$PROJECT_ID' not accessible or doesn't exist${NC}"
    echo ""
    echo -e "${YELLOW}Available projects for ${CURRENT_ACCOUNT}:${NC}"
    gcloud projects list --format="table(projectId,name)" --limit=10
    echo ""
    read -p "Enter a valid project ID from the list above: " PROJECT_ID
    
    # Validate the new project ID
    if ! gcloud projects describe "$PROJECT_ID" > /dev/null 2>&1; then
        echo -e "${RED}❌ Project '$PROJECT_ID' still not accessible${NC}"
        echo "Please ensure you have access to the project and try again."
        exit 1
    fi
fi
echo -e "${GREEN}✅ Project '$PROJECT_ID' is accessible${NC}"

# Set project configuration
echo ""
echo "🔧 Setting project configuration..."
gcloud config set project "$PROJECT_ID"
echo -e "${GREEN}✅ Project set to: $PROJECT_ID${NC}"

# Verify application default credentials
echo ""
echo "🔑 Checking application default credentials..."
if ! gcloud auth application-default print-access-token > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️ Application default credentials not set${NC}"
    echo -e "${BLUE}🔧 Setting up application default credentials...${NC}"
    
    # Set application default credentials
    gcloud auth application-default login
    echo -e "${GREEN}✅ Application default credentials configured${NC}"
else
    echo -e "${GREEN}✅ Application default credentials already configured${NC}"
fi

echo ""
echo -e "${GREEN}🎉 Authentication Complete!${NC}"
echo -e "${GREEN}=============================${NC}"
echo -e "${GREEN}✅ Authenticated as: ${CURRENT_ACCOUNT}${NC}"
echo -e "${GREEN}✅ Active project: ${PROJECT_ID}${NC}"
echo -e "${GREEN}✅ Application default credentials: Ready${NC}"
echo ""

# ================================
# APPLICATION STARTUP SECTION
# ================================
echo -e "${MAGENTA}🚀 APPLICATION STARTUP PHASE${NC}"
echo -e "${MAGENTA}==============================${NC}"

# Activate virtual environment from parent directory
echo "📦 Setting up virtual environment..."
if [ -f "../.venv/bin/activate" ]; then
    source ../.venv/bin/activate
    echo -e "${GREEN}✅ Virtual environment activated${NC}"
elif [ -f "../../.venv/bin/activate" ]; then
    # Try two levels up (in case we're in a subdirectory)
    source ../../.venv/bin/activate
    echo -e "${GREEN}✅ Virtual environment activated (found at ../../.venv)${NC}"
else
    echo -e "${YELLOW}⚠️ Virtual environment not found. Setting up now...${NC}"
    echo "📋 Running shared virtual environment setup..."
    
    # Navigate to setup directory and run the setup script
    if [ -f "../00_Starting_Here/setup-shared-venv.sh" ]; then
        cd ../00_Starting_Here
        ./setup-shared-venv.sh
        cd "$SCRIPT_DIR"
        source ../.venv/bin/activate
        echo -e "${GREEN}✅ Virtual environment created and activated${NC}"
    else
        echo -e "${RED}❌ Setup script not found. Please run:${NC}"
        echo "  cd ../00_Starting_Here && ./setup-shared-venv.sh"
        echo "  Or manually create: cd .. && python -m venv .venv"
        exit 1
    fi
fi

# Setup Frontend
echo ""
echo -e "${BLUE}🎨 Setting up frontend...${NC}"
cd frontend

# Check if package.json exists
if [ ! -f "package.json" ]; then
    echo -e "${RED}❌ package.json not found in frontend directory${NC}"
    exit 1
fi

# Install dependencies
echo "📥 Installing npm dependencies..."
npm install

# Build the frontend
echo "🏗️ Building frontend..."
npm run build

echo -e "${GREEN}✅ Frontend build completed${NC}"

# Start Backend
echo ""
echo -e "${BLUE}🔧 Starting backend server...${NC}"
cd ../backend

# Check if main.py exists
if [ ! -f "main.py" ]; then
    echo -e "${RED}❌ main.py not found in backend directory${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}🌟 Starting Python backend server...${NC}"
echo -e "${CYAN}====================================${NC}"
echo -e "${GREEN}✅ Authentication: Complete${NC}"
echo -e "${GREEN}✅ Project: $PROJECT_ID${NC}"
echo -e "${GREEN}✅ Account: $CURRENT_ACCOUNT${NC}"
echo -e "${GREEN}✅ Frontend: Built and Ready${NC}"
echo -e "${GREEN}✅ Backend: Starting...${NC}"
echo ""
echo -e "${YELLOW}🌐 Backend will be running at: http://localhost:8000${NC}"
echo -e "${YELLOW}⏹️ Press Ctrl+C to stop the server${NC}"
echo "----------------------------------------"

# Start the backend server
python main.py
