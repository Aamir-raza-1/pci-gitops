#!/bin/bash

# Maestro Facts Collection - Phase 03
# Runs actual discovery tools and collects infrastructure facts

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ARTIFACTS_DIR="$PROJECT_ROOT/artifacts"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
RUN_ID=""
PROVIDER=""
PARALLEL=true
DRY_RUN=false

# Tool availability
TOOLS_AVAILABLE=()
TOOLS_MISSING=()

print_header() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Maestro Facts Collection - Phase 03${NC}"
    echo -e "${CYAN}  Run ID: ${RUN_ID}${NC}"
    echo -e "${CYAN}  Running actual discovery tools...${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo
}

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

print_tool() {
    echo -e "${MAGENTA}[TOOL]${NC} $1"
}

# Check available tools
check_tools() {
    echo -e "${CYAN}Checking available discovery tools...${NC}"

    # Cloud CLI tools
    for tool in gcloud aws az kubectl terraform docker; do
        if command -v "$tool" &> /dev/null; then
            TOOLS_AVAILABLE+=("$tool")
            print_status "$tool available"
        else
            TOOLS_MISSING+=("$tool")
            print_warning "$tool not found"
        fi
    done

    # Specialized discovery tools
    for tool in trivy kubescape checkov tfsec; do
        if command -v "$tool" &> /dev/null; then
            TOOLS_AVAILABLE+=("$tool")
            print_status "$tool available (security scanning)"
        fi
    done

    echo
    echo -e "Available tools: ${GREEN}${#TOOLS_AVAILABLE[@]}${NC}"
    echo -e "Missing tools: ${YELLOW}${#TOOLS_MISSING[@]}${NC}"
}

# Run Terraform analysis
run_terraform_analysis() {
    local output_dir="$ARTIFACTS_DIR/facts/terraform"
    mkdir -p "$output_dir"

    echo -e "${CYAN}Running Terraform analysis...${NC}"

    if command -v terraform &> /dev/null; then
        print_tool "terraform show"

        if [[ "$DRY_RUN" == "true" ]]; then
            print_warning "DRY RUN: Would analyze Terraform configuration"
            return
        fi

        # Find terraform directories
        find . -name "*.tf" -type f 2>/dev/null | head -5 | while read -r tf_file; do
            local dir=$(dirname "$tf_file")
            echo "  Analyzing $dir"

            # Try terraform show
            if cd "$dir" && terraform init -backend=false &>/dev/null; then
                terraform show -json > "$output_dir/terraform_state_$(basename "$dir").json" 2>/dev/null || true
            fi
        done

        print_status "Terraform analysis complete"
    else
        print_warning "Terraform not available"
    fi
}

# Run container scanning
run_container_scanning() {
    local output_dir="$ARTIFACTS_DIR/facts/containers"
    mkdir -p "$output_dir"

    echo -e "${CYAN}Running container scanning...${NC}"

    if command -v docker &> /dev/null; then
        print_tool "docker images"

        if [[ "$DRY_RUN" == "true" ]]; then
            print_warning "DRY RUN: Would scan container images"
            return
        fi

        # List local images
        docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" > "$output_dir/docker_images.txt" 2>/dev/null || true

        # If Trivy is available, scan for vulnerabilities
        if command -v trivy &> /dev/null; then
            print_tool "trivy image scan"
            docker images --format "{{.Repository}}:{{.Tag}}" | head -3 | while read -r image; do
                echo "  Scanning $image"
                trivy image --format json "$image" > "$output_dir/trivy_$(echo "$image" | tr '/:' '_').json" 2>/dev/null || true
            done
        fi

        print_status "Container scanning complete"
    else
        print_warning "Docker not available"
    fi
}

# Run Kubernetes discovery
run_kubernetes_discovery() {
    local output_dir="$ARTIFACTS_DIR/facts/kubernetes"
    mkdir -p "$output_dir"

    echo -e "${CYAN}Running Kubernetes discovery...${NC}"

    if command -v kubectl &> /dev/null; then
        print_tool "kubectl cluster-info"

        if [[ "$DRY_RUN" == "true" ]]; then
            print_warning "DRY RUN: Would collect Kubernetes information"
            return
        fi

        # Get cluster info
        kubectl cluster-info dump --output-directory="$output_dir" &>/dev/null || true

        # Get resource counts
        echo "  Collecting resource counts..."
        kubectl get all --all-namespaces -o json > "$output_dir/all_resources.json" 2>/dev/null || true

        # Get nodes
        kubectl get nodes -o json > "$output_dir/nodes.json" 2>/dev/null || true

        # Get namespaces
        kubectl get namespaces -o json > "$output_dir/namespaces.json" 2>/dev/null || true

        # Run Kubescape if available
        if command -v kubescape &> /dev/null; then
            print_tool "kubescape security scan"
            kubescape scan framework nsa --format json > "$output_dir/kubescape_nsa.json" 2>/dev/null || true
        fi

        print_status "Kubernetes discovery complete"
    else
        print_warning "kubectl not available"
    fi
}

