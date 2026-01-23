#!/bin/bash

# Maestro Phase 00 - Input Processing
# Processes assessment form data and generates artifacts for discovery phase

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ARTIFACTS_DIR="$PROJECT_ROOT/artifacts"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Default values
MODE="online"
CONFIDENCE=0
PROVIDER=""
AUTH_MODE=""
FORM_DATA_FILE=""
RUN_ID="maestro_${TIMESTAMP}"
DRY_RUN=false
VERBOSE=false

# Print functions
print_header() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Maestro Phase 00 - Input Processing${NC}"
    echo -e "${CYAN}  Run ID: ${RUN_ID}${NC}"
    echo -e "${CYAN}  Timestamp: ${TIMESTAMP}${NC}"
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

print_section() {
    echo
    echo -e "${MAGENTA}═══ $1 ═══${NC}"
    echo
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    --form-data FILE      Path to form data JSON file (required)
    --run-id ID          Custom run ID (default: maestro_TIMESTAMP)
    --dry-run            Perform dry run without creating files
    --verbose            Enable verbose output
    -h, --help           Show this help message

Example:
    $0 --form-data ./form_data.json
    $0 --form-data ./form_data.json --run-id custom_001 --verbose

EOF
    exit 0
}

# Create directory structure
create_directories() {
    print_info "Creating artifact directories..."

    local dirs=(
        "$ARTIFACTS_DIR/raw"
        "$ARTIFACTS_DIR/processed"
        "$ARTIFACTS_DIR/logs"
        "$ARTIFACTS_DIR/metadata"
    )

    for dir in "${dirs[@]}"; do
        if [[ "$DRY_RUN" == "false" ]]; then
            mkdir -p "$dir"
            [[ "$VERBOSE" == "true" ]] && echo "  Created: $dir"
        else
            print_info "Would create: $dir"
        fi
    done

    print_status "Directory structure ready"
}

# Process form data
process_form_data() {
    print_section "Processing Form Data"

    if [[ ! -f "$FORM_DATA_FILE" ]]; then
        print_error "Form data file not found: $FORM_DATA_FILE"
        exit 1
    fi

    print_info "Reading form data from: $FORM_DATA_FILE"

    # Save raw form data
    local raw_file="$ARTIFACTS_DIR/raw/form_data_${RUN_ID}.json"
    if [[ "$DRY_RUN" == "false" ]]; then
        cp "$FORM_DATA_FILE" "$raw_file"
        print_status "Raw form data saved to: $raw_file"
    else
        print_info "Would save raw form data to: $raw_file"
    fi

    # Extract key information using Python
    python3 - <<EOF
import json
import sys

try:
    with open("$FORM_DATA_FILE", 'r') as f:
        data = json.load(f)

    # Extract key fields
    company_name = data.get('company_name', 'Unknown')
    provider = data.get('cloud_provider', 'gcp')
    auth_mode = data.get('auth_mode', 'adc')
    budget = data.get('current_budget', 'unknown')
    timeline = data.get('migration_timeline', 'unknown')
    serving = data.get('serving_customers', 'unknown')
    current_hosting = data.get('current_hosting', 'unknown')

    print(f"Company: {company_name}")
    print(f"Provider: {provider}")
    print(f"Auth Mode: {auth_mode}")
    print(f"Budget: {budget}")
    print(f"Timeline: {timeline}")
    print(f"Currently Serving: {serving}")
    print(f"Current Hosting: {current_hosting}")

    # Set global variables
    with open('/tmp/maestro_vars.sh', 'w') as f:
        f.write(f'COMPANY_NAME="{company_name}"\n')
        f.write(f'PROVIDER="{provider}"\n')
        f.write(f'AUTH_MODE="{auth_mode}"\n')
        f.write(f'BUDGET="{budget}"\n')
        f.write(f'TIMELINE="{timeline}"\n')

except Exception as e:
    print(f"Error processing form data: {e}", file=sys.stderr)
    sys.exit(1)
EOF

    # Source the variables
    if [[ -f /tmp/maestro_vars.sh ]]; then
        source /tmp/maestro_vars.sh
        rm -f /tmp/maestro_vars.sh
    fi

    print_status "Form data processed successfully"
}

