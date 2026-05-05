# Terraform Provider Configuration for Airgapped Helm Installation

terraform {
  required_version = ">= 1.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
  }
}

# Kubernetes Provider - Configure for your cluster
provider "kubernetes" {
  # Option 1: Using kubeconfig file
  config_path = "~/.kube/config"

  # Option 2: Explicit configuration
  # host                   = "https://kubernetes.company.com:6443"
  # token                  = var.k8s_token
  # cluster_ca_certificate = base64decode(var.cluster_ca_cert)

  # Option 3: Using exec plugin for authentication
  # config_path = "~/.kube/config"
  # config_context = "production-cluster"
}

# Helm Provider
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"

    # Or explicit configuration
    # host                   = "https://kubernetes.company.com:6443"
    # token                  = var.k8s_token
    # cluster_ca_certificate = base64decode(var.cluster_ca_cert)
  }

  # Artifactory repository configuration
  registry {
    url      = "oci://artifactory.company.com/helm-local"
    username = var.artifactory_username
    password = var.artifactory_password
  }
}
