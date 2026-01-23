#!/bin/bash

# Maestro Migration Assessment - Master Orchestration Script
# Runs all phases: 00-Input → 01-Access → 02-Discovery → 03-Recommend

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
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

# Input variables
FORM_DATA=""
RUN_ID="maestro_${TIMESTAMP}"
SKIP_ACCESS=false
SKIP_DISCOVERY=false
SKIP_RECOMMEND=false
DRY_RUN=false

print_header() {
    echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║            Maestro Migration Assessment Pipeline              ║${NC}"
    echo -e "${MAGENTA}║                    Build → Analyze → Migrate                  ║${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo
}

print_phase() {
    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1" >&2; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_info() { echo -e "${BLUE}[i]${NC} $1"; }

# Run Phase 00 - Input Processing
run_phase_00() {
    print_phase "Phase 00: INPUT PROCESSING"

    if [[ ! -f "$FORM_DATA" ]]; then
        print_error "Form data file not found: $FORM_DATA"
        return 1
    fi

    print_info "Processing form data..."
    ./00-input/process-assessment.sh \
        --form-data "$FORM_DATA" \
        --run-id "$RUN_ID" \
        $(if $DRY_RUN; then echo "--dry-run"; fi)

    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        print_status "Phase 00 completed successfully"
    else
        print_error "Phase 00 failed with exit code: $exit_code"
        return $exit_code
    fi

    return 0
}

# Run Phase 01 - Access Validation
run_phase_01() {
    print_phase "Phase 01: ACCESS VALIDATION"

    if $SKIP_ACCESS; then
        print_warning "Skipping access validation (--skip-access)"
        return 0
    fi

    local config_file="$ARTIFACTS_DIR/processed/discovery_config_${RUN_ID}.json"

    if [[ ! -f "$config_file" ]]; then
        print_error "Discovery config not found: $config_file"
        return 1
    fi

    print_info "Validating permissions and access..."
    ./01-access/check-access.sh \
        --config "$config_file" \
        --run-id "$RUN_ID"

    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        print_status "Phase 01 completed successfully"
    elif [[ $exit_code -eq 4 ]]; then
        print_warning "Missing permissions - review access guide"
        print_info "Continue with limited discovery"
    else
        print_error "Phase 01 failed with exit code: $exit_code"
        return $exit_code
    fi

    return 0
}

# Run Phase 02 - Discovery
run_phase_02() {
    print_phase "Phase 02: INFRASTRUCTURE DISCOVERY"

    if $SKIP_DISCOVERY; then
        print_warning "Skipping discovery phase (--skip-discovery)"
        return 0
    fi

    local config_file="$ARTIFACTS_DIR/processed/discovery_config_${RUN_ID}.json"
    local access_validation="$ARTIFACTS_DIR/access/access_validation.json"

    print_info "Discovering infrastructure and analyzing resources..."
    ./02-discovery/discovery.sh \
        --config "$config_file" \
        --run-id "$RUN_ID" \
        --access-validation "$access_validation"

    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        print_status "Phase 02 completed successfully"
    else
        print_error "Phase 02 failed with exit code: $exit_code"
        return $exit_code
    fi

    return 0
}

# Run Phase 03 - Recommendations
run_phase_03() {
    print_phase "Phase 03: RECOMMENDATIONS & ROADMAP"

    if $SKIP_RECOMMEND; then
        print_warning "Skipping recommendation phase (--skip-recommend)"
        return 0
    fi

    local config_file="$ARTIFACTS_DIR/processed/discovery_config_${RUN_ID}.json"
    local discovery_dir="$ARTIFACTS_DIR/discovery"

    print_info "Generating migration recommendations and roadmap..."
    ./03-recommend/recommend.sh \
        --config "$config_file" \
        --run-id "$RUN_ID" \
        --discovery-dir "$discovery_dir"

    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        print_status "Phase 03 completed successfully"
    else
        print_error "Phase 03 failed with exit code: $exit_code"
        return $exit_code
    fi

    return 0
}

# Generate final summary
generate_summary() {
    echo
    echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║                   ASSESSMENT COMPLETE                         ║${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo

    echo -e "${GREEN}✅ All phases completed successfully${NC}"
    echo
    echo -e "${YELLOW}Run ID:${NC} ${CYAN}$RUN_ID${NC}"
    echo -e "${YELLOW}Duration:${NC} ${CYAN}$SECONDS seconds${NC}"
    echo

    echo -e "${YELLOW}Key Artifacts:${NC}"
    echo -e "  📊 Assessment Summary: ${CYAN}$ARTIFACTS_DIR/processed/assessment_summary_${RUN_ID}.json${NC}"
    echo -e "  🔐 Access Report:      ${CYAN}$ARTIFACTS_DIR/access/access_guide.md${NC}"
    echo -e "  🔍 Discovery Results:  ${CYAN}$ARTIFACTS_DIR/discovery/discovery_summary.md${NC}"
    echo -e "  📋 Migration Roadmap:  ${CYAN}$ARTIFACTS_DIR/recommendations/migration_roadmap.md${NC}"
    echo -e "  📄 Final Report:       ${CYAN}$ARTIFACTS_DIR/recommendations/final_assessment.md${NC}"
    echo

    echo -e "${GREEN}Next Steps:${NC}"
    echo -e "  1. Review the final assessment report"
    echo -e "  2. Share findings with stakeholders"
    echo -e "  3. Plan migration timeline"
    echo -e "  4. Begin pilot migration"
    echo

    # Create a quick summary file
    cat > "$ARTIFACTS_DIR/maestro_run_${RUN_ID}.summary" << EOF
Maestro Migration Assessment Summary
=====================================
Run ID: ${RUN_ID}
Timestamp: ${TIMESTAMP}
Status: SUCCESS

Phases Completed:
✅ Phase 00: Input Processing
✅ Phase 01: Access Validation
✅ Phase 02: Infrastructure Discovery
✅ Phase 03: Recommendations

View full report:
${ARTIFACTS_DIR}/recommendations/final_assessment.md
EOF

    echo -e "${MAGENTA}Thank you for using Maestro Migration Assessment!${NC}"
}

# Main execution
main() {
    print_header

    # Check prerequisites
    if [[ ! -x "./00-input/process-assessment.sh" ]]; then
        print_error "Phase scripts not found or not executable"
        print_info "Making scripts executable..."
        chmod +x ./00-input/process-assessment.sh 2>/dev/null || true
        chmod +x ./01-access/check-access.sh 2>/dev/null || true
        chmod +x ./02-discovery/discovery.sh 2>/dev/null || true
        chmod +x ./03-recommend/recommend.sh 2>/dev/null || true
    fi

    # Create artifacts directory
    mkdir -p "$ARTIFACTS_DIR"

    # Run phases
    local failed=false

    if ! run_phase_00; then
        failed=true
        print_error "Pipeline failed at Phase 00"
    elif ! run_phase_01; then
        failed=true
        print_error "Pipeline failed at Phase 01"
    elif ! run_phase_02; then
        failed=true
        print_error "Pipeline failed at Phase 02"
    elif ! run_phase_03; then
        failed=true
        print_error "Pipeline failed at Phase 03"
    fi

    if $failed; then
        echo
        print_error "Assessment pipeline failed!"
        print_info "Check logs and error messages above"
        exit 1
    fi

    # Generate summary
    generate_summary
}

# Show usage
usage() {
    cat << EOF
Usage: $0 --form-data <json_file> [OPTIONS]

Run the complete Maestro migration assessment pipeline.

Required:
    --form-data FILE        Path to form submission JSON file

Options:
    --run-id ID            Custom run ID (default: maestro_TIMESTAMP)
    --skip-access          Skip Phase 01 (Access Validation)
    --skip-discovery       Skip Phase 02 (Discovery)
    --skip-recommend       Skip Phase 03 (Recommendations)
    --dry-run              Run in dry-run mode (no actual changes)
    -h, --help             Show this help message

Examples:
    # Run complete assessment
    $0 --form-data form_submissions/form_data.json

    # Custom run ID
    $0 --form-data form_data.json --run-id custom_run_001

    # Skip certain phases
    $0 --form-data form_data.json --skip-discovery --skip-recommend

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --form-data)
            FORM_DATA="$2"
            shift 2
            ;;
        --run-id)
            RUN_ID="$2"
            shift 2
            ;;
        --skip-access)
            SKIP_ACCESS=true
            shift
            ;;
        --skip-discovery)
            SKIP_DISCOVERY=true
            shift
            ;;
        --skip-recommend)
            SKIP_RECOMMEND=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$FORM_DATA" ]]; then
    print_error "Missing required argument: --form-data"
    echo "Use --help for usage information"
    exit 1
fi

# Run main
main