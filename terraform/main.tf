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
  # ---- Mode helper
  is_fs              = upper(var.ora_disk_mgmt) == "FS"
  ora_disk_mgmt_flag = upper(var.ora_disk_mgmt)

  # ---- Base disk definitions (do not change device_name values)
  _u01 = {
    auto_delete  = true
    device_name  = "oracle_home"
    disk_size_gb = var.oracle_home_disk.size_gb
    disk_type    = var.oracle_home_disk.type
    disk_labels  = { purpose = "software" }
  }

  # DATA / RECO in ASMUDEV and ASMLIB mode (with disk groups)
  _data_asm = {
    auto_delete  = true
    device_name  = "data"
    disk_size_gb = var.data_disk.size_gb
    disk_type    = var.data_disk.type
    disk_labels  = { diskgroup = "data", purpose = "asm" }
  }
  _reco_asm = {
    auto_delete  = true
    device_name  = "reco"
    disk_size_gb = var.reco_disk.size_gb
    disk_type    = var.reco_disk.type
    disk_labels  = { diskgroup = "reco", purpose = "asm" }
  }

  # DATA / RECO in FS mode
  _data_fs = {
    auto_delete  = true
    device_name  = "data"
    disk_size_gb = var.data_disk.size_gb
    disk_type    = var.data_disk.type
    disk_labels  = { purpose = "data" }
  }
  _reco_fs = {
    auto_delete  = true
    device_name  = "reco"
    disk_size_gb = var.reco_disk.size_gb
    disk_type    = var.reco_disk.type
    disk_labels  = { purpose = "reco" }
  }

  _swap = {
    auto_delete  = true
    device_name  = "swap"
    disk_size_gb = var.swap_disk_size_gb
    disk_type    = var.swap_disk_type
    disk_labels  = { purpose = "swap" }
  }

  # ---- Build lists based on mode
  # Filesystem disks (participate in XFS mounts via data_mounts_config)
  fs_disks = concat(
    [
      local._u01
    ],
    local.is_fs ? [local._data_fs, local._reco_fs] : []
  )

  asm_disks = concat(
    local.is_fs ? [] : [local._data_asm, local._reco_asm],
    [local._swap]
  )

  # ---- DBCA destinations
  data_dest    = local.is_fs ? "/u02/oradata" : "DATA"
  reco_dest = local.is_fs ? "/u03/fast_recovery_area" : "RECO"

  # Takes the list of filesystem disks and converts them into a list of objects with the required fields by ansible
  data_mounts_config = [
    for i, d in local.fs_disks : {
      purpose     = d.disk_labels.purpose
      blk_device  = "/dev/disk/by-id/google-${d.device_name}"
      name        = format("u%02d", i + 1)
      fstype      = "xfs"
      mount_point = format("/u%02d", i + 1)
      mount_opts  = "nofail"
    }
  ]

  # Takes the list of asm disks and converts them into a list of objects with the required fields by ansible
  asm_disk_config = [
    for g in distinct([for d in local.asm_disks : d.disk_labels.diskgroup if lookup(d.disk_labels, "diskgroup", null) != null]) : {
      diskgroup = upper(g)
      disks = [
        for d in local.asm_disks : {
          blk_device = "/dev/disk/by-id/google-${d.device_name}"
          name       = d.device_name
        } if lookup(d.disk_labels, "diskgroup", null) == g
      ]
    }
  ]

  # Metadata
  disk_metadata = {
    "ora-disk-mgmt"            = upper(var.ora_disk_mgmt) # "FS" or "ASMUDEV" or "ASMLIB"
    "ora-data-dest"            = local.data_dest          # "/u02/oradata" or "+DATA"
    "ora-reco-dest"            = local.reco_dest          # "/u03/fast_recovery_area" or "+RECO"
    "ora-data-mounts-json"     = jsonencode(local.data_mounts_config)
    "ora-asm-disk-config-json" = local.is_fs ? "" : jsonencode(local.asm_disk_config)
  }

  # Concatenetes both lists to be passed down to the instance module
  additional_disks = concat(local.fs_disks, local.asm_disks)

  project_id = var.project_id

  subnetwork1_opt = var.subnetwork1 != "" ? var.subnetwork1 : null
  subnetwork2_opt = var.subnetwork2 != "" ? var.subnetwork2 : null

  is_multi_instance = (var.zone1 != "" && var.zone2 != "")

  instances = local.is_multi_instance ? {
    "${var.instance_name}-1" = {
      zone       = var.zone1
      subnetwork = local.subnetwork1_opt
      role       = "primary"
    }
    "${var.instance_name}-2" = {
      zone       = var.zone2
      subnetwork = local.subnetwork2_opt
      role       = "standby"
    }
    } : {
    "${var.instance_name}-1" = {
      zone       = var.zone1
      subnetwork = local.subnetwork1_opt
      role       = "primary"
    }
  }
}

