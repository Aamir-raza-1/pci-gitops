#!/bin/bash

# Comprehensive Dynamic Validation
# Validates everything based on config, provides detailed feedback

set -euo pipefail

CONFIG_FILE="${1:-}"
RUN_ID="${2:-validation_$(date +%Y%m%d_%H%M%S)}"

if [[ -z "$CONFIG_FILE" ]]; then
    echo "Usage: $0 CONFIG_FILE [RUN_ID]"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Output directory
PROJECT_ROOT="$(dirname $(dirname $(realpath $0)))"
OUTPUT_DIR="$PROJECT_ROOT/artifacts/access_${RUN_ID}"
mkdir -p "$OUTPUT_DIR"

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Comprehensive Access Validation${NC}"
echo -e "${BLUE}  Run ID: ${RUN_ID}${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo

# Parse configuration
echo -e "${YELLOW}[1/5] Analyzing Configuration${NC}"

CONFIG_ANALYSIS=$(python3 - "$CONFIG_FILE" << 'PYTHON_END'
import json
import sys

config_file = sys.argv[1]
with open(config_file, 'r') as f:
    config = json.load(f)

analysis = {
    'provider': config.get('discovery', {}).get('provider', 'unknown'),
    'auth_mode': config.get('discovery', {}).get('auth', {}).get('mode', 'unknown'),
    'project': config.get('discovery', {}).get('auth', {}).get('project', ''),
    'region': config.get('discovery', {}).get('auth', {}).get('region', ''),
    'has_kubernetes': bool(config.get('discovery', {}).get('scope', {}).get('kubernetes', False)),
    'has_databases': bool(config.get('discovery', {}).get('scope', {}).get('databases', False)),
    'has_storage': bool(config.get('discovery', {}).get('scope', {}).get('storage', False)),
    'has_repos': bool(config.get('discovery', {}).get('scope', {}).get('repositories', [])),
    'has_websites': bool(config.get('discovery', {}).get('scope', {}).get('websites', [])),
    'mode': config.get('discovery', {}).get('mode', 'full')
}

print(json.dumps(analysis))
PYTHON_END
)

# Extract values
PROVIDER=$(echo "$CONFIG_ANALYSIS" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['provider'])")
MODE=$(echo "$CONFIG_ANALYSIS" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['mode'])")
HAS_K8S=$(echo "$CONFIG_ANALYSIS" | python3 -c "import sys,json; print('yes' if json.loads(sys.stdin.read())['has_kubernetes'] else 'no')")
HAS_DB=$(echo "$CONFIG_ANALYSIS" | python3 -c "import sys,json; print('yes' if json.loads(sys.stdin.read())['has_databases'] else 'no')")
HAS_STORAGE=$(echo "$CONFIG_ANALYSIS" | python3 -c "import sys,json; print('yes' if json.loads(sys.stdin.read())['has_storage'] else 'no')")
HAS_REPOS=$(echo "$CONFIG_ANALYSIS" | python3 -c "import sys,json; print('yes' if json.loads(sys.stdin.read())['has_repos'] else 'no')")

echo "  Provider: $PROVIDER"
echo "  Mode: $MODE"
echo "  Components to check:"
[[ "$HAS_K8S" == "yes" ]] && echo "    - Kubernetes"
[[ "$HAS_DB" == "yes" ]] && echo "    - Databases"
[[ "$HAS_STORAGE" == "yes" ]] && echo "    - Storage"
[[ "$HAS_REPOS" == "yes" ]] && echo "    - Repositories"
echo

# Initialize validation results
VALIDATION_RESULT="$OUTPUT_DIR/validation_result.json"
cat > "$VALIDATION_RESULT" << EOF
{
  "run_id": "$RUN_ID",
  "timestamp": "$(date -u +%Y%m%dT%H%M%SZ)",
  "provider": "$PROVIDER",
  "mode": "$MODE",
  "status": "checking",
  "validations": {},
  "missing_tools": [],
  "missing_permissions": [],
  "remediation": {
    "tools": [],
    "permissions": [],
    "auth": []
  },
  "ready_for_discovery": false
}
EOF

