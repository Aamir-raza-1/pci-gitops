#!/bin/bash
set -euo pipefail
# This script generates the manifest for this specific layer test.
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
helm template generator/chart -f "${DIR}/request.yaml" > "${DIR}/zz-output.yaml"
echo "INFO: Layer 2 test manifest generated at ${DIR}/zz-output.yaml"
