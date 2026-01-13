#!/bin/bash
set -euo pipefail

# This script runs 'helm template' to generate the full manifest from a request file.
# It is the first, foundational step of the GTC workflow.

REQUEST_FILE="${1:?ERROR: Path to request file is required. ex: requests/alpha-prod-comprehensive.yaml}"
OUTPUT_FILE="${2:-/dev/stdout}" # Default to stdout if no output file is provided
CHART_DIR="generator/chart"

echo "INFO: Generating Helm-only manifests for ${REQUEST_FILE}" >&2

# Run helm template.
# It will fail automatically if the request.yaml is invalid due to the schema or 'required' checks.
helm template ${CHART_DIR} -f ${REQUEST_FILE} > ${OUTPUT_FILE}

echo "INFO: Helm generation successful. Output sent to ${OUTPUT_FILE}" >&2
