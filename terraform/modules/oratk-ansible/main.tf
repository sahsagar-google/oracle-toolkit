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

locals {
  additional_disks = concat(var.fs_disks, var.asm_disks)

  data_mounts_config = [
    for i, d in var.fs_disks : {
      purpose     = d.disk_labels.purpose
      blk_device  = "/dev/disk/by-id/google-${d.device_name}"
      name        = format("u%02d", i + 1)
      fstype      = "xfs"
      mount_point = format("/u%02d", i + 1)
      mount_opts  = "nofail"
    }
  ]

  asm_disk_config = [
    for g in distinct([for d in var.asm_disks : d.disk_labels.diskgroup]) : {
      diskgroup = upper(g)
      disks = [
        for d in var.asm_disks : {
          blk_device = "/dev/disk/by-id/google-${d.device_name}"
          name       = d.device_name
        } if d.disk_labels.diskgroup == g
      ]
    }
  ]
}

module "instance_template" {
  source  = "terraform-google-modules/vm/google//modules/instance_template"
  version = "~> 13.0"

  name_prefix        = format("%s-template", var.instance_name)
  region             = var.region
  project_id         = var.project
  subnetwork         = var.subnetwork
  subnetwork_project = var.project
  service_account = {
    email  = var.service_account_email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  machine_type = var.machine_type
  source_image = lookup(var.image_map, var.image, null)
  disk_size_gb = var.base_disk_size
  disk_type    = "pd-balanced"
  auto_delete  = true


  metadata = {
    metadata_startup_script = var.metadata_startup_script
    ssh-keys                = "ansible:${file(var.ssh_public_key_path)}"
  }

  additional_disks = local.additional_disks

  tags = var.network_tags
}

module "compute_instance" {
  source  = "terraform-google-modules/vm/google//modules/compute_instance"
  version = "~> 13.0"

  region              = var.region
  zone                = var.zone
  subnetwork          = var.subnetwork
  subnetwork_project  = var.project
  num_instances       = var.instance_count
  hostname            = var.instance_name
  instance_template   = module.instance_template.self_link
  deletion_protection = false

  access_config = [
    {
      nat_ip       = null
      network_tier = "STANDARD"
    }
  ]
}

resource "null_resource" "provisioner" {
  for_each = { for i, instance in module.compute_instance.instances_details : i => instance }

  provisioner "remote-exec" {
    inline = ["echo 'Running Ansible on ${each.value.network_interface[0].access_config[0].nat_ip}'"]

    connection {
      type        = "ssh"
      user        = "ansible"
      private_key = file("${var.ssh_private_key_path}")
      host        = each.value.network_interface[0].access_config[0].nat_ip
    }
  }

  provisioner "local-exec" {
    working_dir = "../"
    command     = <<-EOT
      ./install-oracle.sh \
      --instance-ip-addr ${each.value.network_interface[0].access_config[0].nat_ip} \
      --instance-ssh-user ansible \
      --instance-ssh-key "${var.ssh_private_key_path}" \
      --ora-asm-disks-json '${jsonencode(local.asm_disk_config)}' \
      --ora-data-mounts-json '${jsonencode(local.data_mounts_config)}' \
      $(echo "${join(" ", var.extra_ansible_vars)}") &
    EOT
  }

  depends_on = [module.compute_instance]
}
