# Main Terraform Configuration for Harness SMP Helm Chart Deployment

# Method 1: Using Helm Repository (Recommended for airgapped)
resource "helm_release" "harness_smp" {
  name             = var.release_name
  chart            = var.chart_name
  repository       = "${var.artifactory_url}/${var.helm_repo_name}"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace
  timeout          = var.timeout
  wait             = var.wait
  wait_for_jobs    = true

  # Authentication for private Artifactory repository
  repository_username = var.artifactory_username
  repository_password = var.artifactory_password

  # Custom values file
  values = [
    file(var.values_file)
  ]

  # Additional inline values (override specific settings)
  set {
    name  = "global.airgap"
    value = "true"
  }

  set {
    name  = "global.imageRegistry"
    value = "artifactory.company.com/docker-local"
  }

  # Dependencies - ensure namespace exists first
  depends_on = [
    kubernetes_namespace.harness
  ]
}

# Method 2: Using Local Chart File (Alternative for strict airgap)
# Uncomment this and comment out the above if you want to use local .tgz file
/*
resource "helm_release" "harness_smp_local" {
  name             = var.release_name
  chart            = "./charts/harness-smp-${var.chart_version}.tgz"
  namespace        = var.namespace
  create_namespace = var.create_namespace
  timeout          = var.timeout
  wait             = var.wait
  wait_for_jobs    = true

  values = [
    file(var.values_file)
  ]

  set {
    name  = "global.airgap"
    value = "true"
  }

  depends_on = [
    kubernetes_namespace.harness
  ]
}
*/

# Create namespace explicitly (optional, but recommended for control)
resource "kubernetes_namespace" "harness" {
  metadata {
    name = var.namespace

    labels = {
      name        = var.namespace
      environment = "production"
      managed-by  = "terraform"
    }
  }
}

# Optional: Create ConfigMap for additional configurations
resource "kubernetes_config_map" "harness_config" {
  metadata {
    name      = "harness-terraform-config"
    namespace = kubernetes_namespace.harness.metadata[0].name
  }

  data = {
    deployed_by = "terraform"
    chart_version = var.chart_version
    deployment_date = timestamp()
  }
}
