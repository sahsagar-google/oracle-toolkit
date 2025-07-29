#!/bin/bash
set -e

# --- Script Variables ---
PROJECT_ID="gcp-oracle-sandbox" # Your project ID
PACKAGE_NAME="oracle-toolkit-infra-manager.zip"
SIGNED_ARTIFACT_EXTENSION=".jar"

# KOKORO_ARTIFACTS_DIR is an environment variable provided by Kokoro
# Any files placed in this directory will be automatically uploaded to GCS
# by the `post_build` configuration in the .kokoro/config file.
ARTIFACT_UPLOAD_DIR="${KOKORO_ARTIFACTS_DIR}"

# --- Script Execution ---
echo "Starting Oracle Toolkit Terraform Blueprint generation..."
echo "Running build with Kokoro service account: $(gcloud config get-value core/account)"

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

# --- Place the final signed artifact in KOKORO_ARTIFACTS_DIR ---
# Kokoro's post_build will pick this up and upload it to GCS.
echo "Moving signed artifact to KOKORO_ARTIFACTS_DIR for GCS upload..."
# Ensure the directory exists
mkdir -p "${ARTIFACT_UPLOAD_DIR}"
mv "/tmp/${SIGNED_ARTIFACT_NAME}" "${ARTIFACT_UPLOAD_DIR}/${SIGNED_ARTIFACT_NAME}"

# Optional: If you also want to upload the SBOM, place it in ARTIFACT_UPLOAD_DIR as well
# mv "/tmp/sbom.json" "${ARTIFACT_UPLOAD_DIR}/sbom.json"

echo "Cleaning up temporary files..."
rm -rf "${TEMP_DIR_FOR_PACKAGE}"

echo "Oracle Toolkit Terraform Blueprint generation process completed."
