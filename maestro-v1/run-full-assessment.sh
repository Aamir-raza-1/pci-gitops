#!/bin/bash

#############################################################################
# Maestro Full Assessment Pipeline
# This script automates the complete assessment workflow:
# 1. Picks the latest form submission
# 2. Runs 00-input/process-assessment-v2.sh
# 3. Uses generated discovery config for validate-processing.sh
# 4. Runs 01-access validation with the same config
#############################################################################

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
BASE_DIR="/Users/aamirraza/asr/maestro-v1"
FORM_SUBMISSIONS_DIR="${BASE_DIR}/form_submissions"
INPUT_DIR="${BASE_DIR}/00-input"
ACCESS_DIR="${BASE_DIR}/01-access"
ARTIFACTS_DIR="${BASE_DIR}/artifacts"

# Function to print colored messages
print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# Function to find latest form submission
find_latest_form() {
    local latest_form=$(ls -t "${FORM_SUBMISSIONS_DIR}"/form_data_*.json 2>/dev/null | head -n 1)
    if [ -z "$latest_form" ]; then
        print_error "No form submissions found in ${FORM_SUBMISSIONS_DIR}"
        exit 1
    fi
    echo "$latest_form"
}

# Function to extract run_id from form
get_run_id() {
    local form_file=$1
    local run_id=$(grep -o '"run_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$form_file" | cut -d'"' -f4)
    if [ -z "$run_id" ]; then
        # Fallback: generate from filename
        run_id="maestro_$(basename "$form_file" .json | sed 's/form_data_//')"
    fi
    echo "$run_id"
}

# Function to find latest discovery config
find_discovery_config() {
    local run_id=$1
    local config_file=""

    # First try to find config with exact run_id match
    config_file=$(find "${ARTIFACTS_DIR}/processed" -name "discovery_config_${run_id}.json" 2>/dev/null | head -n 1)

    # If not found, get the latest discovery config
    if [ -z "$config_file" ]; then
        config_file=$(ls -t "${ARTIFACTS_DIR}/processed"/discovery_config_*.json 2>/dev/null | head -n 1)
    fi

    if [ -z "$config_file" ]; then
        print_error "No discovery config found in ${ARTIFACTS_DIR}/processed"
        exit 1
    fi

    echo "$config_file"
}

# Main execution starts here
print_header "MAESTRO FULL ASSESSMENT PIPELINE"
echo "Starting automated assessment workflow..."
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"

# Step 1: Find latest form submission
print_header "STEP 1: FINDING LATEST FORM SUBMISSION"
LATEST_FORM=$(find_latest_form)
print_success "Found latest form: $(basename "$LATEST_FORM")"

# Extract run_id
RUN_ID=$(get_run_id "$LATEST_FORM")
print_info "Run ID: $RUN_ID"

# Display form details
echo -e "\nForm details:"
echo "----------------------------------------"
jq -r '
    "Company: " + (.company_name // "N/A"),
    "Cloud Provider: " + (.cloud_provider // "N/A"),
    "Project/Account: " + ((.gcloud_project // .aws_account) // "N/A"),
    "Submitted: " + (.submitted_at // "Unknown")
' "$LATEST_FORM" 2>/dev/null || cat "$LATEST_FORM"
echo "----------------------------------------"

# Step 2: Copy form to 00-input directory
print_header "STEP 2: PREPARING INPUT"
cp "$LATEST_FORM" "${INPUT_DIR}/"
print_success "Copied form to ${INPUT_DIR}/$(basename "$LATEST_FORM")"

# Step 3: Run process-assessment-v2.sh
print_header "STEP 3: RUNNING PROCESS-ASSESSMENT-V2"
cd "${INPUT_DIR}"

if [ ! -x "process-assessment-v2.sh" ]; then
    print_error "process-assessment-v2.sh not found or not executable"
    exit 1
fi

print_info "Executing process-assessment-v2.sh with form: $(basename "$LATEST_FORM")"
echo ""

# Run the assessment processing with correct --form-data parameter
./process-assessment-v2.sh --form-data "$(basename "$LATEST_FORM")" --run-id "$RUN_ID"
PROCESS_EXIT_CODE=$?

if [ $PROCESS_EXIT_CODE -eq 0 ]; then
    print_success "Process assessment completed successfully"
else
    print_error "Process assessment failed with exit code: $PROCESS_EXIT_CODE"
    exit $PROCESS_EXIT_CODE
fi

# Step 4: Find generated discovery config
print_header "STEP 4: LOCATING DISCOVERY CONFIG"
sleep 2  # Give time for file to be written
DISCOVERY_CONFIG=$(find_discovery_config "$RUN_ID")
print_success "Found discovery config: $(basename "$DISCOVERY_CONFIG")"

# Display config summary
echo -e "\nDiscovery config summary:"
echo "----------------------------------------"
jq -r '
    "Environment: " + .environment,
    "Company: " + .company,
    "Cloud Provider: " + .cloud_provider,
    "Resources Count: " + (.resources | length | tostring)
' "$DISCOVERY_CONFIG" 2>/dev/null || echo "Unable to parse config"
echo "----------------------------------------"

# Step 5: Run validate-processing.sh
print_header "STEP 5: RUNNING VALIDATION"
cd "${INPUT_DIR}"

if [ ! -x "validate-processing.sh" ]; then
    print_error "validate-processing.sh not found or not executable"
    exit 1
fi

print_info "Executing validate-processing.sh with form and discovery config"
echo ""

# validate-processing.sh expects: <form_data.json> <discovery_config.json>
./validate-processing.sh "$(basename "$LATEST_FORM")" "$DISCOVERY_CONFIG"
VALIDATE_EXIT_CODE=$?

if [ $VALIDATE_EXIT_CODE -eq 0 ]; then
    print_success "Validation completed successfully"
else
    print_error "Validation failed with exit code: $VALIDATE_EXIT_CODE"
    # Don't exit here, continue to access validation
fi

# Step 6: Copy discovery config to 01-access
print_header "STEP 6: PREPARING ACCESS VALIDATION"
cp "$DISCOVERY_CONFIG" "${ACCESS_DIR}/"
print_success "Copied discovery config to ${ACCESS_DIR}/$(basename "$DISCOVERY_CONFIG")"

# Step 7: Run 01-access comprehensive-validation.sh
print_header "STEP 7: RUNNING ACCESS VALIDATION"
cd "${ACCESS_DIR}"

if [ ! -x "comprehensive-validation.sh" ]; then
    print_error "comprehensive-validation.sh not found or not executable"
    exit 1
fi

print_info "Executing comprehensive-validation.sh with discovery config"
echo ""

./comprehensive-validation.sh "$(basename "$DISCOVERY_CONFIG")"
ACCESS_EXIT_CODE=$?

if [ $ACCESS_EXIT_CODE -eq 0 ]; then
    print_success "Access validation completed successfully"
else
    print_error "Access validation failed with exit code: $ACCESS_EXIT_CODE"
fi

# Final summary
print_header "ASSESSMENT PIPELINE COMPLETE"
echo "Summary:"
echo "----------------------------------------"
echo "Form processed: $(basename "$LATEST_FORM")"
echo "Run ID: $RUN_ID"
echo "Discovery config: $(basename "$DISCOVERY_CONFIG")"
echo ""
echo "Results:"
print_info "Process Assessment: $([ $PROCESS_EXIT_CODE -eq 0 ] && echo "✓ SUCCESS" || echo "✗ FAILED")"
print_info "Validation: $([ $VALIDATE_EXIT_CODE -eq 0 ] && echo "✓ SUCCESS" || echo "✗ FAILED")"
print_info "Access Validation: $([ $ACCESS_EXIT_CODE -eq 0 ] && echo "✓ SUCCESS" || echo "✗ FAILED")"
echo ""
echo "Artifacts generated in:"
echo "  - ${ARTIFACTS_DIR}/processed/"
echo "  - ${ARTIFACTS_DIR}/access_${RUN_ID}/"
echo ""
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo "----------------------------------------"

# Exit with combined status
if [ $PROCESS_EXIT_CODE -eq 0 ] && [ $VALIDATE_EXIT_CODE -eq 0 ] && [ $ACCESS_EXIT_CODE -eq 0 ]; then
    print_success "All steps completed successfully!"
    exit 0
else
    print_error "Some steps failed. Check the logs above."
    exit 1
fi