# Run cloud-specific discovery
run_cloud_discovery() {
    local output_dir="$ARTIFACTS_DIR/facts/cloud"
    mkdir -p "$output_dir"

    echo -e "${CYAN}Running cloud-specific discovery...${NC}"

    case "$PROVIDER" in
        gcp)
            run_gcp_discovery "$output_dir"
            ;;
        aws)
            run_aws_discovery "$output_dir"
            ;;
        azure)
            run_azure_discovery "$output_dir"
            ;;
        *)
            print_warning "Unknown provider: $PROVIDER"
            ;;
    esac
}

# GCP discovery
run_gcp_discovery() {
    local output_dir="$1"

    if command -v gcloud &> /dev/null; then
        print_tool "gcloud asset export"

        if [[ "$DRY_RUN" == "true" ]]; then
            print_warning "DRY RUN: Would export GCP assets"
            return
        fi

        # Export compute instances
        gcloud compute instances list --format=json > "$output_dir/gcp_instances.json" 2>/dev/null || true

        # Export GKE clusters
        gcloud container clusters list --format=json > "$output_dir/gcp_gke_clusters.json" 2>/dev/null || true

        # Export Cloud SQL
        gcloud sql instances list --format=json > "$output_dir/gcp_sql.json" 2>/dev/null || true

        # Export VPCs
        gcloud compute networks list --format=json > "$output_dir/gcp_networks.json" 2>/dev/null || true

        # Export load balancers
        gcloud compute forwarding-rules list --format=json > "$output_dir/gcp_loadbalancers.json" 2>/dev/null || true

        # Export storage buckets
        gcloud storage buckets list --format=json > "$output_dir/gcp_buckets.json" 2>/dev/null || true

        print_status "GCP discovery complete"
    else
        print_warning "gcloud not available"
    fi
}

# AWS discovery
run_aws_discovery() {
    local output_dir="$1"

    if command -v aws &> /dev/null; then
        print_tool "aws resource collection"

        if [[ "$DRY_RUN" == "true" ]]; then
            print_warning "DRY RUN: Would collect AWS resources"
            return
        fi

        # Get EC2 instances
        aws ec2 describe-instances > "$output_dir/aws_instances.json" 2>/dev/null || true

        # Get EKS clusters
        aws eks list-clusters > "$output_dir/aws_eks_clusters.json" 2>/dev/null || true

        # Get RDS instances
        aws rds describe-db-instances > "$output_dir/aws_rds.json" 2>/dev/null || true

        # Get VPCs
        aws ec2 describe-vpcs > "$output_dir/aws_vpcs.json" 2>/dev/null || true

        # Get load balancers
        aws elbv2 describe-load-balancers > "$output_dir/aws_loadbalancers.json" 2>/dev/null || true

        # Get S3 buckets
        aws s3api list-buckets > "$output_dir/aws_buckets.json" 2>/dev/null || true

        print_status "AWS discovery complete"
    else
        print_warning "aws CLI not available"
    fi
}

# Azure discovery
run_azure_discovery() {
    local output_dir="$1"

    if command -v az &> /dev/null; then
        print_tool "az resource collection"

        if [[ "$DRY_RUN" == "true" ]]; then
            print_warning "DRY RUN: Would collect Azure resources"
            return
        fi

        # Get VMs
        az vm list > "$output_dir/azure_vms.json" 2>/dev/null || true

        # Get AKS clusters
        az aks list > "$output_dir/azure_aks_clusters.json" 2>/dev/null || true

        # Get SQL databases
        az sql db list > "$output_dir/azure_sql.json" 2>/dev/null || true

        # Get VNets
        az network vnet list > "$output_dir/azure_vnets.json" 2>/dev/null || true

        # Get load balancers
        az network lb list > "$output_dir/azure_loadbalancers.json" 2>/dev/null || true

        # Get storage accounts
        az storage account list > "$output_dir/azure_storage.json" 2>/dev/null || true

        print_status "Azure discovery complete"
    else
        print_warning "az CLI not available"
    fi
}

# Run security scanning
run_security_scanning() {
    local output_dir="$ARTIFACTS_DIR/facts/security"
    mkdir -p "$output_dir"

    echo -e "${CYAN}Running security scanning...${NC}"

    # Checkov for IaC scanning
    if command -v checkov &> /dev/null; then
        print_tool "checkov IaC scan"

        if [[ "$DRY_RUN" == "false" ]]; then
            checkov -d . --output json > "$output_dir/checkov_scan.json" 2>/dev/null || true
        fi
    fi

    # TFSec for Terraform
    if command -v tfsec &> /dev/null; then
        print_tool "tfsec terraform scan"

        if [[ "$DRY_RUN" == "false" ]]; then
            tfsec . --format json > "$output_dir/tfsec_scan.json" 2>/dev/null || true
        fi
    fi

    print_status "Security scanning complete"
}

