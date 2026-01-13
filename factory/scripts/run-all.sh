#!/bin/bash
set -euo pipefail

# This script discovers and runs all test cases.
for t in tests/cases/*; do
  if [ -d "$t" ]; then
    ./scripts/run-case.sh "$t"
  fi
done
