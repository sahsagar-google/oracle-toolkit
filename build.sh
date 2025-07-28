#!/bin/bash
set -e

# --- Script Variables ---
PROJECT_ID="gcp-oracle-sandbox"
PACKAGE_NAME="oracle-toolkit-infra-manager.zip"
SIGNED_ARTIFACT_EXTENSION=".jar"
ARTIFACT_BASE_GCS_BUCKET="gs://cloudoracledeploystaging/terraform/oracle-toolkit"

# --- Script Execution ---
echo "Starting Oracle Toolkit Terraform Blueprint generation..."
echo "Running build with initial Kokoro service account: $(gcloud config get-value core/account)"

# Temporarily switch to the elevated service account
ELEVATED_SA_EMAIL="gcs-upload-sa@gcp-oracle-sandbox.iam.gserviceaccount.com"
KOKORO_SA_EMAIL=$(gcloud config get-value core/account)

echo "Attempting to switch to elevated service account: ${ELEVATED_SA_EMAIL}"

# Get a temporary access token for the elevated service account via impersonation
ELEVATED_SA_TOKEN=$(gcloud auth print-access-token --impersonate-service-account="${ELEVATED_SA_EMAIL}")

# Activate the elevated service account using the obtained token
gcloud auth activate-service-account "${ELEVATED_SA_EMAIL}" --access-token="${ELEVATED_SA_TOKEN}" --project="${PROJECT_ID}"

echo "Successfully switched context to: $(gcloud config get-value core/account)"

TEMP_DIR_FOR_PACKAGE=$(mktemp -d)
echo "Using temporary directory for packaging: ${TEMP_DIR_FOR_PACKAGE}"

# Copy 'terraform' directory content to the root of the temporary package directory.
echo "Preparing Terraform content for Infra Manager package..."
cp -R terraform/* "${TEMP_DIR_FOR_PACKAGE}/"

# Zip the transformed Terraform content along with other necessary files
echo "Creating the zip package: ${PACKAGE_NAME}..."
zip -r "/tmp/${PACKAGE_NAME}" "${TEMP_DIR_FOR_PACKAGE}/." -x "*.git*" -x "*.terraform*" -x "terraform.tfvars"

# Generate SBOM - placeholder
echo "Generating SBOM metadata (placeholder for internal Google tool)..."
# Example: /usr/local/bin/generate-sbom --input "/tmp/${PACKAGE_NAME}" --output "/tmp/sbom.json"

# Sign the zip file - placeholder
SIGNED_ARTIFACT_NAME="${PACKAGE_NAME%.zip}${SIGNED_ARTIFACT_EXTENSION}"
echo "Signing the artifact: ${SIGNED_ARTIFACT_NAME}..."
# Example: /usr/local/bin/sign-artifact --input "/tmp/${PACKAGE_NAME}" --output "/tmp/${SIGNED_ARTIFACT_NAME}" --sbom "/tmp/sbom.json"
cp "/tmp/${PACKAGE_NAME}" "/tmp/${SIGNED_ARTIFACT_NAME}" # Simulate creation of signed artifact if tools aren't run

# Upload artifacts to GCS
TIMESTAMP=$(date +%Y%m%d%H%M) # Current timestamp for versioned artifacts

DEV_GCS_PATH="${ARTIFACT_BASE_GCS_BUCKET}/dev/${KOKORO_BUILD_ID}/${SIGNED_ARTIFACT_NAME}"
echo "Uploading to dev staging GCS: ${DEV_GCS_PATH}..."
gcloud storage cp "/tmp/${SIGNED_ARTIFACT_NAME}" "${DEV_GCS_PATH}" --project="${PROJECT_ID}"

PROD_GCS_PATH="${ARTIFACT_BASE_GCS_BUCKET}/prod/${KOKORO_BUILD_ID}/${SIGNED_ARTIFACT_NAME}"
echo "Uploading to production GCS: ${PROD_GCS_PATH}..."
gcloud storage cp "/tmp/${SIGNED_ARTIFACT_NAME}" "${PROD_GCS_PATH}" --project="${PROJECT_ID}"

LATEST_GCS_PATH="${ARTIFACT_BASE_GCS_BUCKET}/prod/latest/${SIGNED_ARTIFACT_NAME}"
echo "Updating 'latest' alias: ${LATEST_GCS_PATH}..."
gcloud storage cp "/tmp/${SIGNED_ARTIFACT_NAME}" "${LATEST_GCS_PATH}" --project="${PROJECT_ID}"

echo "Cleaning up temporary files..."
rm -rf "${TEMP_DIR_FOR_PACKAGE}"

echo "Switching back to original service account: ${KOKORO_SA_EMAIL}"
gcloud auth revoke "${ELEVATED_SA_EMAIL}"
gcloud auth activate-service-account "${KOKORO_SA_EMAIL}" --project="${PROJECT_ID}"

echo "Switched back to: $(gcloud config get-value core/account)"
echo "Oracle Toolkit Terraform Blueprint generation process completed."
