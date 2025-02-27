# Quickstart for Using the Oracle Toolkit for GCP on GCE

This document serves as a quickstart guide and simple reference for using the Oracle Toolkit for GCP on Google Compute Enging (GCE). It is an abridged version of the more comprehensive [Oracle Toolkit for GCP - GCE User Guide](gce-user-guide.md).

## Prerequisite Assumptions

This document assumes that you have:

1. Provisioned your Ansible Control Node, installed Ansible and JMESpath on it, and downloaded the toolkit.
1. Setup Google Cloud foundational components such as IAM, networking, GSC storage buckets with the required media staged, and security aspects.
1. Have either Terraform or the Google Cloud CLI and specifically the **gcloud** utility installed.

If you need additional details to setup any of these prerequisites, refer to Google documentation such as [Google Cloud quickstarts and tutorials](https://cloud.google.com/docs/tutorials) and specifically [Install the gcloud CLI](https://cloud.google.com/sdk/docs/install).

## Deploying using the Google Cloud CLI

### Set Supporting Variables

Before beginning, infrastructure locality and networking aspects must be defined and captured (i.e. into shell environment variables for convenience):

```bash
PROJECT_ID=PROJECT_ID
REGION_ID=REGION
ZONE_ID=ZONE
NETWORK_ID=NETWORK
SUBNET_ID=SUBNET

gcloud config set project ${PROJECT_ID}
```

### Create the GCE Instance and Block Storage Devices

Specify some instance specific characteristics such as the VM shape, name, and OS image:

```bash
MACHINE_TYPE="c4-standard-4"
IMAGE_FILE="$(gcloud compute images describe-from-family rhel-8 --project=rhel-cloud --format json | jq -r '.selfLink')"
VM_NAME=INSTANCE_NAME
```

> **NOTE:** Some operating systems such as Red Hat Enterprise Linux may have additional licensing costs. See the [Premium images](https://cloud.google.com/compute/disks-image-pricing?hl=en#section-1) section of Google documentation for additional details.

Create the instance (add network tags by appending the `--tags TAG` option as required):

```bash
gcloud compute instances create ${VM_NAME} \
  --project=${PROJECT_ID} \
  --zone=${ZONE_ID} \
  --machine-type=${MACHINE_TYPE} \
  --network-interface=network-tier=STANDARD,stack-type=IPV4_ONLY,subnet=${SUBNET_ID} \
  --create-disk=auto-delete=yes,boot=yes,device-name=${VM_NAME}-boot-disk,image=${IMAGE_FILE},mode=rw,provisioned-iops=3300,provisioned-throughput=290,size=64G,type=hyperdisk-balanced
```

Capture the IP address of the newly created instance:

```bash
INSTANCE_IP_ADDR=$(gcloud compute instances describe ${VM_NAME} --zone=${ZONE_ID} --format="value(networkInterfaces[0].networkIP)")
```

Create and attach the desired cloud block storage devices or "disks". Assuming one 64GB disk for the `/u01` file system, and a 500GB disk for each of the ASM `DATA` and `RECO` disk groups:

```bash
gcloud compute disks create ${VM_NAME}-disk-1 --size=64 --type=hyperdisk-balanced --provisioned-iops=3300 --provisioned-throughput=290 --zone=${ZONE_ID}
gcloud compute instances attach-disk ${VM_NAME} --disk=${VM_NAME}-disk-1 --device-name=oracle-disk-1 --zone=${ZONE_ID}
gcloud compute instances set-disk-auto-delete ${VM_NAME} --auto-delete --disk=${VM_NAME}-disk-1 --zone=${ZONE_ID}

gcloud compute disks create ${VM_NAME}-asm-data-1 --size=500G --type=hyperdisk-balanced --provisioned-iops=3300 --provisioned-throughput=290 --zone=${ZONE_ID}
gcloud compute disks create ${VM_NAME}-asm-reco-1 --size=500G --type=hyperdisk-balanced --provisioned-iops=3300 --provisioned-throughput=290 --zone=${ZONE_ID}
gcloud compute instances attach-disk ${VM_NAME} --disk=${VM_NAME}-asm-data-1 --device-name=oracle-asm-data-1 --zone=${ZONE_ID}
gcloud compute instances attach-disk ${VM_NAME} --disk=${VM_NAME}-asm-reco-1 --device-name=oracle-asm-reco-1 --zone=${ZONE_ID}
gcloud compute instances set-disk-auto-delete ${VM_NAME} --auto-delete --disk=${VM_NAME}-asm-data-1 --zone=${ZONE_ID}
gcloud compute instances set-disk-auto-delete ${VM_NAME} --auto-delete --disk=${VM_NAME}-asm-reco-1 --zone=${ZONE_ID}
```

### Setup SSH Connectivity

If required, generate a new and dedicated ssh key-pair (using your internal or organizational ssh key standards for properties such as key file names, encryption algorithm used, etc).

Example command:

```bash
ssh-keygen -q -b 4096 -t rsa -N '' -C 'oracle-toolkit-for-oracle' -f "${HOME}/.ssh/id_rsa_oracle_toolkit" <<<y
```

Then copy your pre-existing, or newly created public key to your newly created GCE VM instance. Example command:

```bash
ssh-copy-id -i "${HOME}/.ssh/id_rsa_oracle_toolkit" ${INSTANCE_IP_ADDR}
```

### Install the Oracle Software and Create a Database

Using the toolkit, all software installation and configuration, and database instance creation steps can be run from a single command.

While the toolkit support many options allowing for many permutations and configuration, getting started (while relying on many default values) can be as simple as:

```bash
./install-oracle.sh \
  --instance-ip-addr ${INSTANCE_IP_ADDR} \
  --instance-ssh-key "${HOME}/.ssh/id_rsa_oracle_toolkit" \
  --ora-version 19 \
  --ora-swlib-bucket gs://[cloud-storage-bucket-name] \
  --ora-swlib-path /u01/oracle_install \
  --ora-data-mounts-json '[{"purpose":"software","blk_device":"/dev/disk/by-id/google-oracle-disk-1","name":"u01","fstype":"xfs","mount_point":"/u01","mount_opts":"nofail"}]' \
  --ora-asm-disks-json '[{"diskgroup":"DATA","disks":[{"blk_device":"/dev/disk/by-id/google-oracle-asm-data-1","name":"DATA1"}]},{"diskgroup":"RECO","disks":[{"blk_device":"/dev/disk/by-id/google-oracle-asm-reco-1","name":"RECO1"}]}]' \
  --ora-db-name ORCL
```

## Deploying using Terraform

The required database infrastructure can also be provisioned, including execution of this toolkit, using Terraform.

To deploy using Terraform:

1. Edit the [terraform/backend.tf](../terraform/backend.tf) document and update the backend GCS `bucket` and `prefix` values indicating where your Terraform state file is stored.
2. Edit the [terraform/main.tf](../terraform/main.tf) document and customize all key-value pairs as necessary. Including adding and resizing ASM disks as required.

Then run the Terraform using:

```bash
cd terraform

terraform init
terraform plan
terraform apply
```

And if required, remove using:

```bash
terraform destroy
```

For full details, refer to the [Terraform Infrastructure Provisioning for Oracle Toolkit for GCP Deployments](../terraform/README.md) document.
