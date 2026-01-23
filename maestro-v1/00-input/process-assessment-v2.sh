#!/bin/bash

# Maestro Phase 00 - Input Processing V2
# Improved version with accurate field mapping and no script generation

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
FORM_DATA_FILE=""
RUN_ID="maestro_${TIMESTAMP}"
DRY_RUN=false
VERBOSE=false

# Print functions
print_header() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Maestro Phase 00 - Input Processing V2${NC}"
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
    --form-data FILE    Path to form data JSON file (required)
    --run-id ID         Custom run ID (default: maestro_TIMESTAMP)
    --dry-run           Don't create files, just validate
    --verbose           Enable verbose output
    --help              Show this help message

Example:
    $0 --form-data form_submissions/form_data_20260120.json
    $0 --form-data data.json --run-id custom_run_001 --dry-run
EOF
    exit 0
}

# Parse arguments
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
        --help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$FORM_DATA_FILE" ]]; then
    print_error "Form data file is required"
    usage
fi

if [[ ! -f "$FORM_DATA_FILE" ]]; then
    print_error "Form data file not found: $FORM_DATA_FILE"
    exit 1
fi

# Create directory structure
create_directories() {
    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$ARTIFACTS_DIR"/{raw,processed,metadata}
        mkdir -p "$ARTIFACTS_DIR"/access_${RUN_ID}
    fi
}