# Generate metadata
generate_metadata() {
    print_section "Generating Metadata"

    local metadata_file="$ARTIFACTS_DIR/metadata/run_metadata_${RUN_ID}.json"

    if [[ "$DRY_RUN" == "false" ]]; then
        python3 - <<EOF
import json
from datetime import datetime

metadata = {
    "run_id": "${RUN_ID}",
    "timestamp": "${TIMESTAMP}",
    "phase": "00-input",
    "status": "processing",
    "environment": {
        "script": "$0",
        "working_dir": "$(pwd)",
        "user": "$(whoami)",
        "hostname": "$(hostname)"
    },
    "configuration": {
        "provider": "${PROVIDER:-unknown}",
        "auth_mode": "${AUTH_MODE:-unknown}",
        "confidence": ${CONFIDENCE},
        "dry_run": "${DRY_RUN}",
        "verbose": "${VERBOSE}"
    },
    "artifacts": {
        "raw_form": "raw/form_data_${RUN_ID}.json",
        "processed_form": "processed/form_processed_${RUN_ID}.json",
        "discovery_config": "processed/discovery_config_${RUN_ID}.json",
        "next_phase_script": "processed/execute_phase_01_${RUN_ID}.sh"
    },
    "next_phase": {
        "phase": "01-discover",
        "script": "01-discover/run-discovery.sh",
        "estimated_duration": "5-10 minutes"
    }
}

with open("$metadata_file", 'w') as f:
    json.dump(metadata, f, indent=2)

print("Metadata generated successfully")
EOF
        print_status "Metadata saved to: $metadata_file"
    else
        print_info "Would generate metadata at: $metadata_file"
    fi
}

