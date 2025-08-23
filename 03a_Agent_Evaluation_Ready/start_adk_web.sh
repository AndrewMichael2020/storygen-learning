#!/bin/bash
# ====================================================
# ADK Web UI Startup Script for Story Generation Agent
#
# This script:
# 1. Activates the virtual environment
# 2. Configures gcloud authentication and project settings
# 3. Starts the ADK Web UI with persistent session storage
#
# Usage:
#   ./start_adk_web.sh [PROJECT_ID]
# ====================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get the script directory and navigate to it
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${CYAN}🚀 Starting ADK Web UI for Story Generation Agent${NC}"
echo -e "${CYAN}==================================================${NC}"
echo ""

# --- Function to setup virtual environment ---
setup_virtual_env() {
    echo -e "${BLUE}📦 Setting up virtual environment...${NC}"
    
    if [ -f "../.venv/bin/activate" ]; then
        source ../.venv/bin/activate
        echo -e "${GREEN}✅ Virtual environment activated${NC}"
    elif [ -f "../../.venv/bin/activate" ]; then
        # Try two levels up (in case we're in a subdirectory)
        source ../../.venv/bin/activate
        echo -e "${GREEN}✅ Virtual environment activated (found at ../../.venv)${NC}"
    else
        echo -e "${YELLOW}⚠️  Virtual environment not found. Setting up now...${NC}"
        echo -e "${BLUE}📋 Running shared virtual environment setup...${NC}"
        
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
}

# --- Function to check prerequisites ---
check_prerequisites() {
    echo -e "${BLUE}🔍 Checking prerequisites...${NC}"
    
    # Check for gcloud CLI
    if ! command -v gcloud &> /dev/null; then
        echo -e "${RED}❌ gcloud CLI not found. Please install it to continue.${NC}"
        echo "   Follow instructions at: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    echo -e "${GREEN}✅ gcloud CLI is installed.${NC}"

    # Check for python
    if ! command -v python &> /dev/null && ! command -v python3 &> /dev/null; then
        echo -e "${RED}❌ Python not found. Please install Python.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Python is installed.${NC}"

    # Check for adk command
    if ! command -v adk &> /dev/null; then
        echo -e "${RED}❌ ADK CLI not found. Please ensure it's installed in your virtual environment.${NC}"
        echo "   You may need to run: pip install google-adk"
        exit 1
    fi
    echo -e "${GREEN}✅ ADK CLI is available.${NC}"

    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
        echo -e "${YELLOW}⚠️ You are not logged into gcloud.${NC}"
        echo -e "${BLUE}Please log in with your Google account...${NC}"
        gcloud auth login
    fi
    
    local current_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1)
    echo -e "${GREEN}✅ Authenticated as: ${current_account}${NC}"
}

# --- Function to get project configuration ---
get_project_config() {
    if [ -n "$1" ]; then
        PROJECT_ID="$1"
        echo -e "${GREEN}✅ Using Project ID from argument: $PROJECT_ID${NC}"
    else
        local current_project
        current_project=$(gcloud config get-value project 2>/dev/null)
        
        if [ -n "$current_project" ]; then
            read -p "$(echo -e "${YELLOW}❓ Project ID is currently set to '$current_project'. Use this one? (Y/n): ${NC}")" -r use_current
            if [[ $use_current =~ ^[Nn]$ ]]; then
                 read -p "$(echo -e "${BLUE}Enter your Google Cloud Project ID: ${NC}")" -r PROJECT_ID
            else
                PROJECT_ID=$current_project
            fi
        else
            read -p "$(echo -e "${BLUE}Enter your Google Cloud Project ID: ${NC}")" -r PROJECT_ID
        fi
    fi

    if [ -z "$PROJECT_ID" ]; then
        echo -e "${RED}❌ No Project ID provided. Exiting.${NC}"
        exit 1
    fi
    
    if ! gcloud projects describe "$PROJECT_ID" > /dev/null 2>&1; then
        echo -e "${RED}❌ Project '$PROJECT_ID' not found or you don't have access.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Project '$PROJECT_ID' is valid and accessible.${NC}"
}

