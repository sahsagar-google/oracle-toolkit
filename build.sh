#!/bin/bash
set -e

# --- Script Variables ---
# IMPORTANT: Update with the build GCP Project ID.
PROJECT_ID="gcp-oracle-sandbox"
PACKAGE_NAME="oracle-toolkit-infra-manager.zip"
SIGNED_ARTIFACT_EXTENSION=".jar" # Signed zip is effectively a JAR.
ARTIFACT_BASE_GCS_BUCKET="gs://cloudoracledeploystaging/terraform/oracle-toolkit"

# --- Script Execution ---
echo "Starting Oracle Toolkit Terraform Blueprint generation..."

TEMP_DIR_FOR_PACKAGE=$(mktemp -d)
echo "Using temporary directory for packaging: ${TEMP_DIR_FOR_PACKAGE}"

# 1. Terraform Root Module Transformation
#    Copy 'terraform' directory content to the root of the temporary package directory.
#    This ensures /main.tf exists at the root of the *zip package* for Infra Manager.
echo "Preparing Terraform content for Infra Manager package..."
cp -R terraform/* "${TEMP_DIR_FOR_PACKAGE}/"
# Optional: Uncomment and adapt if you need to strip backend blocks from main.tf
# sed -i '/backend/d' "${TEMP_DIR_FOR_PACKAGE}/main.tf"

# 2. Zip the transformed Terraform content along with other necessary files
echo "Creating the zip package: ${PACKAGE_NAME}..."
zip -r "/tmp/${PACKAGE_NAME}" "${TEMP_DIR_FOR_PACKAGE}/." -x "*.git*" -x "*.terraform*" -x "terraform.tfvars"

# 3. Generate SBOM (Software Bill of Materials) - placeholder
echo "Generating SBOM metadata (placeholder for internal Google tool)..."
# Example: /usr/local/bin/generate-sbom --input "/tmp/${PACKAGE_NAME}" --output "/tmp/sbom.json"

# 4. Sign the zip file (packaged as a JAR for signing) - placeholder
SIGNED_ARTIFACT_NAME="${PACKAGE_NAME%.zip}${SIGNED_ARTIFACT_EXTENSION}"
echo "Signing the artifact: ${SIGNED_ARTIFACT_NAME} (placeholder for internal Google tool)..."
# Example: /usr/local/bin/sign-artifact --input "/tmp/${PACKAGE_NAME}" --output "/tmp/${SIGNED_ARTIFACT_NAME}" --sbom "/tmp/sbom.json"
cp "/tmp/${PACKAGE_NAME}" "/tmp/${SIGNED_ARTIFACT_NAME}" # Simulate creation of signed artifact if tools aren't run

# 5. Upload artifacts to GCS
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

echo "Oracle Toolkit Terraform Blueprint generation process completed."
