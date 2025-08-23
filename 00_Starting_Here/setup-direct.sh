#!/bin/bash

# 🔐 StoryGen Complete CI/CD Setup Script
# =======================================
# This script configures everything needed for GitHub Actions CI/CD with Google Cloud:
# • Workload Identity Federation (secure keyless authentication)  
# • Service Account with comprehensive permissions (Vertex AI, Cloud Run, Storage, etc.)
# • Cloud Storage bucket for Imagen-generated images
# • Secret Manager for secure API key storage
# • All required Google Cloud APIs
#
# Prerequisites:
# 1. Google Cloud Project with billing enabled
# 2. gcloud CLI installed and authenticated (gcloud auth login)
# 3. Project owner/editor permissions
# 4. GitHub repository (fork of StoryGen)
#
# Usage:
#   ./setup-direct.sh [PROJECT_ID] [GITHUB_USERNAME] [REPO_NAME] [SECRET_NAME]
#
# The script will automatically load configuration from ../.env if available:
#   GOOGLE_CLOUD_PROJECT_ID=your-project-id
#   GITHUB_USERNAME=your-username  
#   GITHUB_REPO=your-repo-name
#   SECRET_MANAGER=your-secret-name
#   GENMEDIA_BUCKET=your-bucket-name
#
# Examples:
#   ./setup-direct.sh                           # Loads from .env or prompts
#   ./setup-direct.sh my-project                # Overrides project, loads others from .env
#   ./setup-direct.sh my-project myuser         # Overrides project & user
#   ./setup-direct.sh my-project myuser storygen-main  # All specified
#   ./setup-direct.sh my-project myuser storygen-main my-custom-secret  # Custom secret name
#
# After running this script:
# 1. Copy the provided secrets/variables to your GitHub repository
# 2. Get your Gemini API key from https://aistudio.google.com/
# 3. Add API key to both Secret Manager and GitHub
# 4. Push to main branch - CI/CD will deploy automatically!

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

# Configuration
REGION="us-central1"
SERVICE_ACCOUNT_NAME="github-actions"
POOL_NAME="github-pool"
PROVIDER_NAME="github-provider-fixed"
BUCKET_SUFFIX="story-images"

echo -e "${CYAN}🔐 StoryGen Complete CI/CD Setup${NC}"
echo -e "${CYAN}=================================${NC}"
echo ""
echo -e "${BLUE}Configuration:${NC}"
echo "  Project: $PROJECT_ID"
echo "  GitHub: $GITHUB_USERNAME/$REPO_NAME"
echo "  Region: $REGION"
echo "  Secret Name: $SECRET_NAME"
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

if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
    echo -e "${RED}❌ Not authenticated with gcloud${NC}"
    echo "Please run: gcloud auth login"
    exit 1
fi

CURRENT_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
echo -e "${GREEN}✅ Authenticated as: ${CURRENT_ACCOUNT}${NC}"

# Validate project access
echo "🔍 Validating project access..."
if ! gcloud projects describe "$PROJECT_ID" > /dev/null 2>&1; then
    echo -e "${RED}❌ Project '$PROJECT_ID' not accessible or doesn't exist${NC}"
    echo "Please check the project ID and ensure you have access."
    exit 1
fi
echo -e "${GREEN}✅ Project '$PROJECT_ID' is accessible${NC}"
echo ""

# Set project
echo "🔧 Setting project..."
gcloud config set project "$PROJECT_ID"

# Enable APIs
echo "🔧 Enabling APIs..."
gcloud services enable \
    iamcredentials.googleapis.com \
    iam.googleapis.com \
    cloudresourcemanager.googleapis.com \
    serviceusage.googleapis.com \
    run.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    aiplatform.googleapis.com \
    generativelanguage.googleapis.com \
    storage.googleapis.com \
    secretmanager.googleapis.com \
    --project="$PROJECT_ID"

# Get project number
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
echo "✅ Project number: $PROJECT_NUMBER"

# Create Workload Identity Pool
echo "🏗️ Creating Workload Identity Pool..."
if ! gcloud iam workload-identity-pools describe "$POOL_NAME" \
   --project="$PROJECT_ID" --location="global" > /dev/null 2>&1; then
    gcloud iam workload-identity-pools create "$POOL_NAME" \
        --project="$PROJECT_ID" \
        --location="global" \
        --display-name="GitHub Actions Pool"
    echo "✅ Pool created"
else
    echo "✅ Pool already exists"
fi

# Create Workload Identity Provider
echo "🏗️ Creating Workload Identity Provider..."
if ! gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" \
   --project="$PROJECT_ID" --location="global" \
   --workload-identity-pool="$POOL_NAME" > /dev/null 2>&1; then
    gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_NAME" \
        --project="$PROJECT_ID" \
        --location="global" \
        --workload-identity-pool="$POOL_NAME" \
        --display-name="GitHub Actions Provider" \
        --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
        --issuer-uri="https://token.actions.githubusercontent.com" \
        --attribute-condition="assertion.repository=='$GITHUB_USERNAME/$REPO_NAME'"
    echo "✅ Provider created"