# --- Function to configure authentication ---
configure_auth() {
    echo -e "${BLUE}🔧 Configuring gcloud project...${NC}"
    gcloud config set project "$PROJECT_ID"
    echo -e "${GREEN}✅ gcloud project set to '$PROJECT_ID'.${NC}"
    
    echo -e "${BLUE}🔧 Setting up Application Default Credentials...${NC}"
    
    # Function to clean up and retry authentication
    retry_auth() {
        echo -e "${YELLOW}🔄 Cleaning up existing credentials and retrying...${NC}"
        gcloud auth application-default revoke 2>/dev/null || true
        echo -e "${BLUE}🔑 Starting fresh Application Default Credentials setup...${NC}"
        if ! gcloud auth application-default login; then
            echo -e "${RED}❌ Authentication failed. Please try manual setup:${NC}"
            echo "1. Run: gcloud auth application-default revoke"
            echo "2. Run: gcloud auth application-default login --no-browser"
            echo "3. Follow the instructions provided"
            exit 1
        fi
    }
    
    # Check if application default credentials file exists and is valid
    if [ ! -f "$HOME/.config/gcloud/application_default_credentials.json" ]; then
        echo -e "${YELLOW}⚠️ Application Default Credentials not found. Setting up now...${NC}"
        if ! gcloud auth application-default login; then
            retry_auth
        fi
    else
        echo -e "${GREEN}✅ Application Default Credentials file found${NC}"
        # Try to set quota project - if it fails, re-authenticate
        if ! gcloud auth application-default set-quota-project "$PROJECT_ID" 2>/dev/null; then
            echo -e "${YELLOW}⚠️ Existing credentials don't work or have scope issues. Re-authenticating...${NC}"
            retry_auth
        else
            echo -e "${GREEN}✅ Quota project set successfully${NC}"
            return 0
        fi
    fi
    
    # Set quota project after authentication
    echo -e "${BLUE}🔧 Setting quota project for Application Default Credentials...${NC}"
    if ! gcloud auth application-default set-quota-project "$PROJECT_ID"; then
        echo -e "${RED}❌ Failed to set quota project. Please run manually:${NC}"
        echo "gcloud auth application-default set-quota-project $PROJECT_ID"
        exit 1
    fi
    echo -e "${GREEN}✅ Quota project set to '$PROJECT_ID'.${NC}"
    
    echo -e "${GREEN}🎉 Authentication and project configuration complete!${NC}"
}

# --- Function to setup ADK Web UI ---
setup_adk_web() {
    echo -e "${BLUE}🌐 Setting up ADK Web UI with persistent session storage...${NC}"
    
    # Create sessions directory if it doesn't exist
    SESSIONS_DIR="$HOME/.adk/sessions"
    mkdir -p "$SESSIONS_DIR"
    
    # SQLite database file for session persistence
    DB_FILE="$SESSIONS_DIR/adk_web_sessions.db"
    SESSION_URI="sqlite:///$DB_FILE"
    
    echo -e "${BLUE}🗄️ Session database: $DB_FILE${NC}"
    echo -e "${BLUE}📡 Session URI: $SESSION_URI${NC}"
    
    # Navigate to backend directory where the agents are located
    cd backend
    
    echo ""
    echo -e "${GREEN}🌟 Starting ADK Web UI...${NC}"
    echo -e "${CYAN}🌐 ADK Web UI will be available at: http://localhost:8080${NC}"
    echo -e "${CYAN}📊 Evaluation results will persist across requests!${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop the server${NC}"
    echo "----------------------------------------"
    
    # Start ADK Web UI with persistent sessions
    adk web \
        --session_service_uri="$SESSION_URI" \
        --host=127.0.0.1 \
        --port=8080 \
        --log_level=info \
        --reload \
        .
    
    echo -e "${BLUE}🛑 ADK Web UI stopped${NC}"
}

# --- Main execution ---
main() {
    # Step 1: Setup virtual environment
    setup_virtual_env
    echo ""
    
    # Step 2: Check prerequisites and authentication
    check_prerequisites
    echo ""
    
    # Step 3: Configure project
    get_project_config "$@"
    echo ""
    
    # Step 4: Configure authentication
    configure_auth
    echo ""
    
    # Step 5: Setup and start ADK Web UI
    setup_adk_web
}

# Handle script interruption gracefully
cleanup_on_exit() {
    echo ""
    echo -e "${YELLOW}⚠️ ADK Web UI stopped by user${NC}"
    exit 0
}

# Set up signal handlers
trap cleanup_on_exit SIGINT SIGTERM

main "$@"
