#!/bin/bash
#
# Setup Script: Upload Helm Chart to Artifactory
# Configures Artifactory for airgapped Helm deployments
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

section() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=========================================${NC}"
}

# Configuration
ARTIFACTORY_URL="${ARTIFACTORY_URL:-https://artifactory.company.com/artifactory}"
ARTIFACTORY_USER="${ARTIFACTORY_USER:-}"
ARTIFACTORY_PASSWORD="${ARTIFACTORY_PASSWORD:-}"
HELM_REPO="${HELM_REPO:-helm-local}"
CHART_FILE="${CHART_FILE:-harness-smp.tgz}"

section "Artifactory Helm Chart Upload Setup"

# Validate inputs
if [ -z "$ARTIFACTORY_USER" ]; then
    read -p "Artifactory Username: " ARTIFACTORY_USER
fi

if [ -z "$ARTIFACTORY_PASSWORD" ]; then
    read -sp "Artifactory Password: " ARTIFACTORY_PASSWORD
    echo ""
fi

if [ ! -f "$CHART_FILE" ]; then
    error "Chart file not found: $CHART_FILE"
fi

log "Configuration:"
log "  Artifactory URL: $ARTIFACTORY_URL"
log "  Repository: $HELM_REPO"
log "  Chart File: $CHART_FILE"
log "  Username: $ARTIFACTORY_USER"

# Test Artifactory connectivity
section "Testing Artifactory Connectivity"

log "Testing connection to Artifactory..."
if curl -u "$ARTIFACTORY_USER:$ARTIFACTORY_PASSWORD" \
    -s -f "$ARTIFACTORY_URL/api/system/ping" >/dev/null; then
    log "✓ Artifactory is accessible"
else
    error "✗ Cannot connect to Artifactory"
fi

# Check if repository exists
section "Checking Repository"

log "Checking if repository '$HELM_REPO' exists..."
if curl -u "$ARTIFACTORY_USER:$ARTIFACTORY_PASSWORD" \
    -s -f "$ARTIFACTORY_URL/api/repositories/$HELM_REPO" >/dev/null 2>&1; then
    log "✓ Repository '$HELM_REPO' exists"
else
    warn "Repository '$HELM_REPO' not found"
    read -p "Would you like to create it? (yes/no): " CREATE_REPO

    if [ "$CREATE_REPO" = "yes" ]; then
        log "Creating Helm repository..."

        cat > /tmp/repo-config.json <<EOF
{
  "key": "$HELM_REPO",
  "rclass": "local",
  "packageType": "helm",
  "description": "Local Helm repository for airgapped deployments"
}
EOF

        if curl -u "$ARTIFACTORY_USER:$ARTIFACTORY_PASSWORD" \
            -X PUT \
            -H "Content-Type: application/json" \
            -d @/tmp/repo-config.json \
            "$ARTIFACTORY_URL/api/repositories/$HELM_REPO" >/dev/null 2>&1; then
            log "✓ Repository created successfully"
            rm /tmp/repo-config.json
        else
            error "✗ Failed to create repository"
        fi
    else
        error "Repository required. Exiting."
    fi
fi

# Extract chart metadata
section "Extracting Chart Metadata"

log "Extracting chart name and version..."

# Extract Chart.yaml from the tgz
CHART_NAME=$(tar -xzf "$CHART_FILE" -O */Chart.yaml 2>/dev/null | grep "^name:" | awk '{print $2}' | tr -d '\r')
CHART_VERSION=$(tar -xzf "$CHART_FILE" -O */Chart.yaml 2>/dev/null | grep "^version:" | awk '{print $2}' | tr -d '\r')

if [ -z "$CHART_NAME" ] || [ -z "$CHART_VERSION" ]; then
    error "Could not extract chart metadata"
fi

log "  Chart Name: $CHART_NAME"
log "  Chart Version: $CHART_VERSION"

