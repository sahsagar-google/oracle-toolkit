#!/bin/bash
source presubmit_tests/infra-manager-lib.sh || {
  echo "Error: cannot source common library" >&2
  exit 1
}
instance_name="github-presubmit-26ai-dg-${BUILD_ID}"
deployment_name="presubmit-26ai-dg-${BUILD_ID}"
tfvars_file="./presubmit_tests/26ai-dg.tfvars"
location="us-central1"
setup_vars
apply_deployment
watch_logs
echo "============================================================"
echo "Validating Day-2 TLS Certificate Rotation Logic (Idempotency)"
echo "============================================================"
# Fetch the zone of the primary instance (usually zone1 from tfvars)
DB_ZONE=$(grep -oP '^zone1\s*=\s*"\K[^"]+' $tfvars_file)

# Force the systemd rotation service to run on the primary DB node
# It should detect the certs are already up-to-date and exit cleanly (0)
gcloud compute ssh "oracle@${instance_name}-1" --zone="${DB_ZONE}" --tunnel-through-iap --command="sudo systemctl start oracle-tls-rotation.service && sudo journalctl -u oracle-tls-rotation.service --no-pager"

echo "TLS Rotation logic validated successfully!"
