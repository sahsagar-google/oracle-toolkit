# Oracle Toolkit for GCP - GCE User Guide

The Oracle Toolkit for GCP fully supports running on Google Compute Engine (GCE) "instances" (or virtual machines). The only restriction is Oracle RAC, which due to it's shared storage, and networking requirements, is only deployable with this toolkit to Google Bare Metal Solution (BMS). However, this toolkit does support installing and configuring all other editions and configurations on GCE instances.

This includes using Oracle Grid Infrastructure (GI) and Automatic Storage Management (ASM), with single-instance databases.

## Things to do in Advance - Prerequisites

Outside of the scope of this document is the setup of Google Cloud foundational components such as Cloud IAM, networking (VPCs and subnets), Google Cloud Storage (GCS) buckets and cloud security. Setting up the required Google Cloud project and billing account is similarly outside of the scope of this document.

The remainder of this guide assumes that those foundational components are in place.

## What's Different with GCE?

Running Oracle Databases on Google Cloud Engine (GCE) VMs has many advantages. Including but not limited to:

- General Google Cloud benefits such as a wide variety of regions and zones, predictable costs, consumption based charges, and rapid provisioning/decommissioning of infrastructure.
- Dynamically sizable VM instances: change VM shapes, even for existing VM instances, as required.
- The inherent snapshotting, cloning, and replication benefits of using Google Cloud Persistent Disks and/or Hyperdisks for software and database (ASM) storage.
- Easy to reference block devices from Linux via the Google `/dev/disk/by-id` device aliases

For multi-node RAC configurations, deploying on Google BMS is recommended.

## Initial Requirements

All that's typically required to get started is an **Ansible Control Node** and the Google Cloud CLI - specifically, the **gcloud** utility. (Or Terraform as an alternative to **glcoud**.)

Usually both pieces of software are on the same computer, but they don't have to be. The Ansible Control Node can be an administrator's physical workstation (i.e. laptop), another cloud VM, or could even be the Google Cloud Cloud Shell. However, due to the somewhat ephemeral nature of Cloud Shell, this option is probably not recommended.

Google Cloud instances for running Oracle Databases can be provisioned using:

1. The Google Cloud Web Console:
   - For consistency, ease of deployment, and repeatability (without error), this option is generally not recommended
1. Terraform:
   - Covered in detail in the complementary document [Terraform Infrastructure Provisioning for Oracle Toolkit for GCP Deployments](../terraform/README.md)
1. Google Cloud CLI (**gcloud**) commands:
   - This guide will focus on this option

### Ansible Control Node Provisioning & Setup

Your Ansible Control Node can be virtually any Ansible supported operating system. Install Ansible via typical methods. See the [Installing Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) section of the official Ansible documentation for additional details.

> **NOTE:** Ansible version 2.9 or higher is required.

For example, in Debian-based Linux distributions:

```bash
sudo apt update && sudo apt install -y ansible
```

Similarly, in Enterprise Linux derivative distributions:

```bash
sudo yum install -y epel-release
sudo yum install -y ansible
```

Install jmespath (for the same Python3 version that Ansible is using). For example, installing into a Python virtual environment:

```bash
python3 -m venv venv
source venv/bin/activate

pip3 install --upgrade pip
pip3 install jmespath
pip3 list | grep jmespath
```

Then either clone, or download the Oracle Toolkit for Google from it's source site.

For example, to clone the public repo, assuming that the `git` package is installed on your Ansible Control Node use:

```bash
git clone https://github.com/google/oracle-toolkit.git
```

Or alternatively, to download, without Git, simply use:

```bash
wget https://github.com/google/oracle-toolkit/archive/refs/heads/master.zip && \
  unzip ./master.zip && \
  rm ./master.zip && \
  mv oracle-toolkit-master oracle-toolkit
```

## GCE Instance Provisioning

GCE instances for running Oracle databases can be provisioned using Terraform by following the steps outlined in the [Terraform Infrastructure Provisioning for Oracle Toolkit for GCP Deployments](../terraform/README.md) guide.