# Track overall status
OVERALL_STATUS="SUCCESS"
CRITICAL_MISSING=""

# Function to update result
update_result() {
    local category="$1"
    local item="$2"
    local status="$3"
    local message="${4:-}"

    python3 - "$VALIDATION_RESULT" << PYTHON_UPDATE
import json
import sys

result_file = sys.argv[1]
with open(result_file, 'r') as f:
    data = json.load(f)

if '$category' not in data['validations']:
    data['validations']['$category'] = {}

data['validations']['$category']['$item'] = {
    'status': '$status',
    'message': '$message'
}

with open(result_file, 'w') as f:
    json.dump(data, f, indent=2)
PYTHON_UPDATE
}

# VALIDATION 1: Core Tools
echo -e "${YELLOW}[2/5] Validating Core Tools${NC}"

# Always check these
for tool in bash python3 curl; do
    if command -v $tool >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} $tool installed"
        update_result "core_tools" "$tool" "present" "$(command -v $tool)"
    else
        echo -e "  ${RED}✗${NC} $tool missing"
        update_result "core_tools" "$tool" "missing" "Required for maestro"
        OVERALL_STATUS="FAILED"
        CRITICAL_MISSING="$CRITICAL_MISSING $tool"
    fi
done

# VALIDATION 2: Provider-specific tools and auth
echo
echo -e "${YELLOW}[3/5] Validating Provider: $PROVIDER${NC}"

case "$PROVIDER" in
    gcp)
        # Check gcloud
        if command -v gcloud >/dev/null 2>&1; then
            VERSION=$(gcloud version --format=json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('Google Cloud SDK','unknown'))" 2>/dev/null || echo "unknown")
            echo -e "  ${GREEN}✓${NC} gcloud installed (v$VERSION)"
            update_result "provider_tools" "gcloud" "present" "$VERSION"

            # Check authentication
            if gcloud auth list 2>/dev/null | grep -q "ACTIVE"; then
                ACCOUNT=$(gcloud config get-value account 2>/dev/null || echo "none")
                PROJECT=$(gcloud config get-value project 2>/dev/null || echo "none")
                echo -e "  ${GREEN}✓${NC} Authenticated: $ACCOUNT"
                echo -e "  ${GREEN}✓${NC} Project: $PROJECT"
                update_result "authentication" "gcp" "active" "Account: $ACCOUNT, Project: $PROJECT"
            else
                echo -e "  ${RED}✗${NC} Not authenticated"
                update_result "authentication" "gcp" "missing" "Run: gcloud auth login"
                OVERALL_STATUS="FAILED"

                python3 -c "
import json
data = json.load(open('$VALIDATION_RESULT'))
data['remediation']['auth'].append('gcloud auth login')
data['remediation']['auth'].append('gcloud config set project YOUR_PROJECT_ID')
json.dump(data, open('$VALIDATION_RESULT', 'w'), indent=2)
"
            fi

            # Check permissions (if authenticated)
            if gcloud auth list 2>/dev/null | grep -q "ACTIVE"; then
                echo -e "\n  Checking GCP permissions:"

                # Project list
                if gcloud projects list --limit=1 >/dev/null 2>&1; then
                    echo -e "    ${GREEN}✓${NC} Can list projects"
                    update_result "permissions" "gcp_projects" "granted" ""
                else
                    echo -e "    ${YELLOW}⚠${NC} Cannot list projects"
                    update_result "permissions" "gcp_projects" "denied" "May need viewer role"
                fi

                # Compute instances (if full mode)
                if [[ "$MODE" == "full" ]]; then
                    if gcloud compute instances list --limit=1 >/dev/null 2>&1; then
                        echo -e "    ${GREEN}✓${NC} Can list compute instances"
                        update_result "permissions" "gcp_compute" "granted" ""
                    else
                        echo -e "    ${YELLOW}⚠${NC} Cannot list compute instances"
                        update_result "permissions" "gcp_compute" "denied" "May need compute.viewer"
                    fi
                fi

                # Storage (if needed)
                if [[ "$HAS_STORAGE" == "yes" ]]; then
                    if gsutil ls -p $(gcloud config get-value project) >/dev/null 2>&1; then
                        echo -e "    ${GREEN}✓${NC} Can access storage"
                        update_result "permissions" "gcp_storage" "granted" ""
                    else
                        echo -e "    ${YELLOW}⚠${NC} Cannot access storage"
                        update_result "permissions" "gcp_storage" "denied" "May need storage.viewer"
                    fi
                fi
            fi
        else
            echo -e "  ${RED}✗${NC} gcloud not installed"
            update_result "provider_tools" "gcloud" "missing" "Required for GCP"
            OVERALL_STATUS="FAILED"
            CRITICAL_MISSING="$CRITICAL_MISSING gcloud"

            python3 -c "
