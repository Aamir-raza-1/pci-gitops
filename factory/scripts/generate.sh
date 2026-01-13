#!/bin/bash
set -euo pipefail

# This script orchestrates the full, robust "Helm -> Mutate -> Cleanup -> Validate" pipeline,
# correctly using the make-golden.sh script.

# --- Inputs & Configuration ---
REQUEST_FILE="${1:?ERROR: Path to request file is required.}"
OUTPUT_DIR="${2:?ERROR: Path to output directory is required.}"
CHART_DIR="generator/chart"
POLICY_LAYER_ABSTRACTION="generator/policies/10-abstractions/"
POLICY_LAYER_MUTATE="generator/policies/15-compliance-mutations/"
POLICY_LAYER_VALIDATE="generator/policies/20-compliance-validations/"

# --- File Paths ---
HELM_OUTPUT_FILE="${OUTPUT_DIR}/00-helm.yaml"
MESSY_MUTATED_FILE="${OUTPUT_DIR}/01-messy-mutated.yaml"
GOLDEN_MANIFEST_FILE="${OUTPUT_DIR}/02-golden.yaml"
POLICY_REPORT_FILE="${OUTPUT_DIR}/03-policy-report.yaml"

# --- Setup ---
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

# --- Pipeline ---
echo "INFO: Starting full generation for ${REQUEST_FILE}"

# 1. Helm Template
echo "  -> Step 1: Running helm template..."
helm template ${CHART_DIR} -f ${REQUEST_FILE} > ${HELM_OUTPUT_FILE}

# 2. Kyverno Mutate
echo "  -> Step 2: Running Kyverno mutations..."
kyverno apply ${POLICY_LAYER_ABSTRACTION} ${POLICY_LAYER_MUTATE} --resource ${HELM_OUTPUT_FILE} > ${MESSY_MUTATED_FILE}

# 3. Cleanup with your make-golden.sh script (Corrected Usage)
echo "  -> Step 3: Cleaning and merging with make-golden.sh..."
# Run your script in the output directory so it can read the input and write its output.
(cd ${OUTPUT_DIR} && ../../scripts/make-golden.sh 01-messy-mutated.yaml)
# Move the output file to the correct final name.
mv "${OUTPUT_DIR}/golden.yaml" "${GOLDEN_MANIFEST_FILE}"

# 4. Kyverno Validate
echo "  -> Step 4: Running Kyverno validations..."
(
  set +e
  kyverno apply ${POLICY_LAYER_VALIDATE} --resource ${GOLDEN_MANIFEST_FILE} --policy-report > ${POLICY_REPORT_FILE}
  exit_code=$?
  if [ $exit_code -gt 1 ]; then
    echo "ERROR: Kyverno validation command failed with exit code ${exit_code}."
    exit $exit_code
  fi
)

# Check the summary of the report for failures.
if grep -q "fail: [1-9]" "${POLICY_REPORT_FILE}"; then
  echo "ERROR: Validation failed! See report in ${POLICY_REPORT_FILE}"
  cat "${POLICY_REPORT_FILE}"
  exit 1
else
  echo "SUCCESS: Generation and validation complete for ${REQUEST_FILE}"
fi