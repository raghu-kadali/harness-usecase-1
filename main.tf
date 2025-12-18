################################
# Provider
################################
provider "google" {
  project = var.project_id
  region  = var.region
}

################################
# Startup Script (Apache)
################################
locals {
  startup_script = <<-EOF
    #!/bin/bash
    apt update -y
    apt install apache2 -y
    systemctl start apache2
    systemctl enable apache2
    echo "Hello from MIG Apache VM" > /var/www/html/index.html
  EOF
}

################################
# Instance Template
################################
resource "google_compute_instance_template" "apache_template" {
  name_prefix  = "apache-template-"
  machine_type = "e2-medium"

  disk {
    boot         = true
    auto_delete  = true
    source_image = "debian-cloud/debian-11"
  }

  network_interface {
    network = "default"
  }

  metadata_startup_script = local.startup_script
  tags = ["http-server"]
}

################################
# Firewall Rule (HTTP)
################################
resource "google_compute_firewall" "allow_http" {
  name    = "allow-http-raghu"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]
}

################################
# Health Check
################################
resource "google_compute_health_check" "http_hc" {
  name = "apache-hc"

  http_health_check {
    port         = 80
    request_path = "/"
  }
}

################################
# Managed Instance Group (MIG)
################################
resource "google_compute_instance_group_manager" "apache_mig" {
  name               = "apache-mig"
  zone               = var.zone
  base_instance_name = "apache"
  target_size        = 2

  version {
    instance_template = google_compute_instance_template.apache_template.id
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.http_hc.id
    initial_delay_sec = 60
  }
}

################################
# Autoscaler
################################
resource "google_compute_autoscaler" "apache_autoscaler" {
  name   = "apache-autoscaler"
  zone   = var.zone
  target = google_compute_instance_group_manager.apache_mig.id

  autoscaling_policy {
    min_replicas = 2
    max_replicas = 5

    cpu_utilization {
      target = 0.6
    }
  }
}

################################
# Backend Service (Load Balancer)
################################
resource "google_compute_backend_service" "backend" {
  name          = "apache-backend"
  protocol      = "HTTP"
  port_name     = "http"
  health_checks = [google_compute_health_check.http_hc.id]

  backend {
    group = google_compute_instance_group_manager.apache_mig.instance_group
  }
}

################################
# URL Map
################################
resource "google_compute_url_map" "url_map" {
  name            = "apache-url-map"
  default_service = google_compute_backend_service.backend.id
}

################################
# HTTP Proxy
################################
resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "apache-http-proxy"
  url_map = google_compute_url_map.url_map.id
}

################################
# Forwarding Rule (Public IP)
################################
resource "google_compute_global_forwarding_rule" "http_rule" {
  name       = "apache-forwarding-rule"
  target     = google_compute_target_http_proxy.http_proxy.id
  port_range = "80"
}
