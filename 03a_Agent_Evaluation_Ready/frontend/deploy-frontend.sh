
#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
PROJECT_ID=$(gcloud config get-value project)
SERVICE_NAME="storygen-frontend"
REGION="us-central1" # Change to your preferred region

if [ -z "$PROJECT_ID" ]; then
    echo "🔴 Error: Google Cloud project ID not found."
    echo "Please set your project using 'gcloud config set project YOUR_PROJECT_ID'"
    exit 1
fi

echo "▶️  Starting frontend deployment to project '$PROJECT_ID' in region '$REGION'..."

# --- 1. Enable APIs ---
echo "✅ Enabling required Google Cloud services..."
gcloud services enable run.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    --project="$PROJECT_ID"

# --- 2. Build Docker Image with Cloud Build ---
echo "🔨 Building Docker image with Cloud Build..."
gcloud builds submit --tag "gcr.io/$PROJECT_ID/$SERVICE_NAME" --project="$PROJECT_ID"

# --- 3. Deploy to Cloud Run ---
echo "🚀 Deploying to Cloud Run..."
gcloud run deploy "$SERVICE_NAME" \
    --image="gcr.io/$PROJECT_ID/$SERVICE_NAME" \
    --platform="managed" \
    --region="$REGION" \
    --allow-unauthenticated \
    --project="$PROJECT_ID"

# --- 4. Get Service URL ---
SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" --platform="managed" --region="$REGION" --format="value(status.url)" --project="$PROJECT_ID")

echo "----------------------------------------"
echo "✅ Frontend deployment successful!"
echo "🚀 Service URL: $SERVICE_URL"
echo "----------------------------------------" 