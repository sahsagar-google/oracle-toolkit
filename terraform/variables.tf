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

variable "project_id" {
  description = "The Google Cloud project ID where all resources will be deployed."
  type        = string
}

variable "subnet" {
  description = "The name of the GCP subnetwork to which the instance will be attached."
  type        = string
}

variable "service_account_email" {
  description = "The service account email used for managing compute instance permissions."
  type        = string
}

