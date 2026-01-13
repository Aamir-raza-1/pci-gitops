#!/bin/bash
set -euo pipefail
REQUEST_FILE="${1:?ERROR: Path to request file is required.}"
OUTPUT_FILE="${2:-/dev/stdout}"
CHART_DIR="generator/chart"
POLICY_LAYER_ABSTRACTION="generator/policies/10-abstractions/"
POLICY_LAYER_COMPLIANCE="generator/policies/15-compliance-mutations/"

echo "INFO: Generating and Mutating manifests for ${REQUEST_FILE}" >&2

# This is the core pipeline: Helm output is piped to Kyverno for mutation.
helm template ${CHART_DIR} -f ${REQUEST_FILE} \
  | kyverno apply ${POLICY_LAYER_ABSTRACTION} ${POLICY_LAYER_COMPLIANCE} --resource - > ${OUTPUT_FILE}

echo "INFO: Generation and mutation successful. Output sent to ${OUTPUT_FILE}" >&2