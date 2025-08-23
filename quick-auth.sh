#!/bin/bash
# ====================================================
# This script configures gcloud authentication and project settings.
#
# 1. Checks for gcloud and existing authentication.
# 2. Prompts for a Project ID if not provided.
# 3. Sets the project for gcloud and Application Default Credentials.
#
# Usage:
#   ./quick-auth.sh [PROJECT_ID]
# ====================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
        echo -e "${YELLOW}⚠️ You are not logged into gcloud.${NC}"
        echo -e "${BLUE}Please log in with your Google account...${NC}"
        gcloud auth login
        gcloud auth application-default login
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

# --- Main execution ---
main() {
    echo -e "${BLUE}🚀 Starting User Authentication and Project Setup...${NC}"
    
    check_prerequisites
    
    get_project_config "$@"
    
    echo -e "${BLUE}🔧 Configuring gcloud project...${NC}"
    gcloud config set project "$PROJECT_ID"
    echo -e "${GREEN}✅ gcloud project set to '$PROJECT_ID'.${NC}"
    
    echo -e "${BLUE}🔧 Setting quota project for Application Default Credentials...${NC}"
    gcloud auth application-default set-quota-project "$PROJECT_ID"
    echo -e "${GREEN}✅ Quota project set to '$PROJECT_ID'.${NC}"
    
    echo -e "\n${GREEN}🎉 Authentication and project configuration complete!${NC}"
}

main "$@"
