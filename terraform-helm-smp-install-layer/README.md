# Terraform Helm Deployment for Airgapped Environment

Deploy Harness SMP Helm chart using Terraform in an airgapped environment with Artifactory.

## 📋 Prerequisites

### Required Tools
- Terraform >= 1.0
- kubectl configured with cluster access
- Access to Artifactory (with Helm repository)
- Helm CLI (optional, for testing)

### Artifactory Setup
- Helm repository created in Artifactory
- `harness-smp.tgz` uploaded to the repository
- Credentials for Artifactory access

---

## 🏗️ Architecture Options

### **Option 1: Artifactory Helm Repository (Recommended)**
```
Terraform → Artifactory Helm Repo → Pull Chart → Install to K8s
```
✅ Centralized chart management  
✅ Version control  
✅ Multiple environments support  

### **Option 2: Local Chart File**
```
Terraform → Local .tgz File → Install to K8s
```
✅ No external dependencies  
✅ Simple setup  
⚠️ Manual version management  

---

## 🚀 Quick Start

### Step 1: Upload Chart to Artifactory

```bash
# Using curl
curl -u username:password \
  -T harness-smp.tgz \
  "https://artifactory.company.com/artifactory/helm-local/harness-smp-0.38.0.tgz"

# Using JFrog CLI
jfrog rt upload harness-smp.tgz helm-local/

# Reindex repository
curl -u username:password -X POST \
  "https://artifactory.company.com/artifactory/api/helm/helm-local/reindex"
```

### Step 2: Configure Terraform

```bash
# Copy example tfvars
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values
vi terraform.tfvars
```

### Step 3: Create values.yaml

```bash
# Create or copy your Harness values.yaml
cp /path/to/your/values.yaml ./values.yaml
```

### Step 4: Deploy

```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan

# Apply changes
TF_VAR_artifactory_password="your-password" terraform apply
```

---

## 📁 Project Structure

```
terraform-helm-example/
├── providers.tf              # Provider configurations
├── variables.tf              # Variable definitions
├── main.tf                   # Main Helm release resource
├── outputs.tf                # Output definitions
├── terraform.tfvars.example  # Example variables (copy to terraform.tfvars)
├── values.yaml               # Helm chart values
├── README.md                 # This file
└── .gitignore                # Git ignore file
```

---

## ⚙️ Configuration

### Environment Variables (Recommended for Secrets)

```bash
export TF_VAR_artifactory_username="helm-user"
export TF_VAR_artifactory_password="your-password"
```

### Using terraform.tfvars

```hcl
artifactory_url      = "https://artifactory.company.com/artifactory"
artifactory_username = "helm-user"
# Don't store password here - use environment variable!

chart_name    = "harness-smp"
chart_version = "0.38.0"
namespace     = "harness"
```

### Using -var-file (Multiple Environments)

```bash
# Production
terraform apply -var-file=environments/prod.tfvars

# Staging
terraform apply -var-file=environments/staging.tfvars
```

---

## 🔐 Authentication Options

### 1. Artifactory Token (Recommended)

```hcl
# In providers.tf
provider "helm" {
  registry {
    url      = "oci://artifactory.company.com/helm-local"
    username = var.artifactory_username
    password = var.artifactory_token  # Use token instead of password
  }
}
```

Generate token in Artifactory:
```bash
curl -u username:password -X POST \
  "https://artifactory.company.com/artifactory/api/security/token" \
  -d "username=helm-user" -d "scope=member-of-groups:readers"
```

### 2. Kubernetes Service Account

For automated deployments:
```bash
# Create service account
kubectl create serviceaccount terraform -n harness

# Bind to appropriate role
kubectl create rolebinding terraform-admin \
  --clusterrole=admin \
  --serviceaccount=harness:terraform \
  -n harness
```

---

## 🎯 Deployment Methods

### Method 1: From Artifactory Repository

```hcl
resource "helm_release" "harness_smp" {
  name       = "harness-smp"
  chart      = "harness-smp"
  repository = "https://artifactory.company.com/artifactory/helm-local"
  version    = "0.38.0"
  
  repository_username = var.artifactory_username
  repository_password = var.artifactory_password
  
  values = [file("values.yaml")]
}
```

### Method 2: From Local Chart File

```hcl
resource "helm_release" "harness_smp" {
  name  = "harness-smp"
  chart = "./charts/harness-smp-0.38.0.tgz"
  
  values = [file("values.yaml")]
}
```

### Method 3: From OCI Registry

```hcl
resource "helm_release" "harness_smp" {
  name       = "harness-smp"
  chart      = "harness-smp"
  repository = "oci://artifactory.company.com/helm-oci"
  version    = "0.38.0"
  
  repository_username = var.artifactory_username
  repository_password = var.artifactory_password
}
```