# Process and validate form data
process_and_validate() {
    print_section "Validating and Processing Form Data"

    local processed_file="$ARTIFACTS_DIR/processed/form_processed_${RUN_ID}.json"

    python3 - <<EOF
import json
import sys
from datetime import datetime

def calculate_confidence(data):
    """Calculate confidence score based on data completeness"""
    confidence = 0
    max_points = 100

    # Required fields (60 points)
    required_fields = [
        'company_name', 'website_url', 'contact_email',
        'industry', 'cloud_provider', 'serving_customers',
        'migration_timeline', 'current_budget'
    ]

    for field in required_fields:
        if data.get(field):
            confidence += 7.5  # 60 points / 8 fields

    # Optional but valuable fields (40 points)
    valuable_fields = {
        'terraform_repo': 10,
        'app_repos': 5,
        'current_hosting': 5,
        'databases': 5,
        'kubernetes_contexts': 5,
        'compliance': 5,
        'special_requirements': 5
    }

    for field, points in valuable_fields.items():
        if data.get(field):
            if isinstance(data[field], list) and len(data[field]) > 0:
                confidence += points
            elif isinstance(data[field], str) and data[field].strip():
                confidence += points

    return min(int(confidence), 100)

def process_repositories(data):
    """Extract and process repository information"""
    repos = {
        'application': [],
        'infrastructure': None,
        'helm': None,
        'cicd': None
    }

    # Application repositories
    if 'app_repos' in data:
        if isinstance(data['app_repos'], list):
            repos['application'] = [r for r in data['app_repos'] if r and r.strip()]
        elif isinstance(data['app_repos'], str) and data['app_repos'].strip():
            # Single repo as string - don't iterate over characters!
            repos['application'] = [data['app_repos'].strip()]
        else:
            repos['application'] = []

    # Infrastructure repos
    repos['infrastructure'] = data.get('terraform_repo', '')
    repos['helm'] = data.get('helm_repo', '')
    repos['cicd'] = data.get('cicd_repo', '')

    return repos

def process_databases(data):
    """Extract database information"""
    databases = []

    # Check if databases field exists and what type it is
    db_field = data.get('databases', '')

    if isinstance(db_field, str) and db_field:
        # Single database as string
        db_type = db_field.lower()
        size = data.get(f'{db_type}_size', 'unknown')
        databases.append({
            'type': db_type,
            'size_gb': size
        })
    elif isinstance(db_field, list):
        # Multiple databases as list
        for db in db_field:
            if db:
                db_type = db.lower()
                size = data.get(f'{db_type}_size', 'unknown')
                databases.append({
                    'type': db_type,
                    'size_gb': size
                })

    # Custom databases
    if 'custom_db_name' in data:
        custom_names = data.get('custom_db_name', [])
        custom_sizes = data.get('custom_db_size', [])
        for i, name in enumerate(custom_names):
            if name:
                databases.append({
                    'type': name,
                    'size_gb': custom_sizes[i] if i < len(custom_sizes) else 'unknown'
                })

    return databases

try:
    with open("$FORM_DATA_FILE", 'r') as f:
        raw_data = json.load(f)

    # Calculate confidence
    confidence = calculate_confidence(raw_data)

    # Process the data
    processed = {
        "run_id": "${RUN_ID}",
        "timestamp": "${TIMESTAMP}",
        "confidence_score": confidence,
        "company": {
            "name": raw_data.get('company_name', ''),
            "website": raw_data.get('website_url', ''),
            "email": raw_data.get('contact_email', ''),
            "industry": raw_data.get('industry', ''),
            "budget": raw_data.get('current_budget', ''),
            "serving_customers": raw_data.get('serving_customers', 'unknown'),
            "timeline": raw_data.get('migration_timeline', '')
        },
        "infrastructure": {
            "current": {
                "hosting": raw_data.get('current_hosting', 'unknown'),
                "hosting_other": raw_data.get('current_hosting_other', ''),
                "regions": raw_data.get('current_regions', '').split(',') if raw_data.get('current_regions') else [],
                "customer_regions": raw_data.get('customer_regions', '').split(',') if raw_data.get('customer_regions') else []
            },
            "target": {
                "provider": raw_data.get('cloud_provider', ''),
                "project": raw_data.get('gcloud_project', '') if raw_data.get('cloud_provider') == 'gcp' else raw_data.get('aws_account', ''),
                "regions": raw_data.get('preferred_target_regions', '').split(',') if raw_data.get('preferred_target_regions') else [],
                "auth_mode": raw_data.get('auth_mode', 'adc')
            }
        },
        "repositories": process_repositories(raw_data),
        "containers": {
            "registries": {
                "gcr": raw_data.get('gcr_registry', ''),
                "ecr": raw_data.get('ecr_registry', ''),
                "acr": raw_data.get('acr_registry', ''),
                "artifact": raw_data.get('artifact_registry', ''),
                "additional": [r for r in raw_data.get('additional_registries', []) if r]
            }
        },
        "kubernetes": {
            "mode": raw_data.get('k8s_mode', 'custom'),
            "contexts": [raw_data.get('k8s_context')] if raw_data.get('k8s_context') else (["current"] if raw_data.get('current_context') else []),
            "providers": [raw_data.get('k8s_provider')] if isinstance(raw_data.get('k8s_provider'), str) else raw_data.get('k8s_provider', [])
        },
        "data": {
            "databases": process_databases(raw_data),
            "total_size_gb": raw_data.get('total_data_size', 0),
            "transfer_window": raw_data.get('data_transfer_window', 'unknown'),
            "billing": {
                "uploaded": bool(raw_data.get('uploaded_files')),
                "files": raw_data.get('uploaded_files', []) if raw_data.get('uploaded_files') else [],
                "note": "Billing data files should be processed in Phase 02 for cost analysis"
            }
        },
        "requirements": {
            "compliance": [raw_data.get('compliance')] if isinstance(raw_data.get('compliance'), str) else raw_data.get('compliance', []),
            "special": raw_data.get('special_requirements', []) if isinstance(raw_data.get('special_requirements'), list) else [],
            "cost_sensitivity": raw_data.get('cost_sensitivity', 'balanced'),
            "reliability": raw_data.get('reliability', 'high'),
            "deployment_model": raw_data.get('deployment_model', 'balanced'),
            "scaling": raw_data.get('scaling_preference', 'automatic'),
            "support": raw_data.get('support_model', 'shared'),
            "downtime_tolerance": raw_data.get('downtime_tolerance', '1_4_hours'),
            "change_freeze": raw_data.get('change_freeze', 'no'),
            "freeze_dates": raw_data.get('freeze_dates', ''),
            "additional": raw_data.get('additional_requirements', '')
        },
        "monitoring": {
            "tools": raw_data.get('monitoring_tools', '').split(',') if raw_data.get('monitoring_tools') else []
        },
        "iac": {
            "available": raw_data.get('iac_mode') == 'has_iac',
            "terraform_repo": raw_data.get('terraform_repo', '')
        }
    }

    # Save processed data
    if "${DRY_RUN}" != "true":
        with open("$processed_file", 'w') as f:
            json.dump(processed, f, indent=2)

    # Output summary
    print(f"\n{'='*60}")
    print(f"ASSESSMENT SUMMARY")
    print(f"{'='*60}")
    print(f"Company: {processed['company']['name']}")
    print(f"Confidence Score: {confidence}%")
    print(f"Current Hosting: {processed['infrastructure']['current']['hosting']}")
    print(f"Target Provider: {processed['infrastructure']['target']['provider']}")
    print(f"Migration Timeline: {processed['company']['timeline']}")
    print(f"Budget Range: {processed['company']['budget']}")
    print(f"Databases: {len(processed['data']['databases'])} types")
    print(f"Repositories: {len(processed['repositories']['application'])} application repos")
    print(f"Compliance: {', '.join(processed['requirements']['compliance']) if processed['requirements']['compliance'] else 'None specified'}")
    print(f"Billing Data: {'Uploaded' if processed['data']['billing']['uploaded'] else 'Not provided'}")
    if processed['data']['billing']['files']:
        print(f"  Files: {', '.join(processed['data']['billing']['files'])}")
    print(f"{'='*60}\n")

    # Store confidence for shell
    with open('/tmp/maestro_confidence.txt', 'w') as f:
        f.write(str(confidence))

except Exception as e:
    print(f"Error processing form: {e}", file=sys.stderr)
    sys.exit(1)
EOF

    # Read confidence score
    if [[ -f /tmp/maestro_confidence.txt ]]; then
        CONFIDENCE=$(cat /tmp/maestro_confidence.txt)
        rm -f /tmp/maestro_confidence.txt
    fi

    print_status "Form data validated and processed"
    print_info "Confidence Score: ${CONFIDENCE}%"
}

