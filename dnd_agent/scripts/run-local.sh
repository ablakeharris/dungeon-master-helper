#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-dnd-waterdeep-492623}"
REGION="${REGION:-us-central1}"
SERVICE="${SERVICE:-dnd-waterdeep}"
PORT="${PORT:-8088}"

# The Cloud Run service is private (deployed with --no-allow-unauthenticated and
# no public ingress). Rather than expose it, we reach it through an authenticated
# local proxy: `gcloud run services proxy` forwards localhost:$PORT to the
# service and signs every request with your gcloud identity, which needs
# roles/run.invoker (deploy.sh grants this to the deploying account).
#
# The first run installs the `cloud-run-proxy` gcloud component if it is missing.

echo "Proxying ${SERVICE} -> http://localhost:${PORT}"
echo "Once it says 'proxies to ...', open: http://localhost:${PORT}/dev-ui/"
echo

exec gcloud run services proxy "$SERVICE" \
  --region="$REGION" \
  --project="$PROJECT" \
  --port="$PORT"
