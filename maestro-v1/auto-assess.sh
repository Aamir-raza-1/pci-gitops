#!/bin/bash

#############################################################################
# Auto Assessment Script
# Automated pipeline for Maestro assessment workflow
#
# Features:
# - Automatic latest form selection
# - Step-by-step execution with error handling
# - Progress tracking and detailed logging
# - Artifact management
#
# Usage:
#   ./auto-assess.sh                    # Use latest form
#   ./auto-assess.sh form_data.json     # Use specific form
#   ./auto-assess.sh --check            # Check prerequisites
#############################################################################

# Enable strict error handling
set -euo pipefail
IFS=$'\n\t'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BASE_DIR="${SCRIPT_DIR}"
readonly FORM_DIR="${BASE_DIR}/form_submissions"
readonly INPUT_DIR="${BASE_DIR}/00-input"
readonly ACCESS_DIR="${BASE_DIR}/01-access"
readonly ARTIFACTS_DIR="${BASE_DIR}/artifacts"
readonly PROCESSED_DIR="${ARTIFACTS_DIR}/processed"
readonly LOG_FILE="${BASE_DIR}/assessment_$(date +%Y%m%d_%H%M%S).log"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${CYAN}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

# Header printing function
print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}$1${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
}

# Check prerequisites
check_prerequisites() {
    local missing_deps=()

    # Check required commands
    for cmd in jq grep sed awk; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    # Check required directories
    for dir in "$INPUT_DIR" "$ACCESS_DIR" "$FORM_DIR"; do
        if [ ! -d "$dir" ]; then
            log_error "Directory not found: $dir"
            return 1
        fi
    done

    # Check required scripts
    local scripts=(
        "${INPUT_DIR}/process-assessment-v2.sh"
        "${INPUT_DIR}/validate-processing.sh"
        "${ACCESS_DIR}/comprehensive-validation.sh"
    )

    for script in "${scripts[@]}"; do
        if [ ! -x "$script" ]; then
            log_error "Script not found or not executable: $script"
            return 1
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Install with: brew install ${missing_deps[*]}"
        return 1
    fi

    log_success "All prerequisites satisfied"
    return 0
}

