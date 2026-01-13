#!/bin/bash
set -euo pipefail
REQUEST_FILE="${1:?ERROR: Path to request file is required.}"
OUTPUT_FILE="${2:-/dev/stdout}"
CHART_DIR="generator/chart"
echo "INFO: Generating Helm manifests for ${REQUEST_FILE}" >&2
helm template ${CHART_DIR} -f ${REQUEST_FILE} > ${OUTPUT_FILE}
echo "INFO: Helm generation successful. Output sent to ${OUTPUT_FILE}" >&2