else
    echo "✅ Provider already exists"
fi

# Create service account
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
echo "🏗️ Creating service account..."
if ! gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" \
   --project="$PROJECT_ID" > /dev/null 2>&1; then
    gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
        --project="$PROJECT_ID" \
        --display-name="GitHub Actions Service Account"
    echo "✅ Service account created"
else
    echo "✅ Service account already exists"
fi

# Grant IAM roles
echo "🔐 Granting IAM roles..."
ROLES=(
    "roles/run.admin"
    "roles/cloudbuild.builds.editor"
    "roles/artifactregistry.admin"
    "roles/serviceusage.serviceUsageAdmin"
    "roles/serviceusage.serviceUsageConsumer"
    "roles/storage.admin"
    "roles/secretmanager.admin"
    "roles/aiplatform.admin"
    "roles/aiplatform.user"
    "roles/ml.admin"
    "roles/editor"
)

for role in "${ROLES[@]}"; do
    echo "  🔧 Granting $role..."
    if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
        --role="$role" > /dev/null 2>&1; then
        echo -e "    ${GREEN}✅ $role granted${NC}"
    else
        echo -e "    ${YELLOW}⚠️ Failed to grant $role (may already exist or not needed)${NC}"
    fi
done

# Configure GitHub access
echo "🔗 Configuring GitHub repository access..."
PRINCIPAL="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL_NAME/attribute.repository/$GITHUB_USERNAME/$REPO_NAME"

gcloud iam service-accounts add-iam-policy-binding "$SERVICE_ACCOUNT_EMAIL" \
    --project="$PROJECT_ID" \
    --role="roles/iam.workloadIdentityUser" \
    --member="$PRINCIPAL"

# Create bucket
echo "🪣 Creating storage bucket..."
if [ -n "$GENMEDIA_BUCKET" ]; then
    BUCKET_NAME="$GENMEDIA_BUCKET"
    echo -e "${GREEN}✅ Using BUCKET_NAME from .env: $BUCKET_NAME${NC}"
else
    BUCKET_NAME="${PROJECT_ID}-${BUCKET_SUFFIX}"
fi
if ! gsutil ls -b gs://"$BUCKET_NAME" > /dev/null 2>&1; then
    gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" gs://"$BUCKET_NAME"
    gsutil iam ch serviceAccount:"$SERVICE_ACCOUNT_EMAIL":objectAdmin gs://"$BUCKET_NAME"
    echo "✅ Bucket created: $BUCKET_NAME"
else
    echo "✅ Bucket already exists: $BUCKET_NAME"
fi

# Create secret
echo "🔐 Creating secret..."
if ! gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" > /dev/null 2>&1; then
    gcloud secrets create "$SECRET_NAME" \
        --replication-policy="automatic" \
        --project="$PROJECT_ID"
    echo "✅ Secret created: $SECRET_NAME"
else
    echo "✅ Secret already exists: $SECRET_NAME"
fi

# Grant Cloud Run default service account access to secrets
echo "🔑 Granting secret access to Cloud Run service account..."
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$COMPUTE_SA" \
    --role="roles/secretmanager.secretAccessor"
echo "✅ Cloud Run service account can access secrets"

# Grant secret access
gcloud secrets add-iam-policy-binding "$SECRET_NAME" \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/secretmanager.secretAccessor" \
    --project="$PROJECT_ID" > /dev/null

echo ""
echo -e "${CYAN}🎉 Complete Setup Finished!${NC}"
echo -e "${CYAN}============================${NC}"
echo ""
echo -e "${GREEN}✅ All resources created successfully!${NC}"
echo -e "${GREEN}✅ Workload Identity Pool: $POOL_NAME${NC}"
echo -e "${GREEN}✅ Workload Identity Provider: $PROVIDER_NAME${NC}"  
echo -e "${GREEN}✅ Service Account: $SERVICE_ACCOUNT_EMAIL${NC}"
echo -e "${GREEN}✅ Storage Bucket: $BUCKET_NAME${NC}"
echo -e "${GREEN}✅ Secret Manager: $SECRET_NAME${NC}"
echo -e "${GREEN}✅ All required APIs enabled (Vertex AI, Gemini, Cloud Run, etc.)${NC}"
echo ""

WORKLOAD_IDENTITY_PROVIDER="projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL_NAME/providers/$PROVIDER_NAME"

