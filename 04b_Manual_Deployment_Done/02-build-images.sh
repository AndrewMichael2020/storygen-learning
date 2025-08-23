#!/bin/bash
set -e

echo "🔨 StoryGen Build - Docker Images"
echo "================================="

# Load environment variables
source ./load-env.sh

# Generate timestamp for image versioning
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
VERSION_TAG="${TIMESTAMP}"

echo ""
echo "📋 Build Configuration:"
echo "   Project ID: $PROJECT_ID"
echo "   Region: $REGION"
echo "   Artifact Repo: $ARTIFACT_REPO"
echo "   Version Tag: $VERSION_TAG"
echo ""

# Build and push backend image
echo "🚀 Building Backend Image..."
echo "================================="

cd backend

BACKEND_IMAGE_URL="${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO}/${BACKEND_IMAGE_NAME}:${VERSION_TAG}"
BACKEND_IMAGE_URL_LATEST="${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO}/${BACKEND_IMAGE_NAME}:latest"

echo "🔨 Building: $BACKEND_IMAGE_URL"

gcloud builds submit \
    --tag "$BACKEND_IMAGE_URL" \
    --project="$PROJECT_ID"

# Also tag as latest
gcloud builds submit \
    --tag "$BACKEND_IMAGE_URL_LATEST" \
    --project="$PROJECT_ID"

echo "✅ Backend image built and pushed!"
echo "   Tagged: $BACKEND_IMAGE_URL"
echo "   Latest: $BACKEND_IMAGE_URL_LATEST"

cd ..

# Build and push frontend image
echo ""
echo "🚀 Building Frontend Image..."
echo "================================="

cd frontend

# Check if pnpm-lock.yaml exists and is up to date
if [ -f "pnpm-lock.yaml" ] && command -v pnpm &> /dev/null; then
    echo "🔍 Checking frontend dependencies..."
    if ! pnpm install --frozen-lockfile --dry-run &>/dev/null; then
        echo "⚠️ pnpm-lock.yaml is outdated. Regenerating..."
        pnpm install --no-frozen-lockfile
        echo "✅ Dependencies updated"
    fi
fi

FRONTEND_IMAGE_URL="${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO}/${FRONTEND_IMAGE_NAME}:${VERSION_TAG}"
FRONTEND_IMAGE_URL_LATEST="${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO}/${FRONTEND_IMAGE_NAME}:latest"

echo "🔨 Building: $FRONTEND_IMAGE_URL"

# Build with placeholder backend URL (will be updated during infrastructure deployment)
PLACEHOLDER_BACKEND_URL="https://placeholder-backend.example.com"

gcloud builds submit \
    --project="$PROJECT_ID" \
    --config=cloudbuild.yaml \
    --substitutions="_BACKEND_URL=${PLACEHOLDER_BACKEND_URL},_IMAGE_NAME=${FRONTEND_IMAGE_URL}"

# Also tag as latest
gcloud builds submit \
    --project="$PROJECT_ID" \
    --config=cloudbuild.yaml \
    --substitutions="_BACKEND_URL=${PLACEHOLDER_BACKEND_URL},_IMAGE_NAME=${FRONTEND_IMAGE_URL_LATEST}"

echo "✅ Frontend image built and pushed!"
echo "   Tagged: $FRONTEND_IMAGE_URL"
echo "   Latest: $FRONTEND_IMAGE_URL_LATEST"

cd ..

# Save image URLs for Terraform
echo ""
echo "📝 Saving image references for Terraform..."

cat > terraform_code/images.tfvars << EOF
# Generated image references - $(date)
backend_image = "$BACKEND_IMAGE_URL_LATEST"
frontend_image = "$FRONTEND_IMAGE_URL_LATEST"
EOF

echo "✅ Images built and pushed successfully!"
echo ""
echo "📋 Image Summary:"
echo "   Backend:  $BACKEND_IMAGE_URL_LATEST"
echo "   Frontend: $FRONTEND_IMAGE_URL_LATEST"
echo ""
echo "🎯 Next step: Run ./03-deploy-infrastructure.sh"
