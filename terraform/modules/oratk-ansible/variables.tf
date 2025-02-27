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

variable "region" {
  description = "The GCP region where the instance and related resources will be deployed (e.g., us-central1)."
  type        = string
}

variable "zone" {
  description = "The specific availability zone within the selected GCP region (e.g., us-central1-b)."
  type        = string
}

variable "project" {
  description = "The Google Cloud project ID where all resources will be deployed."
  type        = string
}

variable "subnetwork" {
  description = "The name of the GCP subnetwork to which the instance will be attached."
  type        = string
}

variable "network_tags" {
  description = "List of network tags to apply to the instance template."
  type        = list(string)
  default     = []
}

variable "service_account_email" {
  description = "The service account email used for managing compute instance permissions."
  type        = string
}

variable "instance_name" {
  description = "The name for the Instance."
  type        = string
}
variable "image" {
  description = "Image to be used from the image_map."
  type        = string
}

variable "instance_count" {
  description = "Number of instances to be created."
  type        = number
}

variable "fs_disks" {
  description = "List of filesystem disks"
  type        = list(any)
  default     = []
}

variable "asm_disks" {
  description = "List of ASM disks"
  type        = list(any)
  default     = []
}

variable "base_disk_size" {
  description = "The size (in GB) of the base disk for the instance."
  type        = number
  default     = 50
}
variable "ssh_public_key_path" {
  description = "The local file path to the public SSH key used for connecting to the instance."
  type        = string
}

variable "ssh_private_key_path" {
  description = "The local file path to the private SSH key used for connecting to the instance."
  type        = string
}

variable "image_map" {
  description = "A mapping of OS labels to their corresponding Google Cloud image paths."
  type        = map(string)
}

variable "machine_type" {
  description = "The machine type to be used for the instance (e.g., n1-standard-2)."
  type        = string
}

variable "extra_ansible_vars" {
  description = "Extra parameters to pass to the install-oracle.sh script."
  type        = list(string)
  default     = []
}

variable "metadata_startup_script" {
  description = "The startup script to be executed on the instance, bootstraps required Ansible binaries."
  type        = string
  default     = null
}
