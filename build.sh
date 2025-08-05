#!/bin/bash
# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
set -e

# --- Script Variables ---
ARTIFACT_NAME="oracle-toolkit-infra-manager.jar"

# --- Script Execution ---
echo "Starting Oracle Toolkit Terraform Blueprint generation..."

TEMP_DIR_FOR_PACKAGE=$(mktemp -d)
echo "Using temporary directory for packaging: ${TEMP_DIR_FOR_PACKAGE}"

# Copy 'terraform' directory content to the root of the temporary package directory.
echo "Preparing Terraform content for Oracle Toolkit package..."
cp -R terraform/* "${TEMP_DIR_FOR_PACKAGE}/"

# Zip the transformed Terraform content into a JAR package.
echo "Creating the JAR package: ${ARTIFACT_NAME}..."
zip -r "/tmp/${ARTIFACT_NAME}" "${TEMP_DIR_FOR_PACKAGE}/." -x "*.git*" -x "*.terraform*" -x "terraform.tfvars"

# --- Place the final artifact in KOKORO_ARTIFACTS_DIR ---
# Kokoro will automatically upload any files from this directory to GCS.
echo "Moving artifact to KOKORO_ARTIFACTS_DIR for GCS upload..."
mkdir -p "${KOKORO_ARTIFACTS_DIR}"
mv "/tmp/${ARTIFACT_NAME}" "${KOKORO_ARTIFACTS_DIR}/${ARTIFACT_NAME}"

echo "Cleaning up temporary files..."
rm -rf "${TEMP_DIR_FOR_PACKAGE}"

echo "Oracle Toolkit Terraform Blueprint generation process completed."