import json
data = json.load(open('$VALIDATION_RESULT'))
data['remediation']['tools'].append('curl https://sdk.cloud.google.com | bash')
json.dump(data, open('$VALIDATION_RESULT', 'w'), indent=2)
"
        fi
        ;;

    aws)
        if command -v aws >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} AWS CLI installed"
            update_result "provider_tools" "aws" "present" "$(aws --version 2>&1)"

            if aws sts get-caller-identity >/dev/null 2>&1; then
                ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
                echo -e "  ${GREEN}✓${NC} Authenticated: Account $ACCOUNT"
                update_result "authentication" "aws" "active" "Account: $ACCOUNT"
            else
                echo -e "  ${RED}✗${NC} Not authenticated"
                update_result "authentication" "aws" "missing" "Configure AWS credentials"
                OVERALL_STATUS="FAILED"
            fi
        else
            echo -e "  ${RED}✗${NC} AWS CLI not installed"
            OVERALL_STATUS="FAILED"
        fi
        ;;
esac

# VALIDATION 3: Kubernetes (if needed)
if [[ "$HAS_K8S" == "yes" ]]; then
    echo
    echo -e "${YELLOW}[4/5] Validating Kubernetes Access${NC}"

    if command -v kubectl >/dev/null 2>&1; then
        VERSION=$(kubectl version --client --short 2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}✓${NC} kubectl installed ($VERSION)"
        update_result "kubernetes" "kubectl" "present" "$VERSION"

        if kubectl config current-context >/dev/null 2>&1; then
            CONTEXT=$(kubectl config current-context)
            echo -e "  ${GREEN}✓${NC} Context: $CONTEXT"
            update_result "kubernetes" "context" "configured" "$CONTEXT"

            # Test cluster access
            if kubectl get namespaces >/dev/null 2>&1; then
                NS_COUNT=$(kubectl get namespaces --no-headers 2>/dev/null | wc -l)
                echo -e "  ${GREEN}✓${NC} Can access cluster ($NS_COUNT namespaces)"
                update_result "kubernetes" "cluster_access" "granted" "$NS_COUNT namespaces"
            else
                echo -e "  ${YELLOW}⚠${NC} Limited cluster access"
                update_result "kubernetes" "cluster_access" "limited" "Cannot list namespaces"
            fi

            # Check specific permissions
            if kubectl auth can-i get pods >/dev/null 2>&1; then
                echo -e "  ${GREEN}✓${NC} Can get pods"
                update_result "kubernetes" "pods_permission" "granted" ""
            else
                echo -e "  ${YELLOW}⚠${NC} Cannot get pods"
                update_result "kubernetes" "pods_permission" "denied" ""
            fi
        else
            echo -e "  ${RED}✗${NC} No kubectl context"
            update_result "kubernetes" "context" "missing" "Configure kubeconfig"
            OVERALL_STATUS="PARTIAL"
        fi
    else
        echo -e "  ${RED}✗${NC} kubectl not installed"
        update_result "kubernetes" "kubectl" "missing" "Required for Kubernetes"
        OVERALL_STATUS="PARTIAL"
    fi
fi

# VALIDATION 4: Additional tools
if [[ "$HAS_REPOS" == "yes" ]]; then
    echo
    echo -e "${YELLOW}[5/5] Validating Additional Tools${NC}"

    if command -v git >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} git installed"
        update_result "additional" "git" "present" "$(git --version)"
    else
        echo -e "  ${YELLOW}⚠${NC} git not installed"
        update_result "additional" "git" "missing" "Needed for repositories"
    fi
