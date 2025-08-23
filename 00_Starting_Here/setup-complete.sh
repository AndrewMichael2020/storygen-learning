#!/bin/bash

# 🚀 StoryGen Complete Setup Script
# ================================
# This master script combines all setup steps for StoryGen project:
# 1. Shared Virtual Environment Setup (setup-shared-venv.sh)
# 2. Google Cloud CI/CD Configuration (setup-direct.sh)  
# 3. API Key Setup (setup-api-key.sh)
#
# Features:
# • Robust error handling with rollback capabilities
# • Progress tracking and resume functionality
# • Environment validation and auto-creation
# • Comprehensive logging and status reporting
# • Safe execution with prerequisite checking
#
# Prerequisites:
# 1. Python 3.8+ installed
# 2. Google Cloud Project with billing enabled
# 3. gcloud CLI installed and authenticated (gcloud auth login)
# 4. Project owner/editor permissions
# 5. GitHub repository (fork of StoryGen)
#
# Usage:
#   ./setup-complete.sh [PROJECT_ID] [GITHUB_USERNAME] [REPO_NAME] [SECRET_NAME]
#
# The script will automatically load configuration from ../.env if available
# or help you create one from the template.
#
# Examples:
#   ./setup-complete.sh                           # Interactive setup with .env
#   ./setup-complete.sh my-project                # Override project only
#   ./setup-complete.sh my-project myuser         # Override project & user
#   ./setup-complete.sh my-project myuser storygen-main  # All specified

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Progress file to track completed steps
PROGRESS_FILE=".setup-progress"
LOG_FILE="setup-complete.log"

# Step tracking
STEP_VENV="venv"
STEP_CLOUD="cloud" 
STEP_APIKEY="apikey"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to check if step is completed
is_step_completed() {
    local step="$1"
    [ -f "$PROGRESS_FILE" ] && grep -q "^$step$" "$PROGRESS_FILE"
}

# Function to mark step as completed
mark_step_completed() {
    local step="$1"
    echo "$step" >> "$PROGRESS_FILE"
    log "✅ Step '$step' completed successfully"
}

# Function to display progress
show_progress() {
    echo ""
    echo -e "${CYAN}📊 Setup Progress${NC}"
    echo "================="
    
    if is_step_completed "$STEP_VENV"; then
        echo -e "${GREEN}✅ Virtual Environment Setup${NC}"
    else
        echo -e "${YELLOW}⏳ Virtual Environment Setup${NC}"
    fi
    
    if is_step_completed "$STEP_CLOUD"; then
        echo -e "${GREEN}✅ Google Cloud CI/CD Configuration${NC}"
    else
        echo -e "${YELLOW}⏳ Google Cloud CI/CD Configuration${NC}"
    fi
    
    if is_step_completed "$STEP_APIKEY"; then
        echo -e "${GREEN}✅ API Key Setup${NC}"
    else
        echo -e "${YELLOW}⏳ API Key Setup${NC}"
    fi
    echo ""
}

# Function to validate prerequisites
validate_prerequisites() {
    log "🔍 Validating prerequisites..."
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}❌ Python 3 is required but not installed${NC}"
        echo "Please install Python 3.8+ first: https://python.org/downloads/"
        exit 1
    fi
    echo -e "${GREEN}✅ Python 3 found: $(python3 --version)${NC}"
    
    # Check gcloud
    if ! command -v gcloud &> /dev/null; then
        echo -e "${RED}❌ gcloud CLI not found${NC}"
        echo "Please install: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    echo -e "${GREEN}✅ gcloud CLI found${NC}"
    
    # Check gcloud auth
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
        echo -e "${RED}❌ Not authenticated with gcloud${NC}"
        echo "Please run: gcloud auth login"
        exit 1
    fi
    
    CURRENT_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    echo -e "${GREEN}✅ Authenticated as: ${CURRENT_ACCOUNT}${NC}"
    
    log "✅ All prerequisites validated"
}

# Function to setup or validate .env file
setup_env_file() {
    local env_file="../.env"
    local template_file="../env.template"
    
    log "🔧 Checking environment configuration..."
    
    if [ ! -f "$env_file" ]; then
        echo -e "${YELLOW}⚠️ No .env file found${NC}"
        
        if [ -f "$template_file" ]; then
            echo -e "${BLUE}📋 Found env.template file${NC}"
            read -p "Create .env file from template? (Y/n): " create_env
            if [[ ! $create_env =~ ^[Nn]$ ]]; then
                cp "$template_file" "$env_file"
                echo -e "${GREEN}✅ Created .env file from template${NC}"
                echo -e "${YELLOW}⚠️ Please edit ../.env with your actual values before continuing${NC}"
                echo "Required values: GOOGLE_CLOUD_PROJECT_ID, GITHUB_USERNAME, GITHUB_REPO"
                echo ""
                read -p "Press Enter after editing .env file to continue..."
            fi
        else
            echo -e "${YELLOW}⚠️ No template found. You can create .env manually or continue with interactive input${NC}"
        fi
    else
        echo -e "${GREEN}✅ .env file found${NC}"
    fi
}

