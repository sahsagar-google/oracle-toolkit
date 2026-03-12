#!/bin/bash
# tools/deploy-infra-manager.sh

set -e

# --- Path Calculations ---
SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")

ZIP_STAGING_DIR=""
TEMPLATED_TFVARS=""

cleanup() {
  local exit_code=$?
  [[ -n "$TEMPLATED_TFVARS" && -f "$TEMPLATED_TFVARS" ]] && rm -f "$TEMPLATED_TFVARS"
  [[ -n "$ZIP_STAGING_DIR" && -d "$ZIP_STAGING_DIR" ]] && rm -rf "$ZIP_STAGING_DIR"
  exit "$exit_code"
}
trap cleanup EXIT

USER_CLEAN=$(echo "${USER:-anon}" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-')

usage() {
  echo "Usage: $0 --tfvars-file <path> --gcs-bucket <gs://bucket> --service-account <email> [options]"
  echo ""
  echo "Templating Support (Use these in your .tfvars):"
  echo "  @gcs_source@, @deployment_name@, @instance_name@"
  echo ""
  echo "Options:"
  echo "  --force            Delete existing deployment before starting."
  echo "  --deployment-name  Deployment ID (default: oracle-deploy-$USER_CLEAN)"
  echo "  --location         GCP region (default: us-central1)"
  exit 1
}

# --- Argument Parsing ---
DEPLOYMENT_NAME="oracle-deploy-${USER_CLEAN}"
LOCATION="us-central1"
POLL_INTERVAL_SECONDS=5
FORCE_DELETE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --tfvars-file) TFVARS_FILE=$(readlink -f "$2"); shift 2 ;;
    --gcs-bucket) GCS_BUCKET="${2%/}"; shift 2 ;;
    --service-account) SERVICE_ACCOUNT="$2"; shift 2 ;;
    --force) FORCE_DELETE=true; shift ;;
    --deployment-name) DEPLOYMENT_NAME="$2"; shift 2 ;;
    --location) LOCATION="$2"; shift 2 ;;
    --project-id) PROJECT_ID="$2"; shift 2 ;;
    *) usage ;;
  esac
done

if [[ -z "$TFVARS_FILE" || -z "$GCS_BUCKET" || -z "$SERVICE_ACCOUNT" ]]; then
  usage
fi

PROJECT_ID=${PROJECT_ID:-$(gcloud config get-value project)}
DEPLOYMENT_FULL_ID="projects/${PROJECT_ID}/locations/${LOCATION}/deployments/${DEPLOYMENT_NAME}"

# --- 1. Fresh Start Check ---
if gcloud infra-manager deployments describe "${DEPLOYMENT_FULL_ID}" --location="${LOCATION}" >/dev/null 2>&1; then
  if [ "$FORCE_DELETE" = true ]; then
    echo "Existing deployment found. Deleting for fresh start..."
    gcloud infra-manager deployments delete "${DEPLOYMENT_FULL_ID}" --location="${LOCATION}" --quiet
  else
    echo "ERROR: Deployment '${DEPLOYMENT_NAME}' already exists. Use --force to recreate."
    exit 1
  fi
fi

# --- 2. Package and Stage Toolkit ---
ZIP_STAGING_DIR=$(mktemp -d)
TOOLKIT_ZIP_PATH="${ZIP_STAGING_DIR}/toolkit.zip"
GCS_DESTINATION="${GCS_BUCKET}/toolkit-${DEPLOYMENT_NAME}.zip"

echo "Packaging toolkit..."
(cd "$PROJECT_ROOT" && zip -r "$TOOLKIT_ZIP_PATH" . -x ".git*" -x ".terraform*" -x "terraform/*" -x "OWNERS" > /dev/null)
gcloud storage cp "$TOOLKIT_ZIP_PATH" "$GCS_DESTINATION"

# --- 3. Prepare Deployment Inputs ---
TEMPLATED_TFVARS=$(mktemp /tmp/deploy.tfvars.XXXXXX)
sed -e "s|@deployment_name@|${DEPLOYMENT_NAME}|g;
        s|@instance_name@|${DEPLOYMENT_NAME}|g;
        s|@gcs_source@|${GCS_DESTINATION}|g" "${TFVARS_FILE}" > "${TEMPLATED_TFVARS}"

# --- 4. Trigger Deployment ---
echo "---"
echo "Deployment Status Link: https://console.cloud.google.com/infra-manager/deployments/details/${LOCATION}/${DEPLOYMENT_NAME}?project=${PROJECT_ID}"
echo "---"

gcloud infra-manager deployments apply "${DEPLOYMENT_FULL_ID}" \
  --local-source="${PROJECT_ROOT}/terraform" \
  --inputs-file="${TEMPLATED_TFVARS}" \
  --location="${LOCATION}" \
  --service-account="projects/${PROJECT_ID}/serviceAccounts/${SERVICE_ACCOUNT}" || true

REVISION_ID=""
while [[ -z "$REVISION_ID" ]]; do
  REVISION_ID=$(gcloud infra-manager deployments describe "${DEPLOYMENT_FULL_ID}" \
    --location="${LOCATION}" --format="value(latestRevision)" 2>/dev/null || true)
  [[ -n "$REVISION_ID" ]] && break
  echo "Waiting for revision ID to be generated..."
  sleep 2
done

# --- 5. Poll for Completion ---
echo "Monitoring Revision ${REVISION_ID##*}..."
while true; do
  STATE=$(gcloud infra-manager revisions describe "${REVISION_ID}" --location="${LOCATION}" --format="value(state)")

  if [[ "$STATE" == "APPLIED" || "$STATE" == "SUCCEEDED" || "$STATE" == "ACTIVE" ]]; then
    echo "Infrastructure has been successfully APPLIED."
    break
  elif [[ "$STATE" == "FAILED" ]]; then
    echo "------------------------------------------------------------"
    echo "SPECIFIC TERRAFORM ERRORS DETECTED:"
    gcloud infra-manager revisions describe "${REVISION_ID}" --location="${LOCATION}" --format="yaml(tfErrors)"
    echo "------------------------------------------------------------"
    exit 1
  fi
  sleep "${POLL_INTERVAL_SECONDS}"
done

# --- 6. Results (Pulled directly from Revision) ---
# We use --format="value(...)" to extract the exact nested fields from the applyResults
VM_NAMES=$(gcloud infra-manager revisions describe "${REVISION_ID}" \
  --location="${LOCATION}" \
  --format="value(applyResults.outputs.database_vm_names.value)")

LOG_URL=$(gcloud infra-manager revisions describe "${REVISION_ID}" \
  --location="${LOCATION}" \
  --format="value(applyResults.outputs.control_node_log_url.value)")

echo "------------------------------------------------------------"
echo "Success!"
echo "Database VM(s): ${VM_NAMES:-'N/A'}"
echo "Ansible Setup Logs: ${LOG_URL:-'N/A'}"
echo "------------------------------------------------------------"
