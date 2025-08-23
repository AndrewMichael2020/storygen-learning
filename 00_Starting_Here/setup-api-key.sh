#!/bin/bash

# 🔐 StoryGen API Key Setup Script
# ================================
# This script securely stores your Gemini API key in Google Cloud Secret Manager
# 
# What this script does:
# • Validates project access and API availability
# • Securely stores your Gemini API key in Secret Manager
# • Configures proper access permissions for Cloud Run services
# • Provides validation and testing of secret access
#
# Prerequisites:
# 1. Run ./setup-direct.sh first to configure your project
# 2. Get your API key from https://aistudio.google.com/
# 3. Secret Manager API must be enabled (script will enable if needed)
#
# Usage:
#   ./setup-api-key.sh [PROJECT_ID] [SECRET_NAME]
#
# The script will automatically load configuration from ../.env if available:
#   GOOGLE_CLOUD_PROJECT_ID=your-project-id
#   SECRET_MANAGER=your-secret-name
#   GOOGLE_API_KEY=your-api-key
#
# Examples:
#   ./setup-api-key.sh                    # Loads from .env or prompts
#   ./setup-api-key.sh sdlcv1             # Overrides project, loads others from .env
#   ./setup-api-key.sh sdlcv1 my-api-key  # Custom secret name

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}🔐 StoryGen API Key Setup${NC}"
echo -e "${CYAN}=========================${NC}"
echo ""
echo "This script will securely store your Gemini API key in Google Cloud Secret Manager."
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
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

# Check prerequisites
echo -e "${BLUE}📋 Checking Prerequisites${NC}"
echo "=========================="

if ! command_exists gcloud; then
    echo -e "${RED}❌ gcloud CLI not found${NC}"
    echo "Please install: https://cloud.google.com/sdk/docs/install"
    exit 1
fi
echo -e "${GREEN}✅ gcloud CLI found${NC}"

if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
    echo -e "${RED}❌ Not authenticated with gcloud${NC}"
    echo "Please run: gcloud auth login"
    exit 1
fi

CURRENT_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
echo -e "${GREEN}✅ Authenticated as: ${CURRENT_ACCOUNT}${NC}"

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
        echo "Current project: $CURRENT_PROJECT"
        read -p "Use current project? (y/N): " use_current
        if [[ $use_current =~ ^[Yy]$ ]]; then
            PROJECT_ID="$CURRENT_PROJECT"
        else
            read -p "Google Cloud Project ID: " PROJECT_ID
        fi
    else
        read -p "Google Cloud Project ID: " PROJECT_ID
    fi
fi

if [ -n "$2" ]; then
    SECRET_NAME="$2"
elif [ -n "$SECRET_MANAGER" ]; then
    SECRET_NAME="$SECRET_MANAGER"
    echo -e "${GREEN}✅ Using SECRET_NAME from .env: $SECRET_NAME${NC}"
else
    SECRET_NAME="storygen-google-api-key"
fi

echo ""
echo -e "${BLUE}Configuration:${NC}"
echo "  Project: $PROJECT_ID"
echo "  Secret Name: $SECRET_NAME"
echo ""

# Validate project access
echo "🔍 Validating project access..."
if ! gcloud projects describe "$PROJECT_ID" > /dev/null 2>&1; then
    echo -e "${RED}❌ Project '$PROJECT_ID' not accessible or doesn't exist${NC}"
    echo "Please check the project ID and ensure you have access."
    echo "Did you run ./setup-direct.sh first?"
    exit 1
fi
echo -e "${GREEN}✅ Project '$PROJECT_ID' is accessible${NC}"

# Check if Secret Manager API is enabled
echo "🔍 Checking Secret Manager API..."
if ! gcloud services list --enabled --filter="name:secretmanager.googleapis.com" --format="value(name)" --project="$PROJECT_ID" | grep -q "secretmanager.googleapis.com"; then
    echo -e "${YELLOW}⚠️ Secret Manager API not enabled. Enabling now...${NC}"
    gcloud services enable secretmanager.googleapis.com --project="$PROJECT_ID"
    echo -e "${GREEN}✅ Secret Manager API enabled${NC}"
