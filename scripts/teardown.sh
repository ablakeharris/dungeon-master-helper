#!/usr/bin/env bash
# Tear down the Google Cloud resources created by deploy.sh.
#
# Removes, in order:
#   1. The Cloud Run service (its run.invoker bindings go with it)
#   2. The service's image in the Artifact Registry repo that `--source`
#      deploys create automatically (cloud-run-source-deploy), and the repo
#      itself if nothing else is left in it
#   3. Uploaded source archives in the Cloud Build / Cloud Run source buckets,
#      and each bucket if it is left empty
#   4. The IAM roles deploy.sh granted to the Compute Engine default SA
#   5. (only with --disable-apis) the APIs deploy.sh enabled
#
# Every step skips resources that are already gone, so it is safe to re-run.
#
# Usage:
#   bash scripts/teardown.sh                 # asks for confirmation
#   bash scripts/teardown.sh --yes           # no prompt
#   bash scripts/teardown.sh --disable-apis  # also disable the enabled APIs
set -euo pipefail

PROJECT="${PROJECT:-dnd-waterdeep-492623}"
REGION="${REGION:-us-central1}"
SERVICE="${SERVICE:-dnd-waterdeep}"
AR_REPO="cloud-run-source-deploy"

ASSUME_YES=false
DISABLE_APIS=false
for arg in "$@"; do
  case "$arg" in
    -y | --yes) ASSUME_YES=true ;;
    --disable-apis) DISABLE_APIS=true ;;
    -h | --help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
BUILD_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

echo "This will delete from project '${PROJECT}' (region ${REGION}):"
echo "  - Cloud Run service:      ${SERVICE}"
echo "  - Artifact Registry image: ${REGION}-docker.pkg.dev/${PROJECT}/${AR_REPO}/${SERVICE}"
echo "    (and the ${AR_REPO} repo if it is then empty)"
echo "  - Uploaded source archives in gs://run-sources-${PROJECT}-${REGION} and gs://${PROJECT}_cloudbuild"
echo "    (and each bucket if it is then empty)"
echo "  - IAM roles on ${BUILD_SA}:"
echo "      roles/cloudbuild.builds.builder, roles/aiplatform.user"
if $DISABLE_APIS; then
  echo "  - APIs: run, cloudbuild, aiplatform, artifactregistry"
fi
echo

if ! $ASSUME_YES; then
  read -r -p "Continue? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

# --- 1. Cloud Run service ----------------------------------------------------
if gcloud run services describe "$SERVICE" --region="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud run services delete "$SERVICE" --region="$REGION" --project="$PROJECT" --quiet
  echo "Deleted Cloud Run service: ${SERVICE}"
else
  echo "Cloud Run service ${SERVICE} not found, skipping."
fi

# --- 2. Artifact Registry ----------------------------------------------------
if gcloud artifacts repositories describe "$AR_REPO" --location="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
  if gcloud artifacts packages describe "$SERVICE" --repository="$AR_REPO" \
    --location="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
    gcloud artifacts packages delete "$SERVICE" --repository="$AR_REPO" \
      --location="$REGION" --project="$PROJECT" --quiet
    echo "Deleted Artifact Registry image: ${SERVICE}"
  fi

  # Other services in the project may share this auto-created repo.
  remaining="$(gcloud artifacts packages list --repository="$AR_REPO" \
    --location="$REGION" --project="$PROJECT" --format='value(name)' --limit=1)"
  if [[ -z "$remaining" ]]; then
    gcloud artifacts repositories delete "$AR_REPO" --location="$REGION" --project="$PROJECT" --quiet
    echo "Deleted Artifact Registry repo: ${AR_REPO}"
  else
    echo "Artifact Registry repo ${AR_REPO} still holds other images, leaving it."
  fi
else
  echo "Artifact Registry repo ${AR_REPO} not found, skipping."
fi

# --- 3. Source upload buckets ------------------------------------------------
# `gcloud run deploy --source` uploads the source to one of these buckets,
# depending on the gcloud version.
clean_bucket() {
  local bucket="$1" prefix="$2"
  if ! gcloud storage buckets describe "gs://${bucket}" --project="$PROJECT" >/dev/null 2>&1; then
    echo "Bucket gs://${bucket} not found, skipping."
    return
  fi
  if gcloud storage ls "gs://${bucket}/${prefix}**" --project="$PROJECT" >/dev/null 2>&1; then
    gcloud storage rm "gs://${bucket}/${prefix}**" --project="$PROJECT" --quiet
    echo "Deleted source archives: gs://${bucket}/${prefix}"
  fi
  if [[ -z "$(gcloud storage ls "gs://${bucket}" --project="$PROJECT" 2>/dev/null)" ]]; then
    gcloud storage buckets delete "gs://${bucket}" --project="$PROJECT" --quiet
    echo "Deleted bucket: gs://${bucket}"
  else
    echo "Bucket gs://${bucket} still holds other objects, leaving it."
  fi
}
clean_bucket "run-sources-${PROJECT}-${REGION}" "services/${SERVICE}/"
clean_bucket "${PROJECT}_cloudbuild" "source/"

# --- 4. IAM bindings on the Compute Engine default SA ------------------------
for role in roles/cloudbuild.builds.builder roles/aiplatform.user; do
  bound="$(gcloud projects get-iam-policy "$PROJECT" \
    --flatten='bindings[].members' \
    --filter="bindings.role=${role} AND bindings.members=serviceAccount:${BUILD_SA}" \
    --format='value(bindings.role)')"
  if [[ -n "$bound" ]]; then
    gcloud projects remove-iam-policy-binding "$PROJECT" \
      --member="serviceAccount:${BUILD_SA}" \
      --role="$role" \
      --condition=None >/dev/null
    echo "Removed ${role} from ${BUILD_SA}"
  else
    echo "${role} not bound to ${BUILD_SA}, skipping."
  fi
done

# --- 5. APIs (opt-in) --------------------------------------------------------
if $DISABLE_APIS; then
  gcloud services disable \
    run.googleapis.com \
    cloudbuild.googleapis.com \
    aiplatform.googleapis.com \
    artifactregistry.googleapis.com \
    --project="$PROJECT" --force
  echo "Disabled APIs."
fi

echo
echo "Teardown complete."