---

## 🔄 Upgrade Workflow

### 1. Upload New Chart Version

```bash
# Upload new version
curl -u username:password \
  -T harness-smp-0.39.0.tgz \
  "https://artifactory.company.com/artifactory/helm-local/harness-smp-0.39.0.tgz"

# Reindex
curl -u username:password -X POST \
  "https://artifactory.company.com/artifactory/api/helm/helm-local/reindex"
```

### 2. Update Terraform

```bash
# Update version in terraform.tfvars
chart_version = "0.39.0"

# Plan and apply
terraform plan
terraform apply
```

### 3. Rollback if Needed

```bash
# Rollback to previous version
terraform apply -var="chart_version=0.38.0"

# Or use Helm directly
helm rollback harness-smp -n harness
```

---

## 🛠️ Common Operations

### Check Current Deployment

```bash
# Terraform state
terraform show

# Helm release status
helm list -n harness

# Kubernetes resources
kubectl get all -n harness
```

### Update Values Only

```bash
# Edit values.yaml
vi values.yaml

# Apply changes (Terraform will trigger upgrade)
terraform apply
```

### Force Recreate

```bash
# Taint the resource
terraform taint helm_release.harness_smp

# Apply (will recreate)
terraform apply
```

### Destroy Deployment

```bash
# Remove Helm release and namespace
terraform destroy

# Or just the release (keep namespace)
terraform destroy -target=helm_release.harness_smp
```

---

## 🐛 Troubleshooting

### Issue: "Chart not found"

```bash
# Verify chart exists in Artifactory
curl -u username:password \
  "https://artifactory.company.com/artifactory/helm-local/index.yaml"

# Check repository configuration
helm repo add my-repo https://artifactory.company.com/artifactory/helm-local \
  --username=user --password=pass
helm search repo my-repo/harness-smp
```

### Issue: "Authentication failed"

```bash
# Test credentials
curl -u username:password \
  "https://artifactory.company.com/artifactory/api/system/ping"

# Check Terraform can access
terraform plan  # Should not show auth errors
```

### Issue: "Timeout waiting for resources"

```bash
# Increase timeout in variables.tf or tfvars
timeout = 1800  # 30 minutes

# Check pod status
kubectl get pods -n harness -w

# Check events
kubectl get events -n harness --sort-by='.lastTimestamp'
```

### Issue: "Provider configuration error"

```bash
# Verify kubectl access
kubectl cluster-info

# Test Helm provider
terraform console
> helm_release.harness_smp
```

---

## 📊 Best Practices

### 1. **Version Pinning**
```hcl
# Pin exact versions
chart_version = "0.38.0"  # Not "~> 0.38" or "latest"
```

### 2. **State Management**
```hcl
# Use remote state for team collaboration
terraform {
  backend "s3" {  # Or Artifactory, Consul, etc.
    bucket = "terraform-state"
    key    = "harness-smp/terraform.tfstate"
  }
}
```

### 3. **Environment Separation**
```
environments/
├── dev.tfvars
├── staging.tfvars
└── prod.tfvars
```

### 4. **Secret Management**
```bash
# Never commit secrets to Git
echo "*.tfvars" >> .gitignore
echo "terraform.tfvars" >> .gitignore

# Use external secret management
# - HashiCorp Vault
# - AWS Secrets Manager
# - Azure Key Vault
```

### 5. **Drift Detection**
```bash
# Regularly check for drift
terraform plan -out=tfplan

# Apply only if no unexpected changes
terraform show tfplan
terraform apply tfplan
```

---

## 🔍 Validation

### Pre-Deployment Checklist

- [ ] Chart uploaded to Artifactory
- [ ] Artifactory credentials configured
- [ ] kubectl configured and tested
- [ ] values.yaml customized for environment
- [ ] Namespace exists or create_namespace=true
- [ ] Sufficient cluster resources
- [ ] Network policies allow access to Artifactory

### Post-Deployment Validation

```bash
# Check Helm release
helm list -n harness

# Check pods
kubectl get pods -n harness

# Check services
kubectl get svc -n harness

# Test connectivity
kubectl run test-pod --rm -it --image=curlimages/curl -- \
  curl http://harness-service.harness.svc.cluster.local
```

---

## 📚 Additional Resources

- [Terraform Helm Provider Docs](https://registry.terraform.io/providers/hashicorp/helm/latest/docs)
- [JFrog Artifactory Helm](https://www.jfrog.com/confluence/display/JFROG/Helm+Chart+Repositories)
- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)

---

## 🤝 Contributing

If you encounter issues or have improvements:
1. Document the issue/solution
2. Update relevant scripts
3. Update this README

---

**Last Updated**: 2026-05-05  
**Terraform Version**: >= 1.0  
**Helm Provider Version**: ~> 2.12
