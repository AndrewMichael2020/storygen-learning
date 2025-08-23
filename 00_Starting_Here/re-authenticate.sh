#!/bin/bash

# 🔐 StoryGen Re-Authentication Script
# ====================================
# This script handles re-authentication with Google Cloud for existing StoryGen setups
# Use this when you need to re-authenticate or switch accounts/projects
#
# Prerequisites:
# 1. gcloud CLI installed
# 2. Valid Google Cloud Project (configured previously)
#
# Usage:
#   ./re-authenticate.sh [PROJECT_ID]
#
# The script will automatically load configuration from ../.env if available:
#   GOOGLE_CLOUD_PROJECT_ID=your-project-id
#
# Examples:
#   ./re-authenticate.sh                    # Loads from .env or prompts
#   ./re-authenticate.sh my-project-id      # Use specific project

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

echo -e "${CYAN}🔐 StoryGen Re-Authentication${NC}"
echo -e "${CYAN}=============================${NC}"
echo ""

# Load .env file first (if available)
load_env_file

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

# Check current authentication status
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
echo -e "${GREEN}🎉 Re-Authentication Complete!${NC}"
echo -e "${GREEN}===============================${NC}"
echo ""
echo -e "${GREEN}✅ Authenticated as: ${CURRENT_ACCOUNT}${NC}"
echo -e "${GREEN}✅ Active project: ${PROJECT_ID}${NC}"
echo -e "${GREEN}✅ Application default credentials: Ready${NC}"
echo ""
echo -e "${BLUE}🚀 You can now run other StoryGen scripts or deploy your application!${NC}"
echo ""

# Optional: Show useful next steps
echo -e "${CYAN}💡 Next Steps:${NC}"
echo "• Run setup scripts if this is a new project"
echo "• Deploy your application with existing CI/CD pipeline"
echo "• Test your authentication with: gcloud auth list"
echo "• Check your project with: gcloud config get-value project"
echo ""
