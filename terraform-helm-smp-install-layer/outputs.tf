# Terraform Outputs

output "release_name" {
  description = "Name of the Helm release"
  value       = helm_release.harness_smp.name
}

output "release_namespace" {
  description = "Namespace where Helm release is deployed"
  value       = helm_release.harness_smp.namespace
}

output "release_version" {
  description = "Version of the deployed chart"
  value       = helm_release.harness_smp.version
}

output "release_status" {
  description = "Status of the Helm release"
  value       = helm_release.harness_smp.status
}

output "release_chart" {
  description = "Chart name and version"
  value       = "${helm_release.harness_smp.chart}:${helm_release.harness_smp.version}"
}

output "manifest_values" {
  description = "Computed values for the release"
  value       = helm_release.harness_smp.metadata
  sensitive   = true
}