# Process form data with accurate field mapping
process_form_data() {
    print_section "Processing Form Data"

    local raw_file="$ARTIFACTS_DIR/raw/form_data_${RUN_ID}.json"
    local processed_file="$ARTIFACTS_DIR/processed/form_processed_${RUN_ID}.json"
    local config_file="$ARTIFACTS_DIR/processed/discovery_config_${RUN_ID}.json"

    # Copy raw data
    if [[ "$DRY_RUN" == "false" ]]; then
        cp "$FORM_DATA_FILE" "$raw_file"
        print_status "Raw form data saved"
    fi

    # Process with Python for accurate mapping
    python3 - "$FORM_DATA_FILE" "$processed_file" "$config_file" "$RUN_ID" "$TIMESTAMP" "$DRY_RUN" <<'PYTHON_END'
import json
import sys
import os

form_file = sys.argv[1]
processed_file = sys.argv[2]
config_file = sys.argv[3]
run_id = sys.argv[4]
timestamp = sys.argv[5]
dry_run = sys.argv[6] == "true"

with open(form_file, 'r') as f:
    raw = json.load(f)

# Helper function to check if field has meaningful value
def has_value(field):
    """Check if field has a meaningful value (not empty, not 'unknown', not None)"""
    if field is None:
        return False
    if isinstance(field, str):
        return field.strip() != '' and field.lower() not in ['unknown', 'none', 'n/a']
    if isinstance(field, list):
        return len(field) > 0 and any(has_value(item) for item in field)
    if isinstance(field, dict):
        return any(has_value(v) for v in field.values())
    return bool(field)

# Calculate confidence score based on actual data provided
confidence = 0
confidence_items = []

# Company info
if has_value(raw.get('company_name')):
    confidence += 10
    confidence_items.append('company_name')

# Cloud provider and project
if has_value(raw.get('cloud_provider')):
    confidence += 15
    confidence_items.append('cloud_provider')

if has_value(raw.get('gcloud_project')) or has_value(raw.get('aws_account')):
    confidence += 15
    confidence_items.append('project_id')

# Auth mode
auth_mode = raw.get('auth_mode', 'adc')
if auth_mode == 'service_account':
    if has_value(raw.get('service_account_key')):
        confidence += 10
        confidence_items.append('service_account')
elif auth_mode == 'adc':
    confidence += 5
    confidence_items.append('auth_mode')

# Repositories
app_repos = [r.strip() for r in (raw.get('app_repos', '') or '').split(',') if r.strip()]
infra_repos = [r.strip() for r in (raw.get('infra_repos', '') or '').split(',') if r.strip()]
helm_repos = [r.strip() for r in (raw.get('helm_repos', '') or '').split(',') if r.strip()]

if app_repos:
    confidence += 10
    confidence_items.append('app_repos')
if infra_repos:
    confidence += 10
    confidence_items.append('infra_repos')

# Kubernetes - check multiple conditions
k8s_mode = raw.get('k8s_mode', 'none')
k8s_enabled = (
    has_value(raw.get('kubernetes_clusters')) or
    k8s_mode == 'current' or
    has_value(raw.get('k8s_context'))
)
if k8s_enabled:
    confidence += 10
    confidence_items.append('kubernetes')

# Databases - check both field names
db_field = raw.get('database_types') or raw.get('databases')
if has_value(db_field):
    confidence += 10
    confidence_items.append('databases')

# Uploaded files
uploaded_files = raw.get('uploaded_files', [])
if uploaded_files:
    confidence += 10
    confidence_items.append('uploaded_docs')

# IAC mode
has_iac = raw.get('iac_mode') == 'has_iac'
if has_iac and has_value(raw.get('terraform_repo')):
    confidence += 5
    confidence_items.append('terraform')

# Websites
websites = [w.strip() for w in (raw.get('websites', '') or '').split(',') if w.strip()]
if websites:
    confidence += 5
    confidence_items.append('websites')

print(f"Confidence Score: {confidence}%")
print(f"Confidence factors: {', '.join(confidence_items)}")

# Container registries
gcr_registry = raw.get('gcr_registry', '')
ecr_registry = raw.get('ecr_registry', '')
acr_registry = raw.get('acr_registry', '')
artifact_registry = raw.get('artifact_registry', '')
has_containers = any([has_value(r) for r in [gcr_registry, ecr_registry, acr_registry, artifact_registry]])

# Determine what needs validation
needs_access_validation = {
    'cloud_auth': has_value(raw.get('cloud_provider')),
    'kubernetes': k8s_enabled,
    'databases': has_value(db_field),
    'repositories': bool(app_repos or infra_repos),
    'storage': has_value(raw.get('cloud_provider')),  # Always check if cloud provider set
    'terraform': has_iac and has_value(raw.get('terraform_repo')),
    'containers': has_containers,
    'only_docs': uploaded_files and confidence <= 20  # Only docs, minimal other info
}

# Build discovery configuration with accurate field mapping
discovery_config = {
    'version': '2.0',
    'run_id': run_id,
    'timestamp': timestamp,
    'confidence': confidence,
    'confidence_factors': confidence_items,
    'source': 'form_submission',

    'discovery': {
        'mode': 'targeted' if confidence < 50 else 'full',
        'provider': raw.get('cloud_provider', 'unknown'),
        'auth': {
            'mode': auth_mode,
            'project': raw.get('gcloud_project', '') if raw.get('cloud_provider') == 'gcp' else raw.get('aws_account', ''),
            'region': raw.get('preferred_target_regions', 'us-central1').split(',')[0].strip() if raw.get('preferred_target_regions') else 'us-central1',
            'service_account_key': raw.get('service_account_key', '') if auth_mode == 'service_account' else ''
        },
        'scope': {
            # Only enable if explicitly provided data for each
            'compute': has_value(raw.get('cloud_provider')),
            'storage': has_value(raw.get('cloud_provider')) and not needs_access_validation['only_docs'],
            'networking': has_value(raw.get('cloud_provider')) and not needs_access_validation['only_docs'],
            'databases': bool(has_value(db_field)),
            'kubernetes': k8s_enabled,  # Use the calculated k8s_enabled flag
            'serverless': has_value(raw.get('cloud_provider')) and not needs_access_validation['only_docs'],
            'iam': has_value(raw.get('cloud_provider')) and not needs_access_validation['only_docs'],
            'repositories': bool(app_repos or infra_repos or helm_repos),
            'websites': bool(websites),
            'terraform': has_iac and bool(raw.get('terraform_repo')),
            'containers': has_containers
        }
    },

    'repositories': {
        'scan': bool(app_repos or infra_repos or helm_repos),
        'application': app_repos,
        'infrastructure': infra_repos,
        'helm': helm_repos,
        'cicd': raw.get('cicd_repo', ''),
        'terraform': raw.get('terraform_repo', '') if has_iac else ''
    },

    'kubernetes': {
        'enabled': k8s_enabled,
        'mode': raw.get('k8s_mode', 'none'),
        'contexts': (
            ['current'] if k8s_mode == 'current' else
            [raw.get('k8s_context', '')] if has_value(raw.get('k8s_context')) else []
        ),
        'clusters': raw.get('kubernetes_clusters', '').split(',') if has_value(raw.get('kubernetes_clusters')) else []
    },

    'databases': {
        'enabled': has_value(db_field),
        'types': [t.strip() for t in (db_field or '').split(',') if t.strip()]
    },

    'websites': {
        'enabled': bool(websites),
        'urls': websites
    },

    'containers': {
        'enabled': has_containers,
        'registries': {
            'gcr': gcr_registry,
            'ecr': ecr_registry,
            'acr': acr_registry,
            'artifact': artifact_registry
        }
    },

    'iac': {
        'available': has_iac,
        'mode': raw.get('iac_mode', 'no_iac'),
        'terraform_repo': raw.get('terraform_repo', '') if has_iac else ''
    },

    'uploaded_docs': {
        'available': bool(uploaded_files),
        'files': raw.get('uploaded_files_details', []),
        'billing_reports': [f for f in uploaded_files if 'billing' in f.lower() or 'cost' in f.lower()],
        'architecture_docs': [f for f in uploaded_files if 'architecture' in f.lower() or 'diagram' in f.lower()]
    },

    'validation_required': needs_access_validation,

    'metadata': {
        'company_name': raw.get('company_name', ''),
        'form_version': raw.get('form_version', '1.0'),
        'submitted_at': raw.get('submitted_at', ''),
        'migration_timeline': raw.get('migration_timeline', ''),
        'downtime_tolerance': raw.get('downtime_tolerance', ''),
        'compliance': raw.get('compliance', []) if isinstance(raw.get('compliance'), list) else [raw.get('compliance')] if raw.get('compliance') else []
    }
}

# Save files if not dry run
if not dry_run:
    # Save discovery config
    with open(config_file, 'w') as f:
        json.dump(discovery_config, f, indent=2)
    print(f"Discovery config saved to: {config_file}")

    # Save processed form (simplified version)
    processed = {
        'run_id': run_id,
        'timestamp': timestamp,
        'confidence_score': confidence,
        'raw_form': raw,
        'discovery_config': discovery_config
    }
    with open(processed_file, 'w') as f:
        json.dump(processed, f, indent=2)
    print(f"Processed form saved to: {processed_file}")

# Output summary
print("\n" + "="*60)
print("PROCESSING SUMMARY")
print("="*60)
print(f"Company: {raw.get('company_name', 'Unknown')}")
print(f"Provider: {raw.get('cloud_provider', 'Unknown')}")
print(f"Project/Account: {discovery_config['discovery']['auth']['project'] or 'Not provided'}")
print(f"Auth Mode: {auth_mode}")
print(f"IAC Available: {has_iac}")
print(f"Kubernetes: {discovery_config['kubernetes']['enabled']}")
print(f"Databases: {len(discovery_config['databases']['types'])} types")
print(f"Repositories: {len(app_repos)} app, {len(infra_repos)} infra")
print(f"Uploaded Files: {len(uploaded_files)}")
print(f"Only Docs Uploaded: {needs_access_validation['only_docs']}")
print("\nScope Enabled:")
for key, enabled in discovery_config['discovery']['scope'].items():
    status = "✓" if enabled else "✗"
    print(f"  [{status}] {key}")
print("="*60)

PYTHON_END

    print_status "Form data processing complete"
}