data "google_compute_image" "os_image" {
  family  = var.source_image_family
  project = var.source_image_project
}

resource "time_static" "template_suffix" {}

locals {
  template_suffix = formatdate("YYYYMMDDhhmmss", time_static.template_suffix.rfc3339)
}

resource "google_compute_instance_template" "default" {
  name         = "${var.instance_name}-${local.template_suffix}"
  project      = var.project_id
  machine_type = var.machine_type

  network_interface {
  
  subnetwork = local.subnetwork1_opt
  network    = local.subnetwork1_opt == null ? "projects/${var.project_id}/global/networks/default" : null
}
  disk {
    boot         = true
    auto_delete  = true
    source_image = data.google_compute_image.os_image.self_link
    disk_type    = var.boot_disk_type
    disk_size_gb = var.boot_disk_size_gb
  }

  dynamic "disk" {
    for_each = local.additional_disks
    content {
      boot         = false
      auto_delete  = disk.value.auto_delete
      device_name  = disk.value.device_name
      disk_size_gb = disk.value.disk_size_gb
      disk_type    = disk.value.disk_type
      labels       = disk.value.disk_labels
    }
  }

  service_account {
    email  = var.vm_service_account
    scopes = ["cloud-platform"]
  }

  metadata = {
    metadata_startup_script = var.metadata_startup_script
    enable-oslogin          = "TRUE"
  }

  tags = var.network_tags
}

resource "google_compute_instance_from_template" "database_vm" {
  for_each = local.instances

  name                     = each.key
  zone                     = each.value.zone
  project                  = var.project_id
  source_instance_template = google_compute_instance_template.default.self_link

  network_interface {
  # Provide one of: subnetwork (preferred) OR default network
  subnetwork = each.value.subnetwork
  network    = each.value.subnetwork == null ? "projects/${var.project_id}/global/networks/default" : null

    dynamic "access_config" {
      for_each = var.assign_public_ip ? [1] : []
      content {}
    }
  }

}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  database_vm_nodes = [
    for vm in google_compute_instance_from_template.database_vm : {
      name = vm.name
      zone = vm.zone
      ip   = vm.network_interface[0].network_ip
      role = local.instances[vm.name].role
    }
  ]
}