fi

# Final status update
python3 -c "
import json
data = json.load(open('$VALIDATION_RESULT'))
data['status'] = '$OVERALL_STATUS'

# Determine if ready for discovery
critical_ok = True
if '$PROVIDER' == 'gcp':
    critical_ok = 'gcloud' in str(data.get('validations', {}).get('provider_tools', {}))
    critical_ok = critical_ok and 'active' in str(data.get('validations', {}).get('authentication', {}))

data['ready_for_discovery'] = critical_ok and '$OVERALL_STATUS' != 'FAILED'

# Count issues
data['issue_count'] = len(data.get('missing_tools', [])) + len(data.get('missing_permissions', []))

json.dump(data, open('$VALIDATION_RESULT', 'w'), indent=2)
"

# Generate setup guide
GUIDE_FILE="$OUTPUT_DIR/setup_guide.md"
python3 - "$VALIDATION_RESULT" "$GUIDE_FILE" << 'PYTHON_GUIDE'
import json
import sys

result_file = sys.argv[1]
guide_file = sys.argv[2]

with open(result_file, 'r') as f:
    data = json.load(f)

with open(guide_file, 'w') as f:
    f.write("# Setup Guide\n\n")
    f.write(f"Generated: {data['timestamp']}\n\n")

    if data['status'] == 'SUCCESS':
        f.write("## ✅ All validations passed!\n\n")
        f.write("You're ready to proceed with the discovery phase.\n")
    else:
        f.write("## Required Actions\n\n")

        if data['remediation']['tools']:
            f.write("### Install Missing Tools\n\n")
            for cmd in data['remediation']['tools']:
                f.write(f"```bash\n{cmd}\n```\n\n")

        if data['remediation']['auth']:
            f.write("### Authentication Setup\n\n")
            for cmd in data['remediation']['auth']:
                f.write(f"```bash\n{cmd}\n```\n\n")

        if data['remediation']['permissions']:
            f.write("### Permission Fixes\n\n")
            for cmd in data['remediation']['permissions']:
                f.write(f"- {cmd}\n")

    f.write("\n## Validation Summary\n\n")
    f.write(f"- Provider: {data['provider']}\n")
    f.write(f"- Mode: {data['mode']}\n")
    f.write(f"- Status: {data['status']}\n")
    f.write(f"- Ready for Discovery: {'Yes' if data['ready_for_discovery'] else 'No'}\n")
PYTHON_GUIDE

# Summary output
echo
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Validation Complete${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo

READY=$(python3 -c "import json; print(json.load(open('$VALIDATION_RESULT'))['ready_for_discovery'])")

if [[ "$OVERALL_STATUS" == "SUCCESS" ]]; then
    echo -e "${GREEN}✅ All validations passed!${NC}"
    echo -e "${GREEN}   You're ready for the discovery phase.${NC}"
elif [[ "$READY" == "True" ]]; then
    echo -e "${YELLOW}⚠️  Some optional checks failed but you can proceed.${NC}"
    echo -e "${YELLOW}   See setup_guide.md for improvements.${NC}"
else
    echo -e "${RED}❌ Critical validations failed.${NC}"
    echo -e "${RED}   You must fix these before proceeding:${NC}"
    echo -e "${RED}   $CRITICAL_MISSING${NC}"
    echo
    echo -e "${YELLOW}📖 See detailed guide: $GUIDE_FILE${NC}"
fi

echo
echo -e "${BLUE}📊 Validation Report: $VALIDATION_RESULT${NC}"
echo -e "${BLUE}📖 Setup Guide: $GUIDE_FILE${NC}"
echo -e "${BLUE}📁 Output Directory: $OUTPUT_DIR${NC}"
echo

# Create simple status file for next phase
cat > "$OUTPUT_DIR/access_validation.json" << EOF
{
  "status": "$OVERALL_STATUS",
  "ready": $READY,
  "run_id": "$RUN_ID",
  "timestamp": "$(date -u +%Y%m%dT%H%M%SZ)"
}
EOF