# Generate discovery configuration
generate_discovery_config() {
    print_section "Generating Discovery Configuration"

    local config_file="$ARTIFACTS_DIR/processed/discovery_config_${RUN_ID}.json"

    python3 - <<EOF
import json
import sys

try:
    # Read processed form data
    processed_file = "$ARTIFACTS_DIR/processed/form_processed_${RUN_ID}.json"
    with open(processed_file, 'r') as f:
        data = json.load(f)

    # Generate discovery configuration
    config = {
        'version': '1.0',
        'run_id': '${RUN_ID}',
        'timestamp': '${TIMESTAMP}',
        'confidence': data['confidence_score'],
        'discovery': {
            'mode': 'full',
            'provider': data['infrastructure']['target']['provider'],
            'auth': {
                'mode': data['infrastructure']['target']['auth_mode'],
                'project': data['infrastructure']['target'].get('project', ''),
                'region': data['infrastructure']['target']['regions'][0] if data['infrastructure']['target']['regions'] else 'us-central1'
            },
            'scope': {
                'compute': True,
                'storage': True,
                'networking': True,
                'databases': True,
                'kubernetes': bool(data['kubernetes']['contexts']),
                'serverless': True,
                'iam': True
            }
        },
        'repositories': {
            'scan': True,
            'application': data['repositories']['application'],
            'infrastructure': data['repositories']['infrastructure'],
            'helm': data['repositories']['helm'],
            'cicd': data['repositories']['cicd']
        },
        'containers': {
            'registries': [
                r for r in [
                    data['containers']['registries'].get('gcr'),
                    data['containers']['registries'].get('ecr'),
                    data['containers']['registries'].get('acr'),
                    data['containers']['registries'].get('artifact')
                ] + data['containers']['registries'].get('additional', [])
                if r
            ]
        },
        'kubernetes': {
            'enabled': bool(data['kubernetes']['contexts']),
            'contexts': data['kubernetes']['contexts']
        },
        'data': {
            'databases': [db['type'] for db in data['data']['databases']],
            'total_size_gb': data['data']['total_size_gb'],
            'migration_window': data['data']['transfer_window']
        },
        'requirements': {
            'compliance': data['requirements']['compliance'],
            'special': data['requirements']['special'],
            'downtime_tolerance': data['requirements']['downtime_tolerance']
        },
        'output': {
            'format': 'json',
            'artifacts_dir': '${ARTIFACTS_DIR}',
            'reports': ['inventory', 'access', 'dependencies', 'risks']
        }
    }

    # Save configuration
    if "${DRY_RUN}" != "true":
        with open("$config_file", 'w') as f:
            json.dump(config, f, indent=2)
        print(f"Discovery configuration saved to: $config_file")
    else:
        print("Would generate discovery configuration")
        print(json.dumps(config, indent=2))

except Exception as e:
    print(f"Error generating discovery config: {e}", file=sys.stderr)
    sys.exit(1)
EOF

    print_status "Discovery configuration generated"
}

