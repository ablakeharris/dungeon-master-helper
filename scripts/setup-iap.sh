#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-dnd-waterdeep-492623}"
REGION="${REGION:-us-central1}"
SERVICE="${SERVICE:-dnd-waterdeep}"
ALLOWLIST_USER="${ALLOWLIST_USER:-}"

gcloud config set project "$PROJECT" >/dev/null

if [[ -z "$ALLOWLIST_USER" ]]; then
  echo "ALLOWLIST_USER must be set to the Google account that should have access, e.g.:" >&2
  echo "  ALLOWLIST_USER=you@example.com $0" >&2
  exit 1
fi

# cloudresourcemanager is required by `gcloud iap web add-iam-policy-binding`.
gcloud services enable iap.googleapis.com cloudresourcemanager.googleapis.com --project="$PROJECT"

# IAP invokes Cloud Run on behalf of authenticated users via its service agent,
# so that agent needs run.invoker. Creating the identity is idempotent.
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
IAP_SA="service-${PROJECT_NUMBER}@gcp-sa-iap.iam.gserviceaccount.com"
gcloud beta services identity create --service=iap.googleapis.com --project="$PROJECT" >/dev/null

# A freshly-created service agent can take several seconds to become visible to
# IAM, so the binding may fail with "does not exist" on the first try. Retry.
for attempt in $(seq 1 6); do
  if gcloud run services add-iam-policy-binding "$SERVICE" \
      --region="$REGION" \
      --member="serviceAccount:${IAP_SA}" \
      --role="roles/run.invoker" >/dev/null 2>&1; then
    break
  fi
  if [[ "$attempt" -eq 6 ]]; then
    echo "Could not bind run.invoker to ${IAP_SA} after several attempts." >&2
    echo "The IAP service agent may still be propagating; just re-run this script." >&2
    exit 1
  fi
  echo "IAP service agent not visible to IAM yet; retrying in 10s (${attempt}/6)..."
  sleep 10
done

# Enable IAP directly on the service (no load balancer). IAP manages its own
# OAuth client, so no client ID/secret is needed here.
gcloud run services update "$SERVICE" --region="$REGION" --iap

# Allowlist the user on the Cloud Run IAP resource.
gcloud iap web add-iam-policy-binding \
  --resource-type=cloud-run \
  --service="$SERVICE" \
  --region="$REGION" \
  --member="user:${ALLOWLIST_USER}" \
  --role="roles/iap.httpsResourceAccessor" >/dev/null

SERVICE_URL="$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)')"

cat <<EOF

=======================================================================
  IAP is enabled directly on Cloud Run (no load balancer).

  URL:  ${SERVICE_URL}

  Visit it and sign in with ${ALLOWLIST_USER}.

  If this is a personal (non-Workspace) project and sign-in is blocked,
  configure the OAuth consent screen once (External, Testing mode) and
  add ${ALLOWLIST_USER} as a Test user:
     https://console.cloud.google.com/apis/credentials/consent?project=${PROJECT}

  To add more users later:
     scripts/add-iap-user.sh <email>
=======================================================================
EOF
