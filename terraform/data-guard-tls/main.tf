# Copyright 2026 Google LLC
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

# ------------------------------------------------------------------------
# 1. Certificate Authority Service (CAS) Setup
# ------------------------------------------------------------------------

# Create the Private CA Pool
resource "google_privateca_ca_pool" "db_ca_pool" {
  name     = "oracle-db-ca-pool"
  location = var.region
  project  = var.project_id
  tier     = "ENTERPRISE"

  issuance_policy {
    allowed_key_types {
      rsa {
        min_modulus_size = 2048
        max_modulus_size = 4096
      }
    }
    # Enforce that certificates can only be issued for our internal domain
    identity_constraints {
      allow_subject_passthrough           = true
      allow_subject_alt_names_passthrough = false

      cel_expression {
        expression = "subject_alt_names.all(san, san.type == DNS && san.value.endsWith('.internal.corp.com'))"
        title      = "Restrict to internal.corp.com"
      }
    }
  }
}

# Create the Root Certificate Authority within the Pool
resource "google_privateca_certificate_authority" "db_root_ca" {
  pool                     = google_privateca_ca_pool.db_ca_pool.name
  certificate_authority_id = "oracle-db-root-ca"
  location                 = var.region
  project                  = var.project_id

  config {
    subject_config {
      subject {
        organization = "Internal Corp"
        common_name  = "Oracle DB Internal Root CA"
      }
    }
    x509_config {
      ca_options {
        is_ca = true
      }
      key_usage {
        base_key_usage {
          cert_sign = true
          crl_sign  = true
        }
        extended_key_usage {
          server_auth = true
          client_auth = true
        }
      }
    }
  }
  
  key_spec {
    algorithm = "RSA_PKCS1_4096_SHA256"
  }

  # NOTE: Set to true for actual production deployments to prevent accidental deletion
  deletion_protection = false 
}

# ------------------------------------------------------------------------
# 2. Cloud DNS Setup (Private Zone)
# ------------------------------------------------------------------------

resource "google_dns_managed_zone" "db_private_zone" {
  name        = "oracle-internal-dns-zone"
  dns_name    = "internal.corp.com."
  description = "Private DNS zone for Oracle Database endpoints"
  project     = var.project_id
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = var.vpc_network_self_link
    }
  }
}

# ------------------------------------------------------------------------
# Variables 
# ------------------------------------------------------------------------

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region for the CA Pool"
  type        = string
  default     = "us-central1"
}

variable "vpc_network_self_link" {
  description = "The self_link of the VPC network to attach the private DNS zone to"
  type        = string
}

# ------------------------------------------------------------------------
# Outputs (Map these directly to your main Oracle DB Terraform deployment)
# ------------------------------------------------------------------------

output "cas_pool_id" {
  value       = google_privateca_ca_pool.db_ca_pool.id
  description = "Pass this to the Oracle Terraform module as 'cas_pool_id'"
}

output "dns_zone_name" {
  value       = google_dns_managed_zone.db_private_zone.name
  description = "Pass this to the Oracle Terraform module as 'dns_zone_name'"
}

output "ca_certificate" {
  value       = google_privateca_certificate_authority.db_root_ca.pem_ca_certificates
  description = "The PEM-encoded CA certificate"
}
