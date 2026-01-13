#!/bin/bash
set -euo pipefail

# This script runs a single test case.
# It runs generate.sh and then checks the output against expectations.

CASE_DIR="${1:?ERROR: Path to test case directory is required. ex: tests/cases/aci-prod}"
REQUEST_FILE="${CASE_DIR}/request.yaml"
EXPECTATIONS_FILE="${CASE_DIR}/expectations.sh"
TEMP_DIR="temp/${CASE_DIR}"

echo "INFO: Running test case: ${CASE_DIR}"

# Run the generation pipeline
./scripts/generate.sh "${REQUEST_FILE}" "${TEMP_DIR}"

# Source the expectations file, which contains assertion functions
source "${EXPECTATIONS_FILE}"

# Run the assertions
echo "  -> Running assertions..."
assert_golden_manifest_contains "kind: ContainerCluster"
assert_policy_report_has "pass" "4" # Example: expecting 4 validation rules to pass

echo "INFO: Test case PASSED: ${CASE_DIR}"
