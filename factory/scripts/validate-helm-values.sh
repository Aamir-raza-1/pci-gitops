#!/bin/bash
set -euo pipefail

# This script validates that a rendered Helm chart contains no placeholder values.

REQUEST_FILE="${1:?ERROR: Path to request file is required.}"
CHART_DIR="generator/chart"
TEMP_FILE=$(mktemp)

# List of forbidden placeholder strings.
# Add any new placeholders here.
FORBIDDEN_STRINGS=(
  "placeholder-"
  "__"
  "my-kms-project"
)

echo "INFO: Validating Helm values for ${REQUEST_FILE}"

# 1. Run helm template. It will fail automatically if schema validation or 'required' fields fail.
echo "  -> Running helm template (with schema validation)..."
helm template ${CHART_DIR} -f ${REQUEST_FILE} > ${TEMP_FILE}
echo "  -> Helm template successful."

# 2. Check for forbidden placeholder strings in the output.
echo "  -> Checking for forbidden placeholder strings..."
for placeholder in "${FORBIDDEN_STRINGS[@]}"; do
  if grep -q "${placeholder}" ${TEMP_FILE}; then
    echo "ERROR: Found forbidden placeholder string '${placeholder}' in rendered manifest!"
    grep -n "${placeholder}" ${TEMP_FILE}
    rm ${TEMP_FILE}
    exit 1
  fi
done

echo "  -> No forbidden strings found."
rm ${TEMP_FILE}
echo "INFO: Helm values validation PASSED for ${REQUEST_FILE}"
