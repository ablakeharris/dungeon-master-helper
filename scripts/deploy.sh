#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-dnd-waterdeep-492623}"
REGION="${REGION:-us-central1}"
SERVICE="${SERVICE:-dnd-waterdeep}"

cd "$(dirname "$0")/.."

gcloud config set project "$PROJECT" >/dev/null

gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  aiplatform.googleapis.com \
  --project="$PROJECT"

# Source-based Cloud Run deploys run the build as the Compute Engine default
# service account. It needs:
#   - cloudbuild.builds.builder: read the uploaded source from the staging
#     bucket, push to Artifact Registry, write build logs.
#   - aiplatform.user: the build runs `uv run python scripts/ingest_docs.py`,
#     which calls Vertex AI for embeddings.
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
BUILD_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
for role in roles/cloudbuild.builds.builder roles/aiplatform.user; do
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:${BUILD_SA}" \
    --role="$role" \
    --condition=None >/dev/null
done

gcloud run deploy "$SERVICE" \
  --source . \
  --project="$PROJECT" \
  --region="$REGION" \
  --no-allow-unauthenticated \
  --ingress=all \
  --max-instances=1 \
  --cpu=2 --memory=2Gi \
  --timeout=3600 \
  --set-env-vars="GOOGLE_CLOUD_PROJECT=${PROJECT},GOOGLE_CLOUD_LOCATION=${REGION},GOOGLE_GENAI_USE_VERTEXAI=TRUE"

echo
echo "Deployed. Next: run scripts/setup-iap.sh to put the service behind IAP."