# Upload chart
section "Uploading Chart to Artifactory"

UPLOAD_PATH="$HELM_REPO/$CHART_NAME-$CHART_VERSION.tgz"
UPLOAD_URL="$ARTIFACTORY_URL/$UPLOAD_PATH"

log "Uploading to: $UPLOAD_URL"

if curl -u "$ARTIFACTORY_USER:$ARTIFACTORY_PASSWORD" \
    -T "$CHART_FILE" \
    "$UPLOAD_URL" 2>&1 | grep -q "201\|200"; then
    log "✓ Chart uploaded successfully"
else
    error "✗ Failed to upload chart"
fi

# Reindex repository
section "Reindexing Helm Repository"

log "Triggering repository reindex..."
if curl -u "$ARTIFACTORY_USER:$ARTIFACTORY_PASSWORD" \
    -X POST \
    "$ARTIFACTORY_URL/api/helm/$HELM_REPO/reindex" 2>&1 | grep -q "200"; then
    log "✓ Repository reindexed successfully"
else
    warn "Reindex may have failed (check Artifactory logs)"
fi

# Verify upload
section "Verifying Upload"

log "Checking if chart is accessible..."
sleep 2  # Give Artifactory time to index

if curl -u "$ARTIFACTORY_USER:$ARTIFACTORY_PASSWORD" \
    -s -f "$UPLOAD_URL" >/dev/null; then
    log "✓ Chart is accessible in Artifactory"
else
    warn "Chart upload succeeded but may not be indexed yet"
fi

# Test with Helm CLI (optional)
section "Testing with Helm CLI"

if command -v helm >/dev/null 2>&1; then
    log "Testing Helm CLI access..."

    TEMP_REPO_NAME="artifactory-test-$$"

    if helm repo add "$TEMP_REPO_NAME" \
        "$ARTIFACTORY_URL/$HELM_REPO" \
        --username="$ARTIFACTORY_USER" \
        --password="$ARTIFACTORY_PASSWORD" >/dev/null 2>&1; then

        log "✓ Helm repository added successfully"

        if helm search repo "$TEMP_REPO_NAME/$CHART_NAME" --version="$CHART_VERSION" | grep -q "$CHART_NAME"; then
            log "✓ Chart is discoverable via Helm CLI"
        else
            warn "Chart not yet discoverable (may need time to index)"
        fi

        helm repo remove "$TEMP_REPO_NAME" >/dev/null 2>&1
    else
        warn "Could not add Helm repository (this is optional)"
    fi
else
    warn "Helm CLI not installed, skipping Helm test"
fi

# Generate Terraform configuration snippet
section "Terraform Configuration"

log "Generating Terraform configuration snippet..."

cat > terraform-config-snippet.tf <<EOF
# Artifactory Configuration for Terraform
# Add this to your terraform.tfvars or use as environment variables

artifactory_url      = "$ARTIFACTORY_URL"
artifactory_username = "$ARTIFACTORY_USER"
# artifactory_password = "SET_VIA_ENV_VAR"  # Use TF_VAR_artifactory_password

helm_repo_name = "$HELM_REPO"
chart_name     = "$CHART_NAME"
chart_version  = "$CHART_VERSION"
EOF

log "✓ Configuration saved to: terraform-config-snippet.tf"

# Final summary
section "Setup Complete!"

log "Chart Details:"
log "  Name: $CHART_NAME"
log "  Version: $CHART_VERSION"
log "  Repository: $HELM_REPO"
log "  URL: $UPLOAD_URL"
log ""
log "Next Steps:"
log "1. Review terraform-config-snippet.tf"
log "2. Update your terraform.tfvars"
log "3. Run: terraform init"
log "4. Run: terraform plan"
log "5. Run: terraform apply"
log ""
log "To deploy with Terraform:"
log "  export TF_VAR_artifactory_password='$ARTIFACTORY_PASSWORD'"
log "  terraform apply"

exit 0
