# Variables for Helm Chart Deployment

variable "artifactory_url" {
  description = "Artifactory base URL"
  type        = string
  default     = "https://artifactory.company.com/artifactory"
}

variable "artifactory_username" {
  description = "Artifactory username"
  type        = string
  sensitive   = true
}

variable "artifactory_password" {
  description = "Artifactory password"
  type        = string
  sensitive   = true
}

variable "helm_repo_name" {
  description = "Artifactory Helm repository name"
  type        = string
  default     = "helm-local"
}

variable "chart_name" {
  description = "Name of the Helm chart"
  type        = string
  default     = "harness-smp"
}

variable "chart_version" {
  description = "Version of the Helm chart to deploy"
  type        = string
  default     = "0.38.0"
}

variable "namespace" {
  description = "Kubernetes namespace for deployment"
  type        = string
  default     = "harness"
}

variable "create_namespace" {
  description = "Create namespace if it doesn't exist"
  type        = bool
  default     = true
}

variable "release_name" {
  description = "Helm release name"
  type        = string
  default     = "harness-smp"
}

variable "values_file" {
  description = "Path to custom values.yaml file"
  type        = string
  default     = "./values.yaml"
}

variable "timeout" {
  description = "Helm install timeout in seconds"
  type        = number
  default     = 900 # 15 minutes
}

variable "wait" {
  description = "Wait for resources to be ready"
  type        = bool
  default     = true
}
