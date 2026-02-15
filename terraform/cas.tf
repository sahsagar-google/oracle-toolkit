# Create a dedicated CA Pool with strict security controls
resource "google_privateca_ca_pool" "secure_pool" {
  name     = "${var.instance_name}-secure-pool"
  location = var.region
  tier     = "DEVOPS"
  project  = var.project_id

  # Enforce that certs can ONLY be issued for your specific internal domain
  issuance_policy {
    allowed_issuance_modes {
      allow_config_based_issuance = true
      allow_csr_based_issuance    = true
    }

    # Restrict the domains that can be requested
    identity_constraints {
      allow_subject_passthrough           = true
      allow_subject_alt_names_passthrough = true
      
      cel_expression {
        # This expression returns 'true' only if ALL DNS SANs end with your domain suffix
        # Example: valid if san is "db.internal.corp.com", invalid if "evil.google.com"
        expression = "subject_alt_names.all(san, san.type == 'DNS' && san.value.endsWith('.${trimsuffix(var.dns_domain_name, ".")}'))"
        title      = "Restrict to Internal Domain"
        description = "Only allow certificates for domains ending in .${var.dns_domain_name}"
      }
    }
  }
}

# Create a Root CA in this pool (Required for the pool to function)
resource "google_privateca_certificate_authority" "secure_root" {
  pool                     = google_privateca_ca_pool.secure_pool.name
  certificate_authority_id = "${var.instance_name}-root-ca"
  location                 = var.region
  project                  = var.project_id
  
  config {
    subject_config {
      subject {
        common_name = "Secure Oracle Root CA"
        organization = "Google Cloud"
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
      }
    }
  }
  
  # Self-signed root
  type = "SELF_SIGNED"
  
  key_spec {
    algorithm = "RSA_PKCS1_4096_SHA256"
  }
  
  # Auto-enable the CA upon creation
  ignore_active_certificates_on_deletion = true
  skip_grace_period                      = true
}