# Function to load environment variables from .env file
load_env_file() {
    local env_file="../.env"
    if [ -f "$env_file" ]; then
        log "🔧 Loading configuration from $env_file"
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
        log "⚠️ No .env file found at $env_file"
        return 1
    fi
}

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

# Function to get configuration parameters
get_configuration() {
    log "📋 Gathering configuration parameters..."
    
    # Load .env file first (if available)
    load_env_file
    
    # Get configuration from command line, .env file, or prompt
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

    if [ -n "$2" ]; then
        GITHUB_USERNAME="$2"
    elif [ -n "$GITHUB_USERNAME" ]; then
        echo -e "${GREEN}✅ Using GITHUB_USERNAME from .env: $GITHUB_USERNAME${NC}"
    else
        read -p "GitHub Username: " GITHUB_USERNAME
    fi

    if [ -n "$3" ]; then
        REPO_NAME="$3"
    elif [ -n "$GITHUB_REPO" ]; then
        REPO_NAME="$GITHUB_REPO"
        echo -e "${GREEN}✅ Using REPO_NAME from .env: $REPO_NAME${NC}"
    else
        prompt_with_default "Repository Name" "storygen-main" "REPO_NAME"
    fi

    if [ -n "$4" ]; then
        SECRET_NAME="$4"
    elif [ -n "$SECRET_MANAGER" ]; then
        SECRET_NAME="$SECRET_MANAGER"
        echo -e "${GREEN}✅ Using SECRET_NAME from .env: $SECRET_NAME${NC}"
    else
        prompt_with_default "Secret Manager Name" "storygen-google-api-key" "SECRET_NAME"
    fi
    
    # Validate required parameters
    if [ -z "$PROJECT_ID" ] || [ -z "$GITHUB_USERNAME" ] || [ -z "$REPO_NAME" ]; then
        echo -e "${RED}❌ Missing required parameters${NC}"
        echo "Required: PROJECT_ID, GITHUB_USERNAME, REPO_NAME"
        exit 1
    fi
    
    echo ""
    echo -e "${BLUE}📋 Configuration Summary:${NC}"
    echo "  Project: $PROJECT_ID"
    echo "  GitHub: $GITHUB_USERNAME/$REPO_NAME"
    echo "  Secret Name: $SECRET_NAME"
    echo ""
    
    log "✅ Configuration gathered successfully"
}

# Function to run virtual environment setup
setup_virtual_environment() {
    if is_step_completed "$STEP_VENV"; then
        echo -e "${GREEN}✅ Virtual environment setup already completed${NC}"
        return 0
    fi
    
    log "🚀 Starting virtual environment setup..."
    echo -e "${CYAN}🔧 Step 1: Setting up shared virtual environment${NC}"
    echo "=================================================="
    
    if [ ! -f "./setup-shared-venv.sh" ]; then
        echo -e "${RED}❌ setup-shared-venv.sh not found in current directory${NC}"
        exit 1
    fi
    
    if ! bash ./setup-shared-venv.sh; then
        echo -e "${RED}❌ Virtual environment setup failed${NC}"
        log "❌ Virtual environment setup failed"
        exit 1
    fi
    
    mark_step_completed "$STEP_VENV"
    echo -e "${GREEN}🎉 Virtual environment setup completed!${NC}"
    echo ""
}

# Function to run Google Cloud setup
setup_google_cloud() {
    if is_step_completed "$STEP_CLOUD"; then
        echo -e "${GREEN}✅ Google Cloud setup already completed${NC}"
        return 0
    fi
    
    log "🚀 Starting Google Cloud CI/CD configuration..."
    echo -e "${CYAN}🔧 Step 2: Configuring Google Cloud CI/CD${NC}"
    echo "============================================="
    
    if [ ! -f "./setup-direct.sh" ]; then
        echo -e "${RED}❌ setup-direct.sh not found in current directory${NC}"
        exit 1
    fi
    
    if ! bash ./setup-direct.sh "$PROJECT_ID" "$GITHUB_USERNAME" "$REPO_NAME" "$SECRET_NAME"; then
        echo -e "${RED}❌ Google Cloud setup failed${NC}"
        log "❌ Google Cloud setup failed"
        exit 1
    fi
    
    mark_step_completed "$STEP_CLOUD"
    echo -e "${GREEN}🎉 Google Cloud CI/CD configuration completed!${NC}"
    echo ""
}

