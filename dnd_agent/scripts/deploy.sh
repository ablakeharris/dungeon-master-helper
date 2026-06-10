#!/usr/bin/env bash
# Deploy the dnd-agent to Cloud Run.
#
# The service is private (--no-allow-unauthenticated). Access is via an
# authenticated local proxy: each authorised user runs run-local.sh, which
# uses `gcloud run services proxy` to forward localhost:8088 to the service
# and signs every request with their gcloud identity.
#
# Usage:
#   bash dnd_agent/scripts/deploy.sh
set -euo pipefail

PROJECT="${PROJECT:-dnd-waterdeep-492623}"
REGION="${REGION:-us-central1}"
SERVICE="${SERVICE:-dnd-waterdeep}"

# Always run from the project root (where Dockerfile lives).
cd "$(dirname "$0")/../.."

gcloud config set project "$PROJECT" >/dev/null

gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  aiplatform.googleapis.com \
  --project="$PROJECT"

# The Compute Engine default SA runs the Cloud Build. It needs:
#   - cloudbuild.builds.builder  – upload source, push image, write logs
#   - aiplatform.user            – ingest_docs.py calls Vertex AI embeddings
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

# Grant run.invoker to each authorised user so they can use the proxy.
ACTIVE_ACCOUNT="$(gcloud config get-value account 2>/dev/null)"
for member in "user:${ACTIVE_ACCOUNT}"; do
  gcloud run services add-iam-policy-binding "$SERVICE" \
    --region="$REGION" \
    --project="$PROJECT" \
    --member="$member" \
    --role="roles/run.invoker" >/dev/null
  echo "Granted run.invoker: ${member}"
done

echo
echo "Deployed. To access the UI, run: bash dnd_agent/scripts/run-local.sh"
echo "Then open: http://localhost:8088/dev-ui/"
