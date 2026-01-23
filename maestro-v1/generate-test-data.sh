#!/bin/bash

# Generate test form data for Maestro assessment
# This creates a sample JSON file that simulates form submission

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Timestamp for unique filenames
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="form_data_${TIMESTAMP}.json"

# Default test data
COMPANY_NAME="${1:-Test Company Inc}"
PROVIDER="${2:-gcp}"
AUTH_MODE="${3:-adc}"

echo -e "${BLUE}Generating test form data...${NC}"

cat > "$OUTPUT_FILE" << EOF
{
  "form_version": "2.0",
  "extracted_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "company_name": "${COMPANY_NAME}",
  "website_url": "https://test-company.com",
  "contact_email": "admin@test-company.com",
  "industry": "technology",
  "serving_customers": "yes",
  "migration_timeline": "medium",
  "current_budget": "10000-25000",
  "cloud_provider": "${PROVIDER}",
  "auth_mode": "${AUTH_MODE}",
  "current_hosting": "on_premises",
  "current_regions": "us-east-1, eu-west-1",
  "customer_regions": "Global",
  "preferred_target_regions": "us-central1, europe-west1",
  "iac_mode": "has_iac",
  "terraform_repo": "https://github.com/test-company/infrastructure",
  "helm_repo": "https://github.com/test-company/helm-charts",
  "cicd_repo": "https://github.com/test-company/pipelines",
  "app_repos": [
    "https://github.com/test-company/frontend",
    "https://github.com/test-company/backend",
    "https://github.com/test-company/api"
  ],
  "gcr_registry": "gcr.io/test-project",
  "artifact_registry": "us-docker.pkg.dev/test-project/containers",
  "k8s_provider": ["gke", "gke", "gke"],
  "k8s_context": ["dev-cluster", "staging-cluster", "prod-cluster"],
  "k8s_mode": "custom",
  "databases": ["postgresql", "redis", "mongodb"],
  "postgresql_size": "500",
  "redis_size": "50",
  "mongodb_size": "1000",
  "total_data_size": "1550",
  "data_transfer_window": "zero",
  "monitoring_tools": "Prometheus, Grafana, AlertManager",
  "compliance": ["SOX", "GDPR"],
  "special_requirements": ["secrets_management", "sensitive_data"],
  "cost_sensitivity": "balanced",
  "reliability": "high",
  "deployment_model": "balanced",
  "scaling_preference": "automatic",
  "support_model": "shared",
  "downtime_tolerance": "near_zero",
  "change_freeze": "no",
  "additional_requirements": "Need zero-downtime migration with full rollback capability"
}
EOF

echo -e "${GREEN}✓ Test data generated: ${OUTPUT_FILE}${NC}"
echo
echo -e "${YELLOW}Next steps:${NC}"
echo -e "1. Review the generated data:"
echo -e "   ${BLUE}cat ${OUTPUT_FILE} | jq .${NC}"
echo
echo -e "2. Run Phase 00 with this data:"
echo -e "   ${BLUE}./00-input/process-assessment.sh --form-data ./${OUTPUT_FILE}${NC}"
echo
echo -e "3. Or customize the test data:"
echo -e "   ${BLUE}$0 \"My Company\" aws service_account${NC}"
echo