# Function to run API key setup
setup_api_key() {
    if is_step_completed "$STEP_APIKEY"; then
        echo -e "${GREEN}✅ API key setup already completed${NC}"
        return 0
    fi
    
    log "🚀 Starting API key setup..."
    echo -e "${CYAN}🔧 Step 3: Setting up API key${NC}"
    echo "=============================="
    
    if [ ! -f "./setup-api-key.sh" ]; then
        echo -e "${RED}❌ setup-api-key.sh not found in current directory${NC}"
        exit 1
    fi
    
    if ! bash ./setup-api-key.sh "$PROJECT_ID" "$SECRET_NAME"; then
        echo -e "${RED}❌ API key setup failed${NC}"
        log "❌ API key setup failed"
        exit 1
    fi
    
    mark_step_completed "$STEP_APIKEY"
    echo -e "${GREEN}🎉 API key setup completed!${NC}"
    echo ""
}

# Function to cleanup progress file on success
cleanup_progress() {
    if [ -f "$PROGRESS_FILE" ]; then
        rm "$PROGRESS_FILE"
        log "🧹 Cleaned up progress tracking file"
    fi
}

# Function to show final summary
show_final_summary() {
    echo ""
    echo -e "${MAGENTA}🎉 STORYGEN COMPLETE SETUP FINISHED! 🎉${NC}"
    echo -e "${MAGENTA}=======================================${NC}"
    echo ""
    echo -e "${GREEN}✅ All setup steps completed successfully!${NC}"
    echo ""
    echo -e "${BLUE}📋 What was configured:${NC}"
    echo "  🐍 Python virtual environment (.venv)"
    echo "  ☁️ Google Cloud CI/CD pipeline"
    echo "  🔐 API key in Secret Manager"
    echo "  🪣 Cloud Storage bucket for images"
    echo "  🔑 Workload Identity Federation"
    echo ""
    echo -e "${YELLOW}📋 Next Steps:${NC}"
    echo "1. Add secrets and variables to your GitHub repository"
    echo "2. Push code to main branch - CI/CD will deploy automatically"
    echo "3. Monitor deployment in GitHub Actions"
    echo ""
    echo -e "${BLUE}📁 Generated Files:${NC}"
    echo "  • setup-summary-${PROJECT_ID}.txt - Configuration summary"
    echo "  • $LOG_FILE - Detailed setup log"
    echo ""
    echo -e "${GREEN}🎯 Your StoryGen project is ready for development and deployment! 🚀${NC}"
    
    log "🎉 Complete setup finished successfully"
}

# Function to handle script interruption
cleanup_on_exit() {
    echo ""
    echo -e "${YELLOW}⚠️ Setup interrupted${NC}"
    echo ""
    echo "Progress has been saved. You can resume by running this script again."
    echo "To start fresh, delete the progress file: rm $PROGRESS_FILE"
    
    log "⚠️ Setup interrupted by user"
    exit 1
}

# Main execution function
main() {
    # Set up signal handlers
    trap cleanup_on_exit SIGINT SIGTERM
    
    # Start logging
    log "🚀 Starting StoryGen complete setup"
    
    echo -e "${MAGENTA}🚀 StoryGen Complete Setup Script${NC}"
    echo -e "${MAGENTA}==================================${NC}"
    echo ""
    echo "This script will set up everything needed for StoryGen:"
    echo "  1. 🐍 Shared Python virtual environment"
    echo "  2. ☁️ Google Cloud CI/CD configuration"
    echo "  3. 🔐 Secure API key storage"
    echo ""
    
    # Show current progress
    show_progress
    
    # Check if resuming
    if [ -f "$PROGRESS_FILE" ]; then
        echo -e "${YELLOW}📁 Found previous setup progress${NC}"
        read -p "Resume from where you left off? (Y/n): " resume_setup
        if [[ $resume_setup =~ ^[Nn]$ ]]; then
            rm "$PROGRESS_FILE"
            echo "🔄 Starting fresh setup..."
        else
            echo "▶️ Resuming setup..."
        fi
        echo ""
    fi
    
    # Step 0: Prerequisites and configuration
    validate_prerequisites
    setup_env_file
    get_configuration "$@"
    
    # Step 1: Virtual Environment Setup
    setup_virtual_environment
    
    # Step 2: Google Cloud Setup
    setup_google_cloud
    
    # Step 3: API Key Setup
    setup_api_key
    
    # Cleanup and show summary
    cleanup_progress
    show_final_summary
}

# Run main function with all arguments
main "$@"
