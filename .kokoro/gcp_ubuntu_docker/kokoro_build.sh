#!/bin/bash
set -e
# WARNING: Only enable 'set -x' if necessary for debugging, and be cautious with credentials.
# set -x

echo "Executing Kokoro build script for Oracle Toolkit..."

# Navigate to the root of the cloned GitHub repository.
# KOKORO_ARTIFACTS_DIR is set by Kokoro. The repo is cloned into ${KOKORO_ARTIFACTS_DIR}/github/oracle-toolkit.
# This script is executed from within .kokoro/gcp_ubuntu_docker, so we go up two levels.
cd "${KOKORO_ARTIFACTS_DIR}/github/oracle-toolkit"

# Execute your main project's build.sh script from the repository root.
echo "Executing project's main build.sh script from repository root..."
./build.sh

echo "Kokoro build script finished."