# Find the latest form submission
find_latest_form() {
    local form_file=""

    if [ $# -eq 1 ] && [ "$1" != "--check" ]; then
        # Specific form provided
        if [ -f "$1" ]; then
            form_file="$1"
        elif [ -f "${FORM_DIR}/$1" ]; then
            form_file="${FORM_DIR}/$1"
        else
            log_error "Form file not found: $1"
            return 1
        fi
    else
        # Find latest form
        form_file=$(find "$FORM_DIR" -name "form_data_*.json" -type f -print0 2>/dev/null |
                    xargs -0 ls -t 2>/dev/null | head -n 1)

        if [ -z "$form_file" ]; then
            log_error "No form submissions found in $FORM_DIR"
            return 1
        fi
    fi

    echo "$form_file"
}

# Extract run ID from form
get_run_id() {
    local form_file="$1"
    local run_id=""

    if [ -f "$form_file" ]; then
        run_id=$(jq -r '.run_id // empty' "$form_file" 2>/dev/null)
    fi

    if [ -z "$run_id" ]; then
        # Generate fallback run ID
        run_id="maestro_$(date +%Y%m%d_%H%M%S)"
        log_warning "Could not extract run_id, using: $run_id"
    fi

    echo "$run_id"
}

# Display form information
display_form_info() {
    local form_file="$1"

    if ! command -v jq &> /dev/null; then
        log_warning "jq not installed, showing raw form"
        head -20 "$form_file"
        return
    fi

    echo "Form Details:" | tee -a "$LOG_FILE"
    echo "────────────────────────────────────────" | tee -a "$LOG_FILE"
    jq -r '
        "Company: " + (.company_name // "N/A"),
        "Cloud Provider: " + (.cloud_provider // "N/A"),
        "Project/Account: " + ((.gcloud_project // .aws_account) // "N/A"),
        "K8s Clusters: " + (.kubernetes_clusters // "N/A"),
        "Database Types: " + (.database_types // "N/A"),
        "Submitted: " + (.submitted_at // "Unknown")
    ' "$form_file" 2>/dev/null | tee -a "$LOG_FILE" || echo "Unable to parse form"
    echo "────────────────────────────────────────" | tee -a "$LOG_FILE"
}

# Execute a step with error handling
execute_step() {
    local step_name="$1"
    local step_cmd="$2"
    local allow_failure="${3:-false}"

    log_info "Executing: $step_name"

    if eval "$step_cmd" >> "$LOG_FILE" 2>&1; then
        log_success "$step_name completed"
        return 0
    else
        local exit_code=$?
        if [ "$allow_failure" = "true" ]; then
            log_warning "$step_name failed with exit code $exit_code (continuing)"
            return 0
        else
            log_error "$step_name failed with exit code $exit_code"
            return $exit_code
        fi
    fi
}

# Clean up function
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Pipeline failed. Check log file: $LOG_FILE"
    fi
}

# Main execution
main() {
    # Set up error handling
    trap cleanup EXIT

    # Start logging
    log "Starting Maestro Assessment Pipeline"
    log "Script version: 1.0.0"
    log "Working directory: $BASE_DIR"

    # Check for --check flag
    if [ $# -eq 1 ] && [ "$1" = "--check" ]; then
        print_header "CHECKING PREREQUISITES"
        check_prerequisites
        exit $?
    fi

    # Check prerequisites
    print_header "PREREQUISITE CHECK"
    if ! check_prerequisites; then
        exit 1
    fi

    # Find form to process
    print_header "FORM SELECTION"
    FORM_FILE=$(find_latest_form "$@")
    if [ -z "$FORM_FILE" ]; then
        exit 1
    fi
    log_success "Selected form: $(basename "$FORM_FILE")"

    # Extract run ID
    RUN_ID=$(get_run_id "$FORM_FILE")
    log_info "Run ID: $RUN_ID"

    # Display form information
    display_form_info "$FORM_FILE"

    # Create artifacts directories
    mkdir -p "$PROCESSED_DIR" "${ARTIFACTS_DIR}/access_${RUN_ID}"

    # Step 1: Copy and process assessment
    print_header "STEP 1: PROCESS ASSESSMENT"
    cp "$FORM_FILE" "$INPUT_DIR/"
    cd "$INPUT_DIR"
    execute_step "process-assessment-v2.sh" "./process-assessment-v2.sh --form-data '$(basename "$FORM_FILE")' --run-id '$RUN_ID'"
    cd "$BASE_DIR"

    # Step 2: Find discovery config
    print_header "STEP 2: LOCATE DISCOVERY CONFIG"
    DISCOVERY_CONFIG=$(find "$PROCESSED_DIR" -name "discovery_config_*.json" -type f -print0 2>/dev/null |
                       xargs -0 ls -t 2>/dev/null | head -n 1)

    if [ -z "$DISCOVERY_CONFIG" ]; then
        log_error "Discovery config not generated"
        exit 1
    fi
    log_success "Found config: $(basename "$DISCOVERY_CONFIG")"

    # Step 3: Validate processing
    print_header "STEP 3: VALIDATE PROCESSING"
    cd "$INPUT_DIR"
    # validate-processing.sh expects: <form_data.json> <discovery_config.json>
    execute_step "validate-processing.sh" "./validate-processing.sh '$(basename "$FORM_FILE")' '$DISCOVERY_CONFIG'" true
    cd "$BASE_DIR"

    # Step 4: Access validation
    print_header "STEP 4: ACCESS VALIDATION"
    cp "$DISCOVERY_CONFIG" "$ACCESS_DIR/"
    cd "$ACCESS_DIR"
    execute_step "comprehensive-validation.sh" "./comprehensive-validation.sh '$(basename "$DISCOVERY_CONFIG")'" true
    cd "$BASE_DIR"

    # Final summary
    print_header "PIPELINE COMPLETE"
    echo "Summary:" | tee -a "$LOG_FILE"
    echo "────────────────────────────────────────" | tee -a "$LOG_FILE"
    echo "Form: $(basename "$FORM_FILE")" | tee -a "$LOG_FILE"
    echo "Run ID: $RUN_ID" | tee -a "$LOG_FILE"
    echo "Discovery Config: $(basename "$DISCOVERY_CONFIG")" | tee -a "$LOG_FILE"
    echo "Log File: $LOG_FILE" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Artifacts:" | tee -a "$LOG_FILE"
    echo "  • Processed: $PROCESSED_DIR" | tee -a "$LOG_FILE"
    echo "  • Access: ${ARTIFACTS_DIR}/access_${RUN_ID}" | tee -a "$LOG_FILE"
    echo "────────────────────────────────────────" | tee -a "$LOG_FILE"

    log_success "Assessment pipeline completed successfully!"
}

# Run main function
main "$@"