# Generate next phase execution script
generate_next_phase_script() {
    print_section "Generating Next Phase Script"

    local script_file="$ARTIFACTS_DIR/processed/execute_phase_01_${RUN_ID}.sh"

    if [[ "$DRY_RUN" == "false" ]]; then
        cat > "$script_file" << 'SCRIPT'
#!/bin/bash

# Auto-generated script to execute Phase 01 - Discovery
# Generated by Phase 00 on TIMESTAMP_PLACEHOLDER

set -euo pipefail

# Configuration
RUN_ID="RUN_ID_PLACEHOLDER"
CONFIG_FILE="CONFIG_FILE_PLACEHOLDER"
PHASE_01_SCRIPT="PHASE_01_SCRIPT_PLACEHOLDER"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Maestro Phase 01 - Discovery${NC}"
echo -e "${CYAN}  Run ID: ${RUN_ID}${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo

# Check if discovery script exists
if [[ ! -f "$PHASE_01_SCRIPT" ]]; then
    echo "Error: Phase 01 script not found at: $PHASE_01_SCRIPT"
    exit 1
fi

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Discovery config not found at: $CONFIG_FILE"
    exit 1
fi

echo -e "${GREEN}Starting discovery process...${NC}"
echo

# Execute Phase 01
exec "$PHASE_01_SCRIPT" \
    --config "$CONFIG_FILE" \
    --run-id "$RUN_ID" \
    --verbose
SCRIPT

        # Replace placeholders
        sed -i.bak \
            -e "s|RUN_ID_PLACEHOLDER|${RUN_ID}|g" \
            -e "s|CONFIG_FILE_PLACEHOLDER|$ARTIFACTS_DIR/processed/discovery_config_${RUN_ID}.json|g" \
            -e "s|PHASE_01_SCRIPT_PLACEHOLDER|$PROJECT_ROOT/01-discover/run-discovery.sh|g" \
            -e "s|TIMESTAMP_PLACEHOLDER|${TIMESTAMP}|g" \
            "$script_file"

        rm -f "${script_file}.bak"
        chmod +x "$script_file"

        print_status "Next phase script generated: $script_file"
    else
        print_info "Would generate next phase script at: $script_file"
    fi
}

