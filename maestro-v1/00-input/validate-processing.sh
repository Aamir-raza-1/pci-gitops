#!/bin/bash

# Validation script to cross-check form data with generated configs
# Ensures nothing is missed or incorrectly disabled

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Arguments
FORM_FILE="${1:-}"
CONFIG_FILE="${2:-}"

if [[ -z "$FORM_FILE" ]] || [[ -z "$CONFIG_FILE" ]]; then
    echo "Usage: $0 <form_data.json> <discovery_config.json>"
    echo "Example: $0 form_submissions/form_data_XXX.json artifacts/processed/discovery_config_XXX.json"
    exit 1
fi

echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Form to Config Validation Check${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo

# Python validation script
python3 - "$FORM_FILE" "$CONFIG_FILE" <<'PYTHON_VALIDATE'
import json
import sys

form_file = sys.argv[1]
config_file = sys.argv[2]

# Load files
with open(form_file, 'r') as f:
    form = json.load(f)

with open(config_file, 'r') as f:
    config = json.load(f)

# Track issues
issues = []
warnings = []
correct = []

print("=" * 60)
print("VALIDATION REPORT")
print("=" * 60)

# Helper to check non-empty value
def has_value(val):
    if val is None:
        return False
    if isinstance(val, str):
        return val.strip() != '' and val.lower() not in ['', 'none', 'unknown']
    if isinstance(val, list):
        return len(val) > 0
    return bool(val)

# 1. Check Kubernetes
k8s_mode = form.get('k8s_mode', 'none')
k8s_clusters = form.get('kubernetes_clusters', '')
k8s_context = form.get('k8s_context', '')
current_context_selected = k8s_mode == 'current'

# Kubernetes should be enabled if:
# - kubernetes_clusters has value OR
# - k8s_mode is 'current' OR
# - k8s_context is provided
should_enable_k8s = (
    has_value(k8s_clusters) or
    current_context_selected or
    has_value(k8s_context)
)

k8s_enabled = config['discovery']['scope'].get('kubernetes', False)

print(f"\n1. KUBERNETES VALIDATION")
print(f"   Form k8s_mode: {k8s_mode}")
print(f"   Form k8s_clusters: {k8s_clusters}")
print(f"   Form k8s_context: {k8s_context}")
print(f"   Should enable: {should_enable_k8s}")
print(f"   Config enabled: {k8s_enabled}")

if should_enable_k8s and not k8s_enabled:
    issues.append(f"❌ Kubernetes should be ENABLED (mode={k8s_mode}, clusters={k8s_clusters})")
elif not should_enable_k8s and k8s_enabled:
    issues.append(f"❌ Kubernetes should be DISABLED (no k8s data in form)")
else:
    correct.append("✓ Kubernetes scope correct")

# 2. Check Databases - check both field names
db_types = form.get('database_types', '') or form.get('databases', '')
should_enable_db = has_value(db_types)
db_enabled = config['discovery']['scope'].get('databases', False)

print(f"\n2. DATABASE VALIDATION")
print(f"   Form database_types: {db_types}")
print(f"   Should enable: {should_enable_db}")
print(f"   Config enabled: {db_enabled}")

if should_enable_db and not db_enabled:
    issues.append(f"❌ Databases should be ENABLED (types={db_types})")
elif not should_enable_db and db_enabled:
    issues.append(f"❌ Databases should be DISABLED (no database types)")
else:
    correct.append("✓ Database scope correct")

# 3. Check Container Registries
gcr = form.get('gcr_registry', '')
ecr = form.get('ecr_registry', '')
acr = form.get('acr_registry', '')
artifact = form.get('artifact_registry', '')

has_registries = any([has_value(gcr), has_value(ecr), has_value(acr), has_value(artifact)])
config_registries = config.get('containers', {}).get('registries', [])

print(f"\n3. CONTAINER REGISTRIES VALIDATION")
print(f"   Form GCR: {gcr}")
print(f"   Form ECR: {ecr}")
print(f"   Form ACR: {acr}")
print(f"   Form Artifact: {artifact}")
print(f"   Has registries: {has_registries}")
print(f"   Config registries: {config_registries}")

if has_registries and not config_registries:
    issues.append(f"❌ Container registries MISSING in config (gcr={gcr})")
else:
    correct.append("✓ Container registries handled")

# 4. Check Repositories
app_repos = form.get('app_repos', '')
infra_repos = form.get('infra_repos', '')
helm_repos = form.get('helm_repos', '')
terraform_repo = form.get('terraform_repo', '')

should_enable_repos = any([
    has_value(app_repos),
    has_value(infra_repos),
    has_value(helm_repos)
])

repos_enabled = config['discovery']['scope'].get('repositories', False)

print(f"\n4. REPOSITORIES VALIDATION")
print(f"   Form app_repos: {app_repos}")
print(f"   Form infra_repos: {infra_repos}")
print(f"   Form helm_repos: {helm_repos}")
print(f"   Should enable: {should_enable_repos}")
print(f"   Config enabled: {repos_enabled}")

if should_enable_repos and not repos_enabled:
    issues.append(f"❌ Repositories should be ENABLED")
elif not should_enable_repos and repos_enabled:
    issues.append(f"❌ Repositories should be DISABLED")
else:
    correct.append("✓ Repository scope correct")

# 5. Check IAC/Terraform
iac_mode = form.get('iac_mode', 'no_iac')
has_iac = iac_mode == 'has_iac'
terraform_enabled = config['discovery']['scope'].get('terraform', False)

print(f"\n5. IAC/TERRAFORM VALIDATION")
print(f"   Form iac_mode: {iac_mode}")
print(f"   Form terraform_repo: {terraform_repo}")
print(f"   Has IAC: {has_iac}")
print(f"   Config terraform enabled: {terraform_enabled}")

if has_iac and has_value(terraform_repo) and not terraform_enabled:
    issues.append(f"❌ Terraform should be ENABLED (iac_mode={iac_mode}, repo={terraform_repo})")
elif not has_iac and terraform_enabled:
    issues.append(f"❌ Terraform should be DISABLED (no IAC)")
else:
    correct.append("✓ Terraform scope correct")

# 6. Check Auth Mode
auth_mode = form.get('auth_mode', 'adc')
config_auth_mode = config['discovery']['auth'].get('mode', '')

print(f"\n6. AUTH MODE VALIDATION")
print(f"   Form auth_mode: {auth_mode}")
print(f"   Config auth_mode: {config_auth_mode}")

if auth_mode != config_auth_mode:
    issues.append(f"❌ Auth mode mismatch: form={auth_mode}, config={config_auth_mode}")
else:
    correct.append("✓ Auth mode correct")

# 7. Check Project/Account
cloud_provider = form.get('cloud_provider', '')
gcp_project = form.get('gcloud_project', '')
aws_account = form.get('aws_account', '')
config_project = config['discovery']['auth'].get('project', '')

print(f"\n7. PROJECT/ACCOUNT VALIDATION")
print(f"   Provider: {cloud_provider}")
print(f"   Form gcp_project: {gcp_project}")
print(f"   Form aws_account: {aws_account}")
print(f"   Config project: {config_project}")

if cloud_provider == 'gcp' and has_value(gcp_project) and gcp_project != config_project:
    issues.append(f"❌ GCP project mismatch: form={gcp_project}, config={config_project}")
elif cloud_provider == 'aws' and has_value(aws_account) and aws_account != config_project:
    issues.append(f"❌ AWS account mismatch: form={aws_account}, config={config_project}")
else:
    correct.append("✓ Project/Account correct")

# 8. Check Websites
websites = form.get('websites', '')
should_enable_websites = has_value(websites)
websites_enabled = config['discovery']['scope'].get('websites', False)

print(f"\n8. WEBSITES VALIDATION")
print(f"   Form websites: {websites}")
print(f"   Should enable: {should_enable_websites}")
print(f"   Config enabled: {websites_enabled}")

if should_enable_websites and not websites_enabled:
    issues.append(f"❌ Websites should be ENABLED")
elif not should_enable_websites and websites_enabled:
    issues.append(f"❌ Websites should be DISABLED")
else:
    correct.append("✓ Websites scope correct")

# 9. Check validation_required flags
validation_required = config.get('validation_required', {})

print(f"\n9. VALIDATION FLAGS CHECK")
print(f"   Cloud auth required: {validation_required.get('cloud_auth', False)}")
print(f"   Kubernetes required: {validation_required.get('kubernetes', False)}")
print(f"   Databases required: {validation_required.get('databases', False)}")
print(f"   Repositories required: {validation_required.get('repositories', False)}")

# Cross-check validation flags
if should_enable_k8s != validation_required.get('kubernetes', False):
    warnings.append(f"⚠️  Kubernetes validation flag mismatch")

if should_enable_db != validation_required.get('databases', False):
    warnings.append(f"⚠️  Database validation flag mismatch")

if should_enable_repos != validation_required.get('repositories', False):
    warnings.append(f"⚠️  Repository validation flag mismatch")

# 10. Check for ignored fields
print(f"\n10. CHECKING FOR IGNORED FIELDS")

# List of important fields to check
important_fields = [
    'company_name',
    'cloud_provider',
    'gcloud_project',
    'aws_account',
    'kubernetes_clusters',
    'database_types',
    'app_repos',
    'infra_repos',
    'gcr_registry',
    'ecr_registry',
    'terraform_repo',
    'websites'
]

for field in important_fields:
    if has_value(form.get(field)):
        # Check if this field should affect config
        if field in ['gcr_registry', 'ecr_registry', 'acr_registry']:
            if not config.get('containers', {}).get('registries'):
                warnings.append(f"⚠️  Field '{field}' has value but not in containers config")

        print(f"   {field}: {'✓ has value' if has_value(form.get(field)) else '- empty'}")

# Summary
print("\n" + "=" * 60)
print("VALIDATION SUMMARY")
print("=" * 60)

if not issues and not warnings:
    print("✅ ALL VALIDATIONS PASSED!")
    print(f"\nCorrect mappings: {len(correct)}")
    for item in correct:
        print(f"  {item}")
else:
    if issues:
        print(f"\n❌ CRITICAL ISSUES FOUND: {len(issues)}")
        for issue in issues:
            print(f"  {issue}")

    if warnings:
        print(f"\n⚠️  WARNINGS: {len(warnings)}")
        for warning in warnings:
            print(f"  {warning}")

    if correct:
        print(f"\n✓ Correct mappings: {len(correct)}")
        for item in correct:
            print(f"  {item}")

# Recommendation
print("\n" + "=" * 60)
print("RECOMMENDATIONS")
print("=" * 60)

if issues:
    print("1. Fix the processing script to handle:")
    if any("Kubernetes" in i for i in issues):
        print("   - Enable kubernetes when k8s_mode='current' or k8s_context provided")
    if any("Database" in i for i in issues):
        print("   - Enable databases when database_types has value")
    if any("registries" in i for i in issues):
        print("   - Process container registry fields (gcr, ecr, acr)")
    if any("Repositories" in i for i in issues):
        print("   - Enable repositories when repos provided")
else:
    print("✅ Form processing is working correctly!")

# Exit with error if critical issues
if issues:
    sys.exit(1)

PYTHON_VALIDATE