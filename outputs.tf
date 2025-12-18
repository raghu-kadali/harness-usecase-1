output "load_balancer_ip" {
  description = "Public IP of the HTTP Load Balancer"
  value       = google_compute_global_forwarding_rule.http_rule.ip_address
}
