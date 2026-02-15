resource "google_monitoring_alert_policy" "tls_rotation_failure" {
  display_name = "Oracle TLS Certificate Rotation Failure - ${var.instance_name}"
  combiner     = "OR"
  project      = var.project_id
  enabled      = true

  conditions {
    display_name = "Rotation Script Reported Failure"
    condition_matched_log {
      # Filter for the specific structured log event
      filter = <<EOT
resource.type="gce_instance"
logName="projects/${var.project_id}/logs/oracle-tls-rotation"
jsonPayload.event="CERT_ROTATION_FAILURE"
EOT
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "3600s" # Don't spam alerts more than once per hour
    }
  }

  documentation {
    content = "The Oracle TLS certificate rotation script on instance ${var.instance_name} has failed. Immediate attention required to prevent database outage. Check /var/log/oracle-tls-rotation.log on the VM."
    mime_type = "text/markdown"
  }
}
