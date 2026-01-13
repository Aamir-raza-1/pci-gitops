#!/bin/bash
set -euo pipefail
TEST_DIR="${1:?ERROR: Path to test directory is required. ex: tests/policies/pci-dss}"
echo "INFO: Running Kyverno tests in ${TEST_DIR}"
kyverno test "${TEST_DIR}"