Alternatively, they can be provisioned quickly and efficiently using the **gcloud** utility from the Google Cloud CLI. To install the **gcloud** utility follow the [Install the gcloud CLI](https://cloud.google.com/sdk/docs/install) instructions.

Before provisioning actual GCE instances, fundamentals such as the Google Cloud project, region, zone, network, and subnet should be chosen. For convenience in future commands, it is easiest to set these as environment variables:

```bash
PROJECT_ID=PROJECT_ID
REGION_ID=REGION
ZONE_ID=ZONE
NETWORK_ID=NETWORK
SUBNET_ID=SUBNET

gcloud config set project ${PROJECT_ID}
```

### Instance Sizing, Performance Characteristics, and OS Image

Choosing the VM shape is of importance, but also can be adjusted post deployment if required.

Oracle databases usually require multiple CPUs and at least 8GB of memory when running Grid Infrastructure. See the Oracle [Database Installation Guide for Linux - Server Hardware Checklist for Oracle Database Installation](https://docs.oracle.com/en/database/oracle/oracle-database/23/ladbi/server-hardware-checklist-for-oracle-database-installation.html) for specific requirements. Oracle licensing may also require consideration when choosing the VM shape and specifically the number of CPUs or vCPUs.

While Oracle database can run on a wide variety of virtual machine families and types, the C4 series is often used. However, depending on your use case, other families and types may be more suitable for your Oracle database workload. For additional details, see the Google [Machine families resource and comparison guide](https://cloud.google.com/compute/docs/machine-resource).

For convenience, specify your chosen virtual machine type as a variable. For example:

```bash
MACHINE_TYPE="c4-standard-4"
```

Choose a supported operating system image (either one of the Google Cloud public images, or your own if uploaded and prepared separately).

> **NOTE:** Some operating systems such as Red Hat Enterprise Linux may have additional licensing costs. See the [Premium images](https://cloud.google.com/compute/disks-image-pricing?hl=en#section-1) section of Google documentation for additional details.

For example, if choosing a Red Hat Enterprise Linux (RHEL) 8 image:

```bash
IMAGE_FILE="$(gcloud compute images describe-from-family rhel-8 --project=rhel-cloud --format json | jq -r '.selfLink')"
```

### Database Server (GCE Instance) Provisioning

With these prerequisites in place, the VM can be easily configured using the Google Cloud CLI **gcloud** utility.

For example (review command carefully and adjust as required before using):

```bash
VM_NAME=INSTANCE_NAME

gcloud compute instances create ${VM_NAME} \
  --project=${PROJECT_ID} \
  --zone=${ZONE_ID} \
  --machine-type=${MACHINE_TYPE} \
  --network-interface=network-tier=STANDARD,stack-type=IPV4_ONLY,subnet=${SUBNET_ID} \
  --create-disk=auto-delete=yes,boot=yes,device-name=${VM_NAME}-boot-disk,image=${IMAGE_FILE},mode=rw,provisioned-iops=3300,provisioned-throughput=290,size=64G,type=hyperdisk-balanced
```

Include other optional components such as `--tags` and `--metadata=startup-script-url` if, and as required.

A boot disk size of `64G` is typically sufficient for most installations, however customize this size to a larger value if your use case requires.

After provisioning, consider networking, cloud firewalls, and private vs public IP addresses for the new instance. Ingress from the Ansible Control Node is mandatory and egress to the internet (for package installation), whether directly or indirectly through a Google Cloud Router and NAT Gateway, is typically required.

If necessary, the assigned IP address can be obtained from the Google Cloud web console, the VM instance itself, or using the **gcloud** command:

```bash
INSTANCE_IP_ADDR=$(gcloud compute instances describe ${VM_NAME} --zone=${ZONE_ID} --format="value(networkInterfaces[0].networkIP)")
```

### Adding Google Cloud Disks (Block Storage)

GCE Block Storage devices including Persistent Disks (PD) or Hyperdisks can be added in virtually any size with any performance characteristic. To be used as additional Linux journald file systems such as `/u01` and `/u02` or for ASM storage. As many disks of whatever shapes and sizes is required can be added.

To create a cloud disk, first choose a disk name:

```bash
DISK_NAME=DISK_NAME
```

Then choose the disk size and performance characteristics (customize as necessary):

```bash
DISK_SIZE=64G
DISK_TYPE=hyperdisk-balanced
DISK_PERFORMANCE="--provisioned-iops=3300 --provisioned-throughput=290"
```

Next, create the cloud disk, add it to the VM instance, and if desired, make the disk auto-delete (customize as necessary):

```bash
gcloud compute disks create ${VM_NAME}-${DISK_NAME} --size=${DISK_SIZE} --type=${DISK_TYPE} ${DISK_PERFORMANCE} --zone=${ZONE_ID}
gcloud compute instances attach-disk ${VM_NAME} --disk=${VM_NAME}-${DISK_NAME} --device-name=oracle-${DISK_NAME} --zone=${ZONE_ID}
gcloud compute instances set-disk-auto-delete ${VM_NAME} --auto-delete --disk=${VM_NAME}-${DISK_NAME} --zone=${ZONE_ID}
```

Repeat as necessary. For example, adding as many block storage devices are required to add to your ASM disk groups.

### Recoding Block Storage in JSON Format for Toolkit Usage

The Oracle Toolkit for GCP requires block storage (or disk) information in JSON format - provided either via JSON configuration files, or as command line arguments to the installation shell script.

Consequently, after creating each, it's usually convenient to record their metadata and property as a JSON object.

For example, for ASM disks:

```bash
DISK_JSON_OBJECT=$(echo '
{
  "diskgroup": "DATA",
  "disks": [
    {
      "blk_device": "/dev/disk/by-id/google-'${DISK_NAME}'",
      "name": "'${DISK_NAME}'"
    }
  ]
}' | jq -r -c '.') && echo "${DISK_JSON_OBJECT}"
```

Then add the contents of `$DISK_JSON_OBJECT` to your `asm_disk_config.json` or `data_mounts_config.json`, back in pretty format using: `echo ${DISK_JSON_OBJECT} | jq -r '.'` or use in your `--ora-data-mounts-json` or `--ora-asm-disks-json` command line arguments in the existing compact format.

### Automating for Efficiency

If desired, the above provided **gcloud** utility steps and commands can easily be combined into a shell script, perhaps including some aspects such as the _`VM_NAME`_ as input arguments, and then run programmatically for ease of use and to provide reliable and consistent results.

## Running the Toolkit

### SSH Key Exchange

Before the toolkit can be used, ssh connectivity must be established with an ssh key exchange. An existing, or new (and perhaps toolkit dedicated) ssh key pair can be used.

If required, create an ssh key pair using your internal standards (i.e. for encryption algorithm, comment standards, etc). Example command to create a new key-pair for usage with this toolkit using common settings:

```bash
ssh-keygen -q -b 4096 -t rsa -N '' -C 'oracle-toolkit-for-oracle' -f "${HOME}/.ssh/id_rsa_oracle_toolkit" <<<y
```

Then copy the desired public key to your newly created GCE VM instance:

```bash
ssh-copy-id -i "${HOME}/.ssh/id_rsa_oracle_toolkit" ${INSTANCE_IP_ADDR}
```

### Toolkit Execution

Overall, running the toolkit against a GCE VM instance is really no different to running against a BMS physical or virtualized server. Assuming that the required block storage disk details have been properly specified in the required JSON configuration files and using the `--ora-data-mounts` and `--ora-asm-disks`, or are specified as command line arguments using the `--ora-data-mounts-json` and `--ora-asm-disks-json` arguments.

While GI and ASM are fully supported, the quickest and easiest start is usually to deploy Free Edition for familiarity with the toolkit and it's operation. Then complement with full EE or SE2 installations.

For example, the simplest command to create a Free Edition database:

```bash
./install-oracle.sh \
  --instance-ip-addr ${INSTANCE_IP_ADDR} \
  --instance-ssh-key "${HOME}/.ssh/id_rsa_oracle_toolkit" \
  --ora-edition free \
  --ora-swlib-bucket gs://BUCKET_NAME \
  --ora-data-mounts-json '[{"purpose":"software","blk_device":"/dev/disk/by-id/google-oracle-disk-1","name":"u01","fstype":"xfs","mount_point":"/u01","mount_opts":"nofail"}]' \
  --backup-dest /opt/oracle/fast_recovery_area/FREE
```

Or to create an Enterprise Edition database:

```bash
./install-oracle.sh \
  --instance-ip-addr ${INSTANCE_IP_ADDR} \
  --instance-ssh-key "${HOME}/.ssh/id_rsa_oracle_toolkit" \
  --ora-version 19 \
  --ora-swlib-bucket gs://BUCKET_NAME \
  --ora-swlib-path /u01/oracle_install \
  --ora-data-mounts-json '[{"purpose":"software","blk_device":"/dev/disk/by-id/google-oracle-disk-1","name":"u01","fstype":"xfs","mount_point":"/u01","mount_opts":"nofail"}]' \
  --ora-asm-disks-json '[{"diskgroup":"DATA","disks":[{"blk_device":"/dev/disk/by-id/google-oracle-asm-data-1","name":"DATA1"}]},{"diskgroup":"RECO","disks":[{"blk_device":"/dev/disk/by-id/google-oracle-asm-reco-1","name":"RECO1"}]}]' \
  --ora-db-name ORCL
```

### Cleanup

The one key difference from BMS is that GCE instances can be destroyed quickly and easily in a variety of ways, including using **gcloud**. For example:

```bash
gcloud compute instances delete ${VM_NAME} --zone=${ZONE_ID}
```

## Integration with Other Google Cloud Services

### Monitoring and Logging

Oracle databases on GCE instances are "self-managed" and therefore have no _automatically integrated_ connections to other Google Cloud services such as the Logging or Monitoring services. (Automatic integration is included with other, "fully-managed" services such as the Exadata and ADM offerings through the [Oracle on Google Cloud](https://cloud.google.com/solutions/oracle).)

However, when running in GCE instances, some integration options are available including using the Google Cloud Ops Agent to collect Oracle Database metrics and log data for use in Google Cloud Metrics Explorer and Logs Explorer. For setup and configuration details, refer to the [Oracle Database](https://cloud.google.com/logging/docs/agent/ops-agent/third-party/oracledb) documentation for Google Cloud Observability integration with third party apps. This toolkit does not automatically setup this component.

### Backups

This toolkit includes some initial RMAN backup scripts which can be used to write both FULL DATABASE and ARCHIVELOG RMAN backups to various destinations including local file system storage, an ASM disk group, or even a Google Cloud Storage (GCS) bucket. For backup script setup, refer to the main [user guide](../docs/user-guide.md).