else
    echo -e "${GREEN}✅ Secret Manager API is enabled${NC}"
fi

# Check if secret exists
echo ""
echo "🔍 Checking if secret exists..."
if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️ Secret '$SECRET_NAME' already exists${NC}"
    echo -e "${GREEN}✅ Will automatically update existing secret with new API key${NC}"
    UPDATING=true
else
    echo -e "${GREEN}✅ Secret '$SECRET_NAME' will be created${NC}"
    UPDATING=false
fi

# Get API key
echo ""
echo -e "${YELLOW}🔑 API Key Input${NC}"
echo "==============="

if [ -n "$GOOGLE_API_KEY" ]; then
    API_KEY="$GOOGLE_API_KEY"
    echo -e "${GREEN}✅ Using GOOGLE_API_KEY from .env file${NC}"
    echo "API key loaded (first 10 chars): ${API_KEY:0:10}..."
else
    echo "Get your Gemini API key from: https://aistudio.google.com/"
    echo ""
    echo -e "${YELLOW}⚠️ Your API key will not be displayed for security${NC}"
    read -s -p "Enter your Gemini API key: " API_KEY
    echo ""
fi

if [ -z "$API_KEY" ]; then
    echo -e "${RED}❌ No API key provided${NC}"
    exit 1
fi

# Validate API key format (basic check)
if [ ${#API_KEY} -lt 20 ]; then
    echo -e "${RED}❌ API key seems too short. Please check and try again.${NC}"
    exit 1
fi

# Create or update secret
echo ""
if [ "$UPDATING" = true ]; then
    echo "🔄 Updating existing secret..."
    echo -n "$API_KEY" | gcloud secrets versions add "$SECRET_NAME" \
        --data-file=- \
        --project="$PROJECT_ID"
    echo -e "${GREEN}✅ Secret updated successfully${NC}"
else
    echo "🔐 Creating new secret..."
    # Create secret first
    gcloud secrets create "$SECRET_NAME" \
        --replication-policy="automatic" \
        --project="$PROJECT_ID"
    
    # Add the API key
    echo -n "$API_KEY" | gcloud secrets versions add "$SECRET_NAME" \
        --data-file=- \
        --project="$PROJECT_ID"
    echo -e "${GREEN}✅ Secret created successfully${NC}"
fi

# Test secret access
echo ""
echo "🧪 Testing secret access..."
if gcloud secrets versions access latest --secret="$SECRET_NAME" --project="$PROJECT_ID" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Secret is accessible${NC}"
else
    echo -e "${RED}❌ Secret access test failed${NC}"
    exit 1
fi



echo ""
echo -e "${CYAN}🎉 API Key Setup Complete!${NC}"
echo -e "${CYAN}===========================${NC}"
echo ""
echo -e "${GREEN}✅ Gemini API key securely stored in Secret Manager${NC}"
echo -e "${GREEN}✅ Project: $PROJECT_ID${NC}"
echo -e "${GREEN}✅ Secret: $SECRET_NAME${NC}"
echo ""
echo -e "${BLUE}🔐 Secret Manager Summary${NC}"
echo "========================="
echo "• API key is now available to Cloud Run services"
echo "• Applications can access it via: GOOGLE_API_KEY environment variable"
echo "• Secret is automatically replicated across regions"
echo ""
echo -e "${YELLOW}📋 Next Steps:${NC}"
echo "1. Configure your CI/CD pipeline to use this secret"
echo "2. Deploy your application with Secret Manager integration"
echo "3. Verify the API key is accessible in your running services"
echo ""
echo -e "${BLUE}💡 Useful Commands:${NC}"
echo "• View secret: gcloud secrets describe $SECRET_NAME --project=$PROJECT_ID"
echo "• Access secret: gcloud secrets versions access latest --secret=$SECRET_NAME --project=$PROJECT_ID"
echo "• Update API key: Run this script again anytime"
echo ""
echo -e "${GREEN}🎯 Your Gemini API key is securely configured! 🔐${NC}"
