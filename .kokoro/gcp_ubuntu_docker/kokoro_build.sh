#!/bin/bash
set -e
# WARNING: Use 'set -x' only for debugging, be cautious with credentials.
# set -x

echo "Starting Oracle Toolkit Terraform Blueprint generation via Kokoro..."

# Define variables for artifact naming and paths
PACKAGE_NAME="oracle-toolkit-infra-manager.zip"
TEMP_DIR_FOR_PACKAGE=$(mktemp -d)

# 1. Change working directory to the cloned GitHub repository root
# This script runs from the .kokoro/gcp_ubuntu_docker directory,
# so we need to go up two levels to get to the repository root.
cd ../../

# 2. Terraform Root Module Transformation
#    Copy/move your 'terraform' directory content to the root of the TEMP_DIR_FOR_PACKAGE.
#    This ensures a /main.tf file exists at the root of the *zip package*.
echo "Preparing Terraform content for Infra Manager package..."
cp -R terraform/* "${TEMP_DIR_FOR_PACKAGE}/"
# Example: if you need to strip backend blocks from main.tf
# sed -i '/backend/d' "${TEMP_DIR_FOR_PACKAGE}/main.tf"

# 3. Zip the transformed Terraform content along with other necessary files
echo "Creating the zip package: ${PACKAGE_NAME}..."
# Zip contents of the temporary directory (which now has main.tf at its root)
# Exclude .git* and .terraform* files, and terraform.tfvars
zip -r "/tmp/${PACKAGE_NAME}" "${TEMP_DIR_FOR_PACKAGE}/." -x "*.git*" -x "*.terraform*" -x "terraform.tfvars"

# 4. Generate SBOM (Software Bill of Materials) - placeholder command
echo "Generating SBOM metadata (placeholder)..."
# /usr/local/bin/generate-sbom --input "/tmp/${PACKAGE_NAME}" --output "/tmp/sbom.json"

# 5. Sign the zip file (packaged as a JAR for signing)
# This step depends on internal Google signing tools and processes.
SIGNED_ARTIFACT_NAME="${PACKAGE_NAME%.zip}.jar"
echo "Signing the artifact: ${SIGNED_ARTIFACT_NAME} (placeholder)..."
# /usr/local/bin/sign-artifact --input "/tmp/${PACKAGE_NAME}" --output "/tmp/${SIGNED_ARTIFACT_NAME}" --sbom "/tmp/sbom.json"

# For demonstration if actual signing tools are unavailable:
cp "/tmp/${PACKAGE_NAME}" "/tmp/${SIGNED_ARTIFACT_NAME}" # Simulate creation of signed artifact

# 6. Upload artifacts to GCS
TIMESTAMP=$(date +%Y%m%d%H%M)

# For Staging/Development builds (example for 'dev' environment):
DEV_GCS_PATH="gs://cloudoracledeploystaging/terraform/oracle-toolkit/dev/${TIMESTAMP}/${SIGNED_ARTIFACT_NAME}"
echo "Uploading to dev staging GCS: ${DEV_GCS_PATH}..."
gcloud storage cp "/tmp/${SIGNED_ARTIFACT_NAME}" "${DEV_GCS_PATH}"

# For Production builds (assuming this kokoro job is for production release, otherwise adjust)
PROD_GCS_PATH="gs://cloudoracledeploystaging/terraform/oracle-toolkit/prod/${TIMESTAMP}/${SIGNED_ARTIFACT_NAME}"
echo "Uploading to production GCS: ${PROD_GCS_PATH}..."
gcloud storage cp "/tmp/${SIGNED_ARTIFACT_NAME}" "${PROD_GCS_PATH}"

# Maintain 'latest' alias
LATEST_GCS_PATH="gs://cloudoracledeploystaging/terraform/oracle-toolkit/prod/latest/${SIGNED_ARTIFACT_NAME}"
echo "Updating 'latest' alias: ${LATEST_GCS_PATH}..."
gcloud storage cp "/tmp/${SIGNED_ARTIFACT_NAME}" "${LATEST_GCS_PATH}"

# Clean up temporary directory
rm -rf "${TEMP_DIR_FOR_PACKAGE}"

echo "Artifact upload process completed."
