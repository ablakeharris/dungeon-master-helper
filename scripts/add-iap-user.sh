#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <email>" >&2
  exit 1
fi

PROJECT="${PROJECT:-dnd-waterdeep-492623}"
REGION="${REGION:-us-central1}"
SERVICE="${SERVICE:-dnd-waterdeep}"
EMAIL="$1"

gcloud config set project "$PROJECT" >/dev/null

gcloud iap web add-iam-policy-binding \
  --resource-type=cloud-run \
  --service="$SERVICE" \
  --region="$REGION" \
  --member="user:${EMAIL}" \
  --role="roles/iap.httpsResourceAccessor"

echo "If the project is still in OAuth Testing mode, also add ${EMAIL} as a Test user:"
echo "  https://console.cloud.google.com/apis/credentials/consent?project=${PROJECT}"
