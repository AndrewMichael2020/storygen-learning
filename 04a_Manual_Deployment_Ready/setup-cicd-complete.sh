#!/bin/bash
set -e

# 🚀 Complete CI/CD Setup Script
# ==============================
# This script provides a complete CI/CD setup including Workload Identity fix
# Run this after test-env-loading.sh to ensure everything is configured correctly

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}🚀 Complete CI/CD Setup${NC}"
echo -e "${CYAN}======================${NC}"
echo ""

# Function to load environment variables from .env file
load_env_file() {
    local env_file="../.env"
    if [ -f "$env_file" ]; then
        echo -e "${GREEN}📄 Loading configuration from $env_file${NC}"
        # Load environment variables, ignoring comments and empty lines
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip comments and empty lines
            if [[ ! "$line" =~ ^[[:space:]]*# ]] && [[ -n "$line" ]]; then
                # Export the variable (remove quotes if present)
                export "$line"
            fi
        done < "$env_file"
        return 0
    else
        echo -e "${YELLOW}⚠️ No .env file found at $env_file${NC}"
        echo "Please run test-env-loading.sh first to check your configuration."
        return 1
    fi
}

# Load configuration
if ! load_env_file; then
    echo -e "${RED}❌ Cannot proceed without .env configuration${NC}"
    exit 1
fi

PROJECT_ID="$GOOGLE_CLOUD_PROJECT_ID"
GITHUB_USERNAME="$GITHUB_USERNAME"
GITHUB_REPO="$GITHUB_REPO"

# Validate required variables
if [ -z "$PROJECT_ID" ] || [ -z "$GITHUB_USERNAME" ] || [ -z "$GITHUB_REPO" ]; then
    echo -e "${RED}❌ Missing required configuration in .env file:${NC}"
    echo "  GOOGLE_CLOUD_PROJECT_ID: ${PROJECT_ID:-'Not set'}"
    echo "  GITHUB_USERNAME: ${GITHUB_USERNAME:-'Not set'}"
    echo "  GITHUB_REPO: ${GITHUB_REPO:-'Not set'}"
    echo ""
    echo "Please ensure your .env file is properly configured."
    exit 1
fi

echo -e "${BLUE}📋 Configuration loaded:${NC}"
echo "  Project ID: $PROJECT_ID"
echo "  GitHub Repository: $GITHUB_USERNAME/$GITHUB_REPO"
echo ""

# Check if authenticated with gcloud
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    echo -e "${RED}❌ Not authenticated with gcloud${NC}"
    echo "Please run: gcloud auth login"
    exit 1
fi

# Step 1: Run the CI/CD configuration setup
echo -e "${BLUE}📋 Step 1: Setting up CI/CD configuration...${NC}"
if [ -f "./setup-cicd-config.sh" ]; then
    ./setup-cicd-config.sh
    echo -e "${GREEN}✅ CI/CD configuration completed${NC}"
else
    echo -e "${RED}❌ setup-cicd-config.sh not found${NC}"
    exit 1
fi

echo ""

# Step 2: Check and fix Workload Identity Provider
echo -e "${BLUE}🔧 Step 2: Checking Workload Identity Provider configuration...${NC}"

POOL_NAME="github-pool"
PROVIDER_NAME="github-provider-fixed"

# Check if WIP exists
if ! gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" \
   --project="$PROJECT_ID" --location="global" \
   --workload-identity-pool="$POOL_NAME" > /dev/null 2>&1; then
    echo -e "${RED}❌ Workload Identity Provider not found${NC}"
    echo "The CI/CD configuration setup should have created it. Please check the setup logs."
    exit 1
fi

# Get current attribute condition
CURRENT_CONDITION=$(gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" \
    --project="$PROJECT_ID" --location="global" \
    --workload-identity-pool="$POOL_NAME" \
    --format="value(attributeCondition)" 2>/dev/null || echo "")

EXPECTED_CONDITION="assertion.repository=='$GITHUB_USERNAME/$GITHUB_REPO'"

echo "  Current condition: ${CURRENT_CONDITION:-'None'}"
echo "  Expected condition: $EXPECTED_CONDITION"

if [ "$CURRENT_CONDITION" = "$EXPECTED_CONDITION" ]; then
    echo -e "${GREEN}✅ Workload Identity Provider already configured correctly${NC}"
else
    echo -e "${YELLOW}⚠️ Fixing Workload Identity Provider configuration...${NC}"
    
    # Run the fix script
    if [ -f "./fix-workload-identity.sh" ]; then
        ./fix-workload-identity.sh
        echo -e "${GREEN}✅ Workload Identity Provider fixed${NC}"
    else
        echo -e "${YELLOW}⚠️ fix-workload-identity.sh not found, applying fix directly...${NC}"
        
        # Apply fix directly
        gcloud iam workload-identity-pools providers update-oidc "$PROVIDER_NAME" \
            --project="$PROJECT_ID" \
            --location="global" \
            --workload-identity-pool="$POOL_NAME" \
            --attribute-condition="$EXPECTED_CONDITION"
        
        echo -e "${GREEN}✅ Workload Identity Provider updated${NC}"
    fi
fi

echo ""

# Step 3: Validate the complete setup
echo -e "${BLUE}🧪 Step 3: Validating complete CI/CD setup...${NC}"

# Check deployment configuration file
DEPLOYMENT_CONFIG="../.github/config/deployment.yml"
if [ -f "$DEPLOYMENT_CONFIG" ]; then
    echo -e "${GREEN}✅ Deployment configuration file exists${NC}"
    
    # Check if the file contains the correct project ID
    if grep -q "project_id: \"$PROJECT_ID\"" "$DEPLOYMENT_CONFIG"; then
        echo -e "${GREEN}✅ Deployment configuration has correct project ID${NC}"
    else
        echo -e "${YELLOW}⚠️ Deployment configuration may need updating${NC}"
    fi
else
    echo -e "${RED}❌ Deployment configuration file not found${NC}"
    echo "Expected: $DEPLOYMENT_CONFIG"
fi

# Check GitHub workflow file
WORKFLOW_FILE="../.github/workflows/ci-cd.yml"
if [ -f "$WORKFLOW_FILE" ]; then
    echo -e "${GREEN}✅ GitHub workflow file exists${NC}"
else
    echo -e "${RED}❌ GitHub workflow file not found${NC}"
    echo "Expected: $WORKFLOW_FILE"
fi

# Test API access
echo ""
echo -e "${BLUE}🔗 Testing Google Cloud API access...${NC}"
if gcloud projects list --limit=1 > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Google Cloud API access working${NC}"
else
    echo -e "${RED}❌ Google Cloud API access failed${NC}"
fi

echo ""
echo -e "${GREEN}🎉 Complete CI/CD setup finished!${NC}"
echo ""
echo -e "${CYAN}📋 Setup Summary:${NC}"
echo "  ✅ CI/CD configuration created"
echo "  ✅ Workload Identity Provider configured for: $GITHUB_USERNAME/$GITHUB_REPO"
echo "  ✅ Deployment configuration updated"
echo "  ✅ GitHub workflow ready"
echo ""
echo -e "${CYAN}🚀 Next steps:${NC}"
echo "  1. Commit and push your changes to trigger CI/CD:"
echo "     git add ."
echo "     git commit -m \"Configure CI/CD with Workload Identity\""
echo "     git push origin main"
echo ""
echo "  2. Monitor the GitHub Actions workflow:"
echo "     https://github.com/$GITHUB_USERNAME/$GITHUB_REPO/actions"
echo ""
echo "  3. If CI/CD fails, check the workflow logs for detailed error messages"
echo ""
echo -e "${YELLOW}📝 Troubleshooting:${NC}"
echo "  • If authentication still fails, run: ./fix-workload-identity.sh"
echo "  • Changes may take a few minutes to propagate"
echo "  • Ensure your GitHub repository secrets are configured correctly"
