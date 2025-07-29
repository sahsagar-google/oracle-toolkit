#!/bin/bash
# Copyright 2025 Google LLC
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


gcs_bucket="gs://oracle-toolkit-presubmit-artifacts"
# Append BUILD_ID to the file name to ensure each zip file gets a unique name.
# This prevents one test from deleting the file while it's still in use by another concurrently running test.
# For available Prow-injected environment variables, see:
# https://docs.prow.k8s.io/docs/jobs/#job-environment-variables
toolkit_zip_file_name="oracle-toolkit-${BUILD_ID}.zip"
tfvars_file="./presubmit_tests/single-instance.tfvars"
instance_name="github-presubmit-si-${BUILD_ID}"
deployment_name="presubmit-si-${BUILD_ID}"
location="us-central1"
project="gcp-oracle-benchmarks"
gcs_source="${gcs_bucket}/${toolkit_zip_file_name}"
deployment_id="projects/${project}/locations/${location}/deployments/${deployment_name}"

cleanup() {
  if [[ -n "${tail_pid}" ]]; then
    kill "${tail_pid}"
  fi
  echo "Cleaning up: deleting ${gcs_source} GCS object and ${deployment_id} Infra Manager deployment..."
  if gcloud infra-manager deployments describe "${deployment_id}" >/dev/null 2>&1; then
    gcloud --quiet infra-manager deployments delete "${deployment_id}" 
  fi
  if gcloud storage objects describe "${gcs_source}" >/dev/null 2>&1; then
    gcloud --quiet storage rm "${gcs_source}"
  fi
}

trap cleanup SIGINT SIGTERM EXIT

apk add --no-cache zip jq

echo "Zipping CWD into /tmp/${toolkit_zip_file_name} and uploading to ${gcs_bucket}/..."
zip -r /tmp/"${toolkit_zip_file_name}" . -x ".git*" -x ".terraform*" -x "terraform*" -x OWNERS > /dev/null
gcloud storage cp /tmp/"${toolkit_zip_file_name}" "${gcs_bucket}/"

sed -i "s|@deployment_name@|$deployment_name|g" "${tfvars_file}"
sed -i "s|@gcs_source@|$gcs_source|g" "${tfvars_file}"
sed -i "s|@instance_name@|$instance_name|g" "${tfvars_file}"

echo "Applying Infra Manager deployment: ${deployment_id}"
gcloud infra-manager deployments apply "${deployment_id}" \
  --service-account="projects/${project}/serviceAccounts/infra-manager-deployer@${project}.iam.gserviceaccount.com" \
  --local-source="./terraform" \
  --inputs-file="${tfvars_file}" || exit 1

echo "List resources for a deployment revision:"
gcloud infra-manager resources list \
--deployment="${deployment_name}" \
--location="${location}" \
--revision=r-0 \
--format=json

# Extract the id of the control node resource
# The format is: projects/<project>/zones/<zone>/instances/control-node-<random-suffix>
control_node_resource_id="$(gcloud infra-manager resources list \
--deployment="${deployment_name}" \
--location="${location}" \
--revision=r-0 \
--format=json | jq -r '.[] | select(.terraformInfo.address == "google_compute_instance.control_node") | .terraformInfo.id')"

if [[ -z "${control_node_resource_id}" ]]; then
  echo "Could not retrieve control node's resource ID."
  exit 1
fi
echo "Control node resource ID: ${control_node_resource_id}"

control_node_instance_zone="$(echo "${control_node_resource_id}" | cut -d'/' -f4)"
if [[ -z "${control_node_instance_zone}" ]]; then
  echo "Could not extract control node's zone."
  exit 1
fi
echo "Control node zone: ${control_node_instance_zone}"

control_node_instance_name="$(echo "${control_node_resource_id}" | cut -d'/' -f6)"
if [[ -z "${control_node_instance_name}" ]]; then
  echo "Could not extract control node's name."
  exit 1
fi
echo "Control node name: ${control_node_instance_name}"

# Get the instance ID from the instance name
control_node_instance_id="$(gcloud compute instances describe "${control_node_instance_name}" \
  --zone="${control_node_zone}" \
  --format="value(id)")"
if [[ -z "${control_node_instance_id}" ]]; then
  echo "Could not get control node's instance ID."
  exit 1
fi
echo "Control node instance ID: ${control_node_instance_id}"

# Stream logs from the startup script execution to stdout in the background
gcloud beta logging tail \
"resource.type=gce_instance AND \
resource.labels.instance_id=${control_node_instance_id} \
AND log_name=projects/${project}/logs/google_metadata_script_runner" \
--format='value(timestamp, json_payload.message)' &

tail_pid=$!

sleep_seconds=60
timeout_seconds=7200
timeout_hours="$((timeout_seconds / 3600))"
timeout_minutes="$(((timeout_seconds % 3600) / 60))"
start_time="$(date +%s)"

echo "Waiting up to ${timeout_hours} hours and ${timeout_minutes} minutes for control node's startup script to complete..."

while true; do
  current_time="$(date +%s)"
  elapsed="$((current_time - start_time))"

  if [[ "${elapsed}" -ge "${timeout_seconds}" ]]; then
    echo "Timeout reached after ${timeout_hours} hours and ${timeout_minutes} minutes. No completion log found."
    exit 1
  fi

  result="$(gcloud logging read \
    "resource.type=global AND \
    log_name=projects/${project}/logs/Ansible_logs AND \
    jsonPayload.deployment_name=${deployment_name} AND \
    jsonPayload.event_type=ANSIBLE_RUNNER_SCRIPT_END" \
    --order=desc \
    --limit=1 \
    --format=json)"

  state="$(echo "${result}" | jq -r '.[0].jsonPayload.state // empty')"

  if [[ "${state}" == "ansible_completed_success" ]]; then
    echo "Control node's startup script completed successfully."
    exit 0
  elif [[ "${state}" == "ansible_completed_failure" ]]; then
    echo "Control node's startup script failed."
    exit 1
  fi

  sleep "${sleep_seconds}"
done