locals {
  common_flags = join(" ", compact([
    local.ora_disk_mgmt_flag != "" ? "--ora-disk-mgmt ${local.ora_disk_mgmt_flag}" : "",
    length(local.asm_disk_config) > 0 ? "--ora-asm-disks-json '${jsonencode(local.asm_disk_config)}'" : "",
    length(local.data_mounts_config) > 0 ? "--ora-data-mounts-json '${jsonencode(local.data_mounts_config)}'" : "",
    # Keep DBCA destinations aligned with the computed mode
    "--ora-data-dest ${local.data_dest}",
    "--ora-reco-dest ${local.reco_dest}",
    "--swap-blk-device /dev/disk/by-id/google-swap",
    "--is-terraform-run",
    var.ora_swlib_bucket != "" ? "--ora-swlib-bucket ${var.ora_swlib_bucket}" : "",
    var.ora_version != "" ? "--ora-version ${var.ora_version}" : "",
    var.ora_backup_dest != "" ? "--backup-dest ${var.ora_backup_dest}" : "",
    var.ora_db_name != "" ? "--ora-db-name ${var.ora_db_name}" : "",
    var.ora_db_container != "" ? "--ora-db-container ${var.ora_db_container}" : "",
    var.ntp_pref != "" ? "--ntp-pref ${var.ntp_pref}" : "",
    var.ora_release != "" ? "--ora-release ${var.ora_release}" : "",
    var.ora_edition != "" ? "--ora-edition ${var.ora_edition}" : "",
    var.ora_listener_port != "" ? "--ora-listener-port ${var.ora_listener_port}" : "",
    var.ora_redo_log_size != "" ? "--ora-redo-log-size ${var.ora_redo_log_size}" : "",
    var.db_password_secret != "" ? "--db-password-secret ${var.db_password_secret}" : "",
    var.oracle_metrics_secret != "" ? "--oracle-metrics-secret ${var.oracle_metrics_secret}" : "",
    var.install_workload_agent ? "--install-workload-agent" : "",
    var.skip_database_config ? "--skip-database-config" : "",
    var.ora_pga_target_mb != "" ? "--ora-pga-target-mb ${var.ora_pga_target_mb}" : "",
    var.ora_sga_target_mb != "" ? "--ora-sga-target-mb ${var.ora_pga_target_mb}" : "",
    var.data_guard_protection_mode != "" ? "--data-guard-protection-mode '${var.data_guard_protection_mode}'" : ""
  ]))
}

resource "google_compute_instance" "control_node" {
  project      = var.project_id
  name         = "${var.control_node_name_prefix}-${random_id.suffix.hex}"
  machine_type = var.control_node_machine_type
  zone         = var.zone1

  scheduling {
    max_run_duration {
      seconds = 604800
    }
    instance_termination_action = "DELETE"
  }

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
  subnetwork         = local.subnetwork1_opt
  network            = local.subnetwork1_opt == null ? "projects/${var.project_id}/global/networks/default" : null
  subnetwork_project = local.subnetwork1_opt != null ? local.project_id : null

    dynamic "access_config" {
      for_each = var.assign_public_ip ? [1] : []
      content {}
    }
  }

  service_account {
    email  = var.control_node_service_account
    scopes = ["cloud-platform"]
  }

  lifecycle {
    # FS/ASMUDEV/ASMLIB-specific guard for backup dest
    precondition {
      condition = (
        (local.is_fs && (var.ora_backup_dest == "" || can(regex("^/.*$", var.ora_backup_dest))))
        ||
        (!local.is_fs && (var.ora_backup_dest == "" || can(regex("^\\+.*$", var.ora_backup_dest)) || can(regex("^/.*$", var.ora_backup_dest))))
      )
      error_message = "FS mode: ora_backup_dest must be an absolute path like '/u03/backup'. ASMUDEV/ASMLIB mode: ora_backup_dest must be an ASMUDEV/ASMLIB diskgroup like '+RECO'."
    }
  }

  metadata_startup_script = templatefile("${path.module}/scripts/setup.sh.tpl", {
    gcs_source             = var.gcs_source
    database_vm_nodes_json = jsonencode(local.database_vm_nodes)
    common_flags           = local.common_flags
    deployment_name        = var.deployment_name
    delete_control_node    = var.delete_control_node
  })

  metadata = {
    enable-oslogin = "TRUE"
  }

  depends_on = [google_compute_instance_from_template.database_vm]
}

output "control_node_log_url" {
  description = "Logs Explorer URL with Oracle Toolkit output"
  value       = "https://console.cloud.google.com/logs/query;query=resource.labels.instance_id%3D${urlencode(google_compute_instance.control_node.instance_id)};duration=P30D?project=${urlencode(var.project_id)}"
}

output "database_vm_names" {
  description = "Names of the created database VMs from instance templates"
  value       = [for vm in google_compute_instance_from_template.database_vm : vm.name]
}