# Generate access validation configuration
generate_access_config() {
    print_section "Generating Access Validation Config"

    local config_file="$ARTIFACTS_DIR/processed/discovery_config_${RUN_ID}.json"
    local access_file="$ARTIFACTS_DIR/access_${RUN_ID}/access_config.json"

    if [[ "$DRY_RUN" == "false" ]]; then
        # Extract validation requirements from discovery config
        python3 - "$config_file" "$access_file" <<'PYTHON_ACCESS'
import json
import sys

config_file = sys.argv[1]
access_file = sys.argv[2]

with open(config_file, 'r') as f:
    config = json.load(f)

validation = config.get('validation_required', {})
scope = config['discovery']['scope']

# Build access validation config
access_config = {
    'run_id': config['run_id'],
    'timestamp': config['timestamp'],
    'provider': config['discovery']['provider'],
    'auth_mode': config['discovery']['auth']['mode'],
    'project': config['discovery']['auth']['project'],

    'validations': {
        'core_tools': {
            'required': True,
            'tools': ['bash', 'python3', 'curl', 'jq']
        },
        'cloud_auth': {
            'required': validation.get('cloud_auth', False),
            'skip_if_docs_only': validation.get('only_docs', False)
        },
        'kubernetes': {
            'required': scope.get('kubernetes', False),
            'contexts': config['kubernetes'].get('contexts', [])
        },
        'databases': {
            'required': scope.get('databases', False),
            'types': config['databases'].get('types', [])
        },
        'repositories': {
            'required': scope.get('repositories', False),
            'repos': {
                'application': config['repositories'].get('application', []),
                'infrastructure': config['repositories'].get('infrastructure', [])
            }
        },
        'terraform': {
            'required': scope.get('terraform', False),
            'repo': config['iac'].get('terraform_repo', '')
        }
    },

    'skip_all_if_docs_only': validation.get('only_docs', False),

    'next_phase': 'discovery' if not validation.get('only_docs') else 'document_analysis'
}

with open(access_file, 'w') as f:
    json.dump(access_config, f, indent=2)

print(f"Access validation config saved to: {access_file}")
PYTHON_ACCESS

        print_status "Access validation config generated"
    fi
}

