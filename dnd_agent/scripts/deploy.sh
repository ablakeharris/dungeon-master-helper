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
#   - aiplatform.user: the build runs `uv run python dnd_agent/scripts/ingest_docs.py`,
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

# The service is private (--no-allow-unauthenticated). Access is via an
# authenticated local proxy (scripts/run-local.sh), so the deploying account
# needs run.invoker. Granting it here keeps the service private while letting
# you reach it immediately.
ACTIVE_ACCOUNT="$(gcloud config get-value account 2>/dev/null)"
gcloud run services add-iam-policy-binding "$SERVICE" \
  --region="$REGION" \
  --project="$PROJECT" \
  --member="user:${ACTIVE_ACCOUNT}" \
  --role="roles/run.invoker" >/dev/null

echo
echo "Deployed (private). Next: run dnd_agent/scripts/run-local.sh and open http://localhost:8088/dev-ui/"
