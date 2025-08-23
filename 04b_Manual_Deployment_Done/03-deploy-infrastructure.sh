#!/bin/bash
set -e

echo "🏗️ StoryGen Deploy - Infrastructure"
echo "==================================="

# Load environment variables
source ./load-env.sh

echo ""
echo "📋 Deployment Configuration:"
echo "   Project ID: $PROJECT_ID"
echo "   Region: $REGION"
echo "   Backend Service: $BACKEND_SERVICE_NAME"
echo "   Frontend Service: $FRONTEND_SERVICE_NAME"
echo "   Bucket: $BUCKET_NAME"
echo ""

cd terraform_code

# Create main input.tfvars from environment variables
echo "📄 Creating Terraform variables file..."
cat > input.tfvars << EOF
# Generated from .env - $(date)
project_id = "$PROJECT_ID"
region = "$REGION"
backend_service_name = "$BACKEND_SERVICE_NAME"
frontend_service_name = "$FRONTEND_SERVICE_NAME"
bucket_name = "$BUCKET_NAME"
secret_name = "$SECRET_NAME"
min_instances = $MIN_INSTANCES
max_instances = $MAX_INSTANCES
EOF

# Check if images.tfvars exists (created by build script)
if [ -f "images.tfvars" ]; then
    echo "✅ Using built Docker images from images.tfvars"
    TFVARS_FILES="-var-file=input.tfvars -var-file=images.tfvars"
else
    echo "⚠️ No images.tfvars found. Using placeholder images."
    echo "   Run ./02-build-images.sh first for production deployment."
    TFVARS_FILES="-var-file=input.tfvars"
fi

# Initialize Terraform
echo ""
echo "🔧 Initializing Terraform..."
terraform init

# Import existing resources to avoid conflicts
echo ""
echo "🔄 Checking for existing resources to import..."

# Check if bucket exists and import it
if gsutil ls "gs://$BUCKET_NAME" &>/dev/null; then
    echo "📦 Found existing bucket: $BUCKET_NAME"
    echo "   Importing into Terraform state..."
    terraform import $TFVARS_FILES 'module.generated-images-bucket.google_storage_bucket.bucket' "$BUCKET_NAME" || echo "   Bucket already in state or import failed (continuing...)"
fi

# Check if Artifact Registry repo exists and import it
if gcloud artifacts repositories describe "$ARTIFACT_REPO" --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
    echo "🗃️ Found existing Artifact Registry: $ARTIFACT_REPO"
    echo "   Note: Artifact Registry managed outside Terraform"
fi

# Check if Secret Manager secret exists
if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" &>/dev/null; then
    echo "🔐 Found existing secret: $SECRET_NAME"
    echo "   Note: Secrets managed outside Terraform"
fi

# Plan deployment
echo ""
echo "📋 Planning Terraform deployment..."
terraform plan $TFVARS_FILES

# Apply infrastructure (with confirmation)
echo ""
echo "⚠️ About to deploy infrastructure. Press Enter to continue or Ctrl+C to abort..."
read

terraform apply $TFVARS_FILES -auto-approve

# Get outputs
echo ""
echo "📋 Infrastructure Outputs:"
terraform output

# Make services publicly accessible
echo ""
echo "🌐 Making services publicly accessible..."
gcloud run services add-iam-policy-binding "$BACKEND_SERVICE_NAME" \
    --member="allUsers" \
    --role="roles/run.invoker" \
    --region="$REGION" \
    --project="$PROJECT_ID" || echo "Backend already public"

gcloud run services add-iam-policy-binding "$FRONTEND_SERVICE_NAME" \
    --member="allUsers" \
    --role="roles/run.invoker" \
    --region="$REGION" \
    --project="$PROJECT_ID" || echo "Frontend already public"

echo ""
echo "🏷️  Applying labels to services..."
gcloud run services update "$BACKEND_SERVICE_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --update-labels="dev-tutorial=codelab-annie-devfest"

gcloud run services update "$FRONTEND_SERVICE_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --update-labels="dev-tutorial=codelab-annie-devfest"

# Configure secrets for backend
echo "🔐 Configuring backend secrets..."
gcloud run services update "$BACKEND_SERVICE_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --set-secrets="GOOGLE_API_KEY=${SECRET_NAME}:latest" || echo "Secret already configured"

# Get updated backend URL and rebuild frontend if needed
echo "🔗 Updating frontend with backend URL..."
ACTUAL_BACKEND_URL=$(gcloud run services describe "$BACKEND_SERVICE_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(status.url)")

echo "   Actual backend URL: $ACTUAL_BACKEND_URL"

# Check if frontend needs rebuilding with correct backend URL
CURRENT_FRONTEND_BACKEND=$(gcloud run services describe "$FRONTEND_SERVICE_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(spec.template.spec.containers[0].env[?(@.name=='NEXT_PUBLIC_BACKEND_URL')].value)" 2>/dev/null || echo "")

if [ "$CURRENT_FRONTEND_BACKEND" != "$ACTUAL_BACKEND_URL" ]; then
    echo "🔄 Frontend backend URL mismatch. Rebuilding frontend..."
    echo "   Current: $CURRENT_FRONTEND_BACKEND"
    echo "   Required: $ACTUAL_BACKEND_URL"
    
    # Navigate back to project root first
    cd ..
    
    # Create .env.local with correct backend URL in frontend directory
    cd frontend
    cat > .env.local << EOF
NEXT_PUBLIC_BACKEND_URL=${ACTUAL_BACKEND_URL}
EOF
    
    # Build new frontend image with correct backend URL
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    FRONTEND_IMAGE_URL="${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO}/${FRONTEND_IMAGE_NAME}:${TIMESTAMP}"
    echo "   Building new frontend image: $FRONTEND_IMAGE_URL"
    
    # Build the image with the environment variable set during build
    gcloud builds submit --project="$PROJECT_ID" \
        --config=cloudbuild.yaml \
        --substitutions="_BACKEND_URL=${ACTUAL_BACKEND_URL},_IMAGE_NAME=${FRONTEND_IMAGE_URL}"
    
    # Update frontend service with new image and environment variable
    gcloud run services update "$FRONTEND_SERVICE_NAME" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --image="$FRONTEND_IMAGE_URL" \
        --set-env-vars="NEXT_PUBLIC_BACKEND_URL=${ACTUAL_BACKEND_URL}"
    
    # Navigate back to terraform_code directory
    cd ../terraform_code
    echo "✅ Frontend rebuilt and deployed with correct backend URL"
else
    echo "✅ Frontend already configured with correct backend URL"
fi

# Save outputs for easy access
BACKEND_URL=$(terraform output -raw backend-service_service_uri 2>/dev/null || echo "")
FRONTEND_URL=$(terraform output -raw frontend-service_service_uri 2>/dev/null || echo "")

cd ..

# Save URLs for reference
cat > deployment-urls.env << EOF
# Deployment URLs - $(date)
export BACKEND_URL="$BACKEND_URL"
export FRONTEND_URL="$FRONTEND_URL"
EOF

echo ""
echo "✅ Infrastructure deployment complete!"
echo ""
echo "🌐 Deployment URLs:"
echo "   Backend:  $BACKEND_URL"
echo "   Frontend: $FRONTEND_URL"
echo ""
echo "📝 URLs saved to deployment-urls.env"
echo ""
echo "🎯 Next step: Test your application at the Frontend URL"
