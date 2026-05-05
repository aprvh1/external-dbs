# Quick Start Guide - Terraform + Helm + Artifactory (Airgapped)

## 🎯 **Three Ways to Deploy**

### **Method 1: From Artifactory Helm Repository** ⭐ Recommended

```bash
# 1. Upload chart to Artifactory
./setup-artifactory.sh

# 2. Configure Terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings

# 3. Deploy
export TF_VAR_artifactory_password="your-password"
terraform init
terraform apply
```

### **Method 2: From Local Chart File**

```bash
# 1. Place chart in local directory
mkdir -p charts/
cp /path/to/harness-smp.tgz charts/

# 2. Update main.tf - uncomment "Method 2" section

# 3. Deploy
terraform init
terraform apply
```

### **Method 3: From OCI Registry**

```bash
# 1. Push to OCI registry
helm push harness-smp.tgz oci://artifactory.company.com/helm-oci

# 2. Update main.tf repository URL to OCI format

# 3. Deploy
terraform init
terraform apply
```

---

## 📦 **Complete Workflow**

### **Initial Setup (One-Time)**

```bash
# 1. Install required tools
brew install terraform kubectl helm  # macOS
# OR
apt-get install terraform kubectl helm  # Ubuntu

# 2. Configure kubectl
export KUBECONFIG=/path/to/kubeconfig
kubectl cluster-info

# 3. Setup Artifactory
export ARTIFACTORY_URL="https://artifactory.company.com/artifactory"
export ARTIFACTORY_USER="helm-user"
export ARTIFACTORY_PASSWORD="your-password"
export CHART_FILE="harness-smp.tgz"

./setup-artifactory.sh

# 4. Configure Terraform
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars  # Update with your values
```

### **Deploy Harness SMP**

```bash
# 1. Initialize Terraform (downloads providers)
terraform init

# 2. Review what will be created
terraform plan

# 3. Apply changes
export TF_VAR_artifactory_password="your-password"
terraform apply
# Type 'yes' when prompted

# 4. Wait for deployment (may take 10-15 minutes)
# Watch progress: kubectl get pods -n harness -w
```

### **Verify Deployment**

```bash
# Check Helm release
helm list -n harness

# Check pods
kubectl get pods -n harness

# Check services
kubectl get svc -n harness

# Get outputs
terraform output
```

---

## 🔄 **Day-2 Operations**

### **Upgrade Chart Version**

```bash
# 1. Upload new chart version
export CHART_FILE="harness-smp-0.39.0.tgz"
./setup-artifactory.sh

# 2. Update version in terraform.tfvars
chart_version = "0.39.0"

# 3. Apply upgrade
terraform apply
```

### **Update Values Only**

```bash
# 1. Edit values.yaml
vi values.yaml

# 2. Apply changes
terraform apply
```

### **Rollback**

```bash
# Option 1: Via Terraform (change version)
terraform apply -var="chart_version=0.38.0"

# Option 2: Via Helm directly
helm rollback harness-smp -n harness

# Option 3: Full destroy and redeploy
terraform destroy -target=helm_release.harness_smp
terraform apply
```

### **Destroy Deployment**

```bash
# Remove everything
terraform destroy

# Or just the Helm release (keep namespace)
terraform destroy -target=helm_release.harness_smp
```

---

## 🔐 **Environment Variables**

### **Required**
```bash
export TF_VAR_artifactory_username="helm-user"
export TF_VAR_artifactory_password="your-password"
```

### **Optional**
```bash
export TF_VAR_chart_version="0.38.0"
export TF_VAR_namespace="harness"
export TF_VAR_timeout="900"
export KUBECONFIG="/path/to/kubeconfig"
```

---

## 🛠️ **Common Commands**

```bash
# Terraform
terraform init                    # Initialize
terraform plan                    # Preview changes
terraform apply                   # Apply changes
terraform apply -auto-approve     # Skip confirmation
terraform show                    # Show current state
terraform output                  # Show outputs
terraform refresh                 # Sync state with reality
terraform state list              # List resources
terraform destroy                 # Remove everything

# Helm
helm list -n harness             # List releases
helm status harness-smp -n harness  # Release status
helm get values harness-smp -n harness  # Show values
helm history harness-smp -n harness     # Release history
helm rollback harness-smp 1 -n harness  # Rollback to revision 1

# Kubernetes
kubectl get all -n harness       # All resources
kubectl get pods -n harness -w   # Watch pods
kubectl logs <pod> -n harness    # Pod logs
kubectl describe pod <pod> -n harness  # Pod details
kubectl get events -n harness --sort-by='.lastTimestamp'  # Events
```

---

## 🐛 **Troubleshooting Quick Fixes**

### **"Chart not found"**
```bash
# Verify chart in Artifactory
curl -u user:pass \
  "https://artifactory.company.com/artifactory/helm-local/index.yaml"

# Reindex repository
curl -u user:pass -X POST \
  "https://artifactory.company.com/artifactory/api/helm/helm-local/reindex"
```

### **"Authentication failed"**
```bash
# Test Artifactory credentials
curl -u user:pass \
  "https://artifactory.company.com/artifactory/api/system/ping"

# Check environment variable
echo $TF_VAR_artifactory_password
```

### **"Timeout"**
```bash
# Increase timeout in terraform.tfvars
timeout = 1800  # 30 minutes

# Check what's slow
kubectl get pods -n harness -w
kubectl describe pod <pending-pod> -n harness
```

### **"Provider error"**
```bash
# Verify kubectl works
kubectl cluster-info
kubectl get nodes

# Re-initialize Terraform
rm -rf .terraform/
terraform init
```

### **"Release already exists"**
```bash
# Import existing release
terraform import helm_release.harness_smp harness/harness-smp

# Or delete and recreate
helm uninstall harness-smp -n harness
terraform apply
```

---

## 📋 **Pre-Flight Checklist**

Before running `terraform apply`:

- [ ] Chart uploaded to Artifactory
- [ ] `terraform.tfvars` configured
- [ ] Artifactory credentials set (env vars)
- [ ] kubectl configured and tested (`kubectl cluster-info`)
- [ ] `values.yaml` customized
- [ ] Sufficient cluster resources (CPU, memory, storage)
- [ ] Network access from cluster to Artifactory
- [ ] Namespace doesn't exist (or `create_namespace = true`)
- [ ] Terraform initialized (`terraform init`)
- [ ] Plan reviewed (`terraform plan`)

---

## 💡 **Pro Tips**

1. **Use workspaces for multiple environments:**
   ```bash
   terraform workspace new prod
   terraform workspace new staging
   terraform workspace select prod
   ```

2. **Always plan before apply:**
   ```bash
   terraform plan -out=tfplan
   terraform apply tfplan
   ```

3. **Keep state secure:**
   ```bash
   # Use remote state
   terraform {
     backend "s3" {
       bucket = "terraform-state"
       key    = "harness/terraform.tfstate"
     }
   }
   ```

4. **Use variables files for environments:**
   ```bash
   terraform apply -var-file=environments/prod.tfvars
   ```

5. **Enable debug logging when troubleshooting:**
   ```bash
   export TF_LOG=DEBUG
   terraform apply
   ```

---

## 🔗 **Quick Links**

- [Main README](README.md) - Full documentation
- [Terraform Helm Provider](https://registry.terraform.io/providers/hashicorp/helm/latest/docs)
- [Artifactory Helm Setup](https://www.jfrog.com/confluence/display/JFROG/Helm+Chart+Repositories)

---

**Need help?** Check the [README](README.md#troubleshooting) for detailed troubleshooting.
