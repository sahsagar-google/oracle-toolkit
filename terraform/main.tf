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

module "oratk_ansible" {
  source = "./modules/oratk-ansible"

  region                = var.region
  zone                  = var.zone
  project               = var.project_id
  subnetwork            = var.subnet
  service_account_email = var.service_account_email

  image_map = {
    rhel7  = "projects/rhel-cloud/global/images/rhel-7-v20240611"
    alma8  = "projects/almalinux-cloud/global/images/almalinux-8-v20241009"
    rhel8  = "projects/rhel-cloud/global/images/rhel-8-v20241210"
    rocky8 = "projects/rocky-linux-cloud/global/images/rocky-linux-8-v20250114"
  }

  instance_name  = "oracle-test"
  instance_count = 1
  image          = "rhel8"
  machine_type   = "n2-standard-4"
  #metadata_startup_script = "gs://BUCKET/SCRIPT.sh"  # Optional - use only if required
  network_tags = ["oracle", "ssh"] # Optional - use only if required

  base_disk_size = 50

  fs_disks = [
    {
      auto_delete  = true
      boot         = false
      device_name  = "oracle-fs-1"
      disk_size_gb = 50
      disk_type    = "pd-balanced"
      disk_labels  = { purpose = "fs" }
    },
    {
      auto_delete  = true
      boot         = false
      device_name  = "swap"
      disk_size_gb = 16
      disk_type    = "pd-balanced"
      disk_labels  = { purpose = "swap" }
    }
  ]

  asm_disks = [
    {
      auto_delete  = true
      boot         = false
      device_name  = "oracle-asm-1"
      disk_size_gb = 50
      disk_type    = "pd-balanced"
      disk_labels  = { diskgroup = "data", purpose = "asm" }
    },
    {
      auto_delete  = true
      boot         = false
      device_name  = "oracle-asm-2"
      disk_size_gb = 50
      disk_type    = "pd-balanced"
      disk_labels  = { diskgroup = "reco", purpose = "asm" }
    }
  ]

  ssh_public_key_path  = abspath("${path.module}/ansible-ssh-key.pub")
  ssh_private_key_path = abspath("${path.module}/ansible-ssh-key")

  extra_ansible_vars = [
    "--ora-swlib-bucket gs://BUCKET",
    "--ora-version 19",
    "--backup-dest +RECO"
  ]
}