# Generate summary report
generate_summary() {
    print_section "Summary Report"

    local summary_file="$ARTIFACTS_DIR/processed/assessment_summary_${RUN_ID}.json"

    python3 - <<EOF
import json
from datetime import datetime

summary = {
    "run_id": "${RUN_ID}",
    "timestamp": "${TIMESTAMP}",
    "phase": "00-input",
    "status": "completed",
    "confidence_score": ${CONFIDENCE},
    "provider": "${PROVIDER}",
    "auth_mode": "${AUTH_MODE}",
    "artifacts_created": [
        "raw/form_data_${RUN_ID}.json",
        "processed/form_processed_${RUN_ID}.json",
        "processed/discovery_config_${RUN_ID}.json",
        "processed/execute_phase_01_${RUN_ID}.sh",
        "metadata/run_metadata_${RUN_ID}.json"
    ],
    "next_steps": [
        "Review the discovery configuration",
        "Execute Phase 01: ./artifacts/processed/execute_phase_01_${RUN_ID}.sh",
        "Or run directly: ./01-discover/run-discovery.sh --config ./artifacts/processed/discovery_config_${RUN_ID}.json --run-id ${RUN_ID}"
    ],
    "estimated_discovery_time": "5-10 minutes",
    "recommendations": []
}

# Add recommendations based on confidence
if ${CONFIDENCE} < 40:
    summary["recommendations"].append("Low confidence score - consider providing more information")
    summary["recommendations"].append("Add repository URLs for better code analysis")
    summary["recommendations"].append("Specify Kubernetes contexts if using K8s")
elif ${CONFIDENCE} < 70:
    summary["recommendations"].append("Moderate confidence - discovery will proceed with available data")
    summary["recommendations"].append("Consider adding IaC repository for infrastructure analysis")
else:
    summary["recommendations"].append("High confidence score - comprehensive discovery possible")

# Add provider-specific recommendations
if "${PROVIDER}" == "gcp":
    summary["recommendations"].append("Ensure gcloud CLI is authenticated: gcloud auth application-default login")
elif "${PROVIDER}" == "aws":
    summary["recommendations"].append("Ensure AWS CLI is configured: aws configure")
elif "${PROVIDER}" == "azure":
    summary["recommendations"].append("Ensure Azure CLI is authenticated: az login")

if "${DRY_RUN}" != "true":
    with open("$summary_file", 'w') as f:
        json.dump(summary, f, indent=2)

print(json.dumps(summary, indent=2))
EOF

    print_status "Assessment summary generated"
}

# Main execution flow
main() {
    print_header

    # Validate form data file
    if [[ -z "$FORM_DATA_FILE" ]]; then
        print_error "Form data file is required. Use --form-data option."
        usage
    fi

    # Create directory structure
    create_directories

    # Process form data
    process_form_data

    # Generate metadata
    generate_metadata

    # Process and validate
    process_and_validate

    # Generate discovery configuration
    generate_discovery_config

    # Generate next phase script
    generate_next_phase_script

    # Generate summary
    generate_summary

    # Final output
    echo
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ Phase 00 - Input Processing Complete${NC}"
    echo
    echo -e "Run ID:          ${CYAN}${RUN_ID}${NC}"
    echo -e "Confidence:      ${CYAN}${CONFIDENCE}%${NC}"
    echo -e "Provider:        ${CYAN}${PROVIDER}${NC}"
    echo -e "Auth Mode:       ${CYAN}${AUTH_MODE}${NC}"
    echo -e "Artifacts:       ${CYAN}${ARTIFACTS_DIR}${NC}"
    echo
    echo -e "${YELLOW}Next Steps:${NC}"
    echo -e "1. Review discovery configuration:"
    echo -e "   ${CYAN}cat ${ARTIFACTS_DIR}/processed/discovery_config_${RUN_ID}.json${NC}"
    echo
    echo -e "2. Run Phase 01 - Discovery:"
    echo -e "   ${CYAN}${ARTIFACTS_DIR}/processed/execute_phase_01_${RUN_ID}.sh${NC}"
    echo
    echo -e "3. Or run directly:"
    echo -e "   ${CYAN}./01-discover/run-discovery.sh --config ${ARTIFACTS_DIR}/processed/discovery_config_${RUN_ID}.json --run-id ${RUN_ID}${NC}"
    echo
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"

    # Log completion
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "Phase 00 completed at $(date)" >> "$ARTIFACTS_DIR/logs/phase_00_${RUN_ID}.log"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --form-data)
            FORM_DATA_FILE="$2"
            shift 2
            ;;
        --run-id)
            RUN_ID="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Execute main function
main