# Generate summary without .sh scripts
generate_summary() {
    print_section "Generating Summary"

    local summary_file="$ARTIFACTS_DIR/processed/assessment_summary_${RUN_ID}.json"
    local config_file="$ARTIFACTS_DIR/processed/discovery_config_${RUN_ID}.json"

    if [[ "$DRY_RUN" == "false" ]]; then
        python3 - "$config_file" "$summary_file" <<'PYTHON_SUMMARY'
import json
import sys

config_file = sys.argv[1]
summary_file = sys.argv[2]

with open(config_file, 'r') as f:
    config = json.load(f)

summary = {
    'run_id': config['run_id'],
    'timestamp': config['timestamp'],
    'phase': '00-input',
    'status': 'completed',
    'confidence_score': config['confidence'],
    'provider': config['discovery']['provider'],
    'auth_mode': config['discovery']['auth']['mode'],

    'artifacts_created': [
        f"raw/form_data_{config['run_id']}.json",
        f"processed/form_processed_{config['run_id']}.json",
        f"processed/discovery_config_{config['run_id']}.json",
        f"access_{config['run_id']}/access_config.json",
        f"processed/assessment_summary_{config['run_id']}.json"
    ],

    'next_steps': [
        "Review the discovery configuration",
        f"Run ACCESS validation: ./01-access/comprehensive-validation.sh artifacts/processed/discovery_config_{config['run_id']}.json",
        "If validation passes, proceed with discovery phase",
        "For document-only uploads, proceed to document analysis"
    ],

    'validation_scope': {k: v for k, v in config['discovery']['scope'].items() if v},

    'recommendations': []
}

# Add recommendations based on confidence
if config['confidence'] < 30:
    summary['recommendations'].append("Low confidence score - consider providing more information")
if not config['repositories']['application']:
    summary['recommendations'].append("Add repository URLs for better code analysis")
if config['kubernetes']['enabled'] and not config['kubernetes']['contexts']:
    summary['recommendations'].append("Specify Kubernetes contexts for cluster access")
if config['discovery']['auth']['mode'] == 'adc':
    summary['recommendations'].append("Ensure gcloud CLI is authenticated: gcloud auth application-default login")
if config['discovery']['auth']['mode'] == 'service_account' and not config['discovery']['auth'].get('service_account_key'):
    summary['recommendations'].append("Service account key file needed for authentication")

with open(summary_file, 'w') as f:
    json.dump(summary, f, indent=2)

print(f"Assessment summary saved to: {summary_file}")
PYTHON_SUMMARY

        print_status "Assessment summary generated"
    fi
}

# Main execution
main() {
    print_header

    # Validate form data
    print_section "Validating Form Data"
    if [[ ! -s "$FORM_DATA_FILE" ]]; then
        print_error "Form data file is empty"
        exit 1
    fi

    # Check if it's valid JSON
    if ! python3 -m json.tool "$FORM_DATA_FILE" > /dev/null 2>&1; then
        print_error "Invalid JSON in form data file"
        exit 1
    fi
    print_status "Form data is valid JSON"

    # Create directories
    create_directories

    # Process form data
    process_form_data

    # Generate access validation config
    generate_access_config

    # Generate summary (no .sh scripts)
    generate_summary

    # Final output
    print_section "Processing Complete"
    echo -e "${GREEN}✓ Phase 00 - Input Processing Complete${NC}"
    echo
    echo "Artifacts created in: $ARTIFACTS_DIR"
    echo
    echo "Next steps:"
    echo "1. Review discovery config: $ARTIFACTS_DIR/processed/discovery_config_${RUN_ID}.json"
    echo "2. Run ACCESS validation: ./01-access/comprehensive-validation.sh $ARTIFACTS_DIR/processed/discovery_config_${RUN_ID}.json"
    echo

    if [[ "$VERBOSE" == "true" ]]; then
        echo "Discovery config content:"
        cat "$ARTIFACTS_DIR/processed/discovery_config_${RUN_ID}.json"
    fi
}

# Run main
main