echo -e "${YELLOW}🔑 GitHub Repository Configuration${NC}"
echo "=================================="
echo ""
echo -e "${BLUE}📋 Step 1: Add Repository Secrets${NC}"
echo "Go to: https://github.com/$GITHUB_USERNAME/$REPO_NAME/settings/secrets/actions"
echo ""
echo -e "${CYAN}WORKLOAD_IDENTITY_PROVIDER:${NC}"
echo "$WORKLOAD_IDENTITY_PROVIDER"
echo ""
echo -e "${CYAN}GCP_SERVICE_ACCOUNT_EMAIL:${NC}"
echo "$SERVICE_ACCOUNT_EMAIL"
echo ""
echo -e "${CYAN}GOOGLE_API_KEY:${NC}"
echo "(Get from https://aistudio.google.com/)"
echo ""

echo -e "${BLUE}📊 Step 2: Add Repository Variables${NC}"
echo "Go to: https://github.com/$GITHUB_USERNAME/$REPO_NAME/settings/variables/actions"
echo ""
echo -e "${CYAN}GCP_PROJECT_ID:${NC} $PROJECT_ID"
echo -e "${CYAN}GCP_REGION:${NC} $REGION"
echo -e "${CYAN}ARTIFACT_REPO:${NC} storygen-repo"
echo -e "${CYAN}BACKEND_SERVICE_NAME:${NC} genai-backend"
echo -e "${CYAN}FRONTEND_SERVICE_NAME:${NC} genai-frontend"
echo -e "${CYAN}BUCKET_NAME:${NC} $BUCKET_NAME"
echo -e "${CYAN}SECRET_NAME:${NC} $SECRET_NAME"
echo ""

echo -e "${BLUE}🚀 Step 3: Next Steps${NC}"
echo "1. Run the API key setup script:"
echo -e "   ${YELLOW}./setup-api-key.sh $PROJECT_ID $SECRET_NAME${NC}"
echo "2. Push to main branch to trigger automatic deployment"
echo "3. Monitor deployment in GitHub Actions"
echo ""
echo -e "${CYAN}📝 Alternative manual approach:${NC}"
echo "• Get your Gemini API key from: https://aistudio.google.com/"
echo "• Add API key to Secret Manager manually:"
echo -e "   ${YELLOW}echo 'YOUR_API_KEY' | gcloud secrets versions add $SECRET_NAME --data-file=- --project=$PROJECT_ID${NC}"
echo ""

echo -e "${GREEN}🔗 Integration Summary:${NC}"
echo "• Backend connects to bucket via GENMEDIA_BUCKET environment variable"
echo "• Imagen images automatically stored in: gs://$BUCKET_NAME"
echo "• Frontend displays images from GCS URLs with base64 fallback"
echo "• Secure keyless authentication via Workload Identity Federation"
echo ""

echo -e "${YELLOW}📋 Quick Test:${NC}"
echo "Run this command to verify your setup:"
echo -e "${YELLOW}./validate-workload-identity.sh${NC}"
echo ""

echo -e "${GREEN}🎯 Your CI/CD pipeline should now work! 🚀${NC}"
echo ""

# Create a summary file for reference
SUMMARY_FILE="setup-summary-${PROJECT_ID}.txt"
cat > "$SUMMARY_FILE" << EOF
# StoryGen CI/CD Setup Summary for Project: $PROJECT_ID
# Generated on $(date)

## Resources Created
- Workload Identity Pool: $POOL_NAME
- Workload Identity Provider: $PROVIDER_NAME
- Service Account: $SERVICE_ACCOUNT_EMAIL  
- Storage Bucket: $BUCKET_NAME
- Secret Manager: $SECRET_NAME

## GitHub Repository Secrets
Add at: https://github.com/$GITHUB_USERNAME/$REPO_NAME/settings/secrets/actions

WORKLOAD_IDENTITY_PROVIDER:
$WORKLOAD_IDENTITY_PROVIDER

GCP_SERVICE_ACCOUNT_EMAIL:
$SERVICE_ACCOUNT_EMAIL

GOOGLE_API_KEY:
(Get from https://aistudio.google.com/)

## GitHub Repository Variables  
Add at: https://github.com/$GITHUB_USERNAME/$REPO_NAME/settings/variables/actions

GCP_PROJECT_ID: $PROJECT_ID
GCP_REGION: $REGION
ARTIFACT_REPO: storygen-repo
BACKEND_SERVICE_NAME: genai-backend
FRONTEND_SERVICE_NAME: genai-frontend
BUCKET_NAME: $BUCKET_NAME
SECRET_NAME: $SECRET_NAME

## Next Steps
1. Add above secrets and variables to GitHub
2. Get Gemini API key: https://aistudio.google.com/
3. Add API key to Secret Manager:
   echo 'YOUR_API_KEY' | gcloud secrets versions add $SECRET_NAME --data-file=- --project=$PROJECT_ID
4. Add same API key as GOOGLE_API_KEY in GitHub
5. Push to main branch - CI/CD will deploy automatically

## Validation
Run: ./validate-workload-identity.sh
EOF

echo -e "${BLUE}📁 Setup summary saved to: $SUMMARY_FILE${NC}"