# Generate facts summary
generate_facts_summary() {
    local summary_file="$ARTIFACTS_DIR/processed/facts_summary_${RUN_ID}.json"

    echo -e "${CYAN}Generating facts summary...${NC}"

    # Count collected files
    local facts_count=$(find "$ARTIFACTS_DIR/facts" -type f 2>/dev/null | wc -l)

    python3 - <<EOF
import json
import os
from datetime import datetime

# Calculate facts directory size
facts_dir = "$ARTIFACTS_DIR/facts"
total_size = 0
file_count = 0

for root, dirs, files in os.walk(facts_dir):
    for f in files:
        fp = os.path.join(root, f)
        if os.path.exists(fp):
            total_size += os.path.getsize(fp)
            file_count += 1

summary = {
    "run_id": "${RUN_ID}",
    "timestamp": "${TIMESTAMP}",
    "phase": "03-facts",
    "provider": "${PROVIDER}",
    "statistics": {
        "tools_available": ${#TOOLS_AVAILABLE[@]},
        "tools_used": len([t for t in "${TOOLS_AVAILABLE[@]}".split() if t]),
        "facts_collected": file_count,
        "total_size_bytes": total_size,
        "total_size_mb": round(total_size / 1024 / 1024, 2)
    },
    "tools": {
        "available": "${TOOLS_AVAILABLE[@]}".split() if "${TOOLS_AVAILABLE[@]}" else [],
        "missing": "${TOOLS_MISSING[@]}".split() if "${TOOLS_MISSING[@]}" else []
    },
    "facts_categories": [],
    "next_steps": [
        "Review collected facts in $ARTIFACTS_DIR/facts/",
        "Run analysis phase: ./04-analyze/analyze-facts.sh --run-id ${RUN_ID}",
        "Generate migration plan: ./05-plan/generate-plan.sh --run-id ${RUN_ID}"
    ]
}

# Check which categories have data
for category in ["terraform", "containers", "kubernetes", "cloud", "security"]:
    cat_dir = os.path.join(facts_dir, category)
    if os.path.exists(cat_dir) and os.listdir(cat_dir):
        summary["facts_categories"].append(category)

with open('$summary_file', 'w') as f:
    json.dump(summary, f, indent=2)

print(f"Facts collected: {file_count} files ({summary['statistics']['total_size_mb']} MB)")
print(f"Categories: {', '.join(summary['facts_categories'])}")
EOF

    print_status "Facts summary saved to: $summary_file"
}

# Main execution
main() {
    print_header

    # Load provider from previous phase
    if [[ -n "$RUN_ID" ]]; then
        local discovery_file="$ARTIFACTS_DIR/processed/infrastructure_inventory_${RUN_ID}.json"
        if [[ -f "$discovery_file" ]]; then
            PROVIDER=$(grep -oP '"provider":\s*"\K[^"]+' "$discovery_file" 2>/dev/null || echo "gcp")
        fi
    fi

    # Create facts directory structure
    mkdir -p "$ARTIFACTS_DIR/facts"/{terraform,containers,kubernetes,cloud,security}

    # Check available tools
    check_tools
    echo

    # Run discovery tools
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}Starting facts collection...${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo

    # 1. Terraform analysis
    echo -e "${BLUE}[1/5] Terraform/IaC Analysis${NC}"
    run_terraform_analysis
    echo

    # 2. Container scanning
    echo -e "${BLUE}[2/5] Container Scanning${NC}"
    run_container_scanning
    echo

    # 3. Kubernetes discovery
    echo -e "${BLUE}[3/5] Kubernetes Discovery${NC}"
    run_kubernetes_discovery
    echo

    # 4. Cloud-specific discovery
    echo -e "${BLUE}[4/5] Cloud Provider Discovery${NC}"
    run_cloud_discovery
    echo

    # 5. Security scanning
    echo -e "${BLUE}[5/5] Security Scanning${NC}"
    run_security_scanning
    echo

    # Generate summary
    generate_facts_summary

    # Final summary
    echo
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Facts Collection Complete!${NC}"
    echo
    echo -e "Run ID:          ${CYAN}${RUN_ID}${NC}"
    echo -e "Provider:        ${CYAN}${PROVIDER}${NC}"
    echo -e "Tools Available: ${CYAN}${#TOOLS_AVAILABLE[@]}${NC}"
    echo -e "Facts Location:  ${CYAN}${ARTIFACTS_DIR}/facts/${NC}"
    echo
    echo -e "${YELLOW}Facts collected in the following categories:${NC}"
    for dir in "$ARTIFACTS_DIR"/facts/*/; do
        if [[ -d "$dir" ]] && [[ -n "$(ls -A "$dir" 2>/dev/null)" ]]; then
            echo -e "  • $(basename "$dir")"
        fi
    done
    echo
    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "1. Review collected facts"
    echo -e "2. Run analysis phase (coming soon)"
    echo -e "3. Generate migration plan (coming soon)"
    echo
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --run-id)
            RUN_ID="$2"
            shift 2
            ;;
        --provider)
            PROVIDER="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-parallel)
            PARALLEL=false
            shift
            ;;
        -h|--help)
            echo "Usage: $0 --run-id <run_id> [--provider <provider>] [--dry-run]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set default RUN_ID if not provided
if [[ -z "$RUN_ID" ]]; then
    RUN_ID="maestro_${TIMESTAMP}"
fi

# Run main
main