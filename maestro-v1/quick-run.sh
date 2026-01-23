#!/bin/bash

#############################################################################
# Quick Run Script - Simplified version of the full assessment pipeline
# Usage: ./quick-run.sh [form_file]
# If no form file specified, uses the latest one
#############################################################################

set -e

# Base directory
BASE_DIR="/Users/aamirraza/asr/maestro-v1"
cd "$BASE_DIR"

# Check if a specific form file was provided
if [ $# -eq 1 ]; then
    FORM_FILE="$1"
    if [ ! -f "$FORM_FILE" ]; then
        echo "Error: Form file not found: $FORM_FILE"
        exit 1
    fi
    echo "Using specified form: $FORM_FILE"
else
    # Find latest form
    FORM_FILE=$(ls -t form_submissions/form_data_*.json 2>/dev/null | head -n 1)
    if [ -z "$FORM_FILE" ]; then
        echo "Error: No form submissions found"
        exit 1
    fi
    echo "Using latest form: $FORM_FILE"
fi

# Extract run_id for tracking
RUN_ID=$(grep -o '"run_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$FORM_FILE" | cut -d'"' -f4 || echo "maestro_$(date +%Y%m%d_%H%M%S)")

echo "================================================"
echo "Starting Maestro Assessment Pipeline"
echo "Form: $(basename "$FORM_FILE")"
echo "Run ID: $RUN_ID"
echo "================================================"

# Step 1: Process assessment
echo -e "\n[1/3] Processing assessment..."
cp "$FORM_FILE" 00-input/
cd 00-input
./process-assessment-v2.sh --form-data "$(basename "$FORM_FILE")" --run-id "$RUN_ID"
cd ..

# Step 2: Validate processing
echo -e "\n[2/3] Running validation..."
DISCOVERY_CONFIG=$(ls -t artifacts/processed/discovery_config_*.json 2>/dev/null | head -n 1)
if [ -z "$DISCOVERY_CONFIG" ]; then
    echo "Error: Discovery config not found"
    exit 1
fi
cd 00-input
# validate-processing.sh expects: <form_data.json> <discovery_config.json>
./validate-processing.sh "$(basename "$FORM_FILE")" "../$DISCOVERY_CONFIG"
cd ..

# Step 3: Access validation
echo -e "\n[3/3] Running access validation..."
cp "$DISCOVERY_CONFIG" 01-access/
cd 01-access
./comprehensive-validation.sh "$(basename "$DISCOVERY_CONFIG")"
cd ..

echo -e "\n================================================"
echo "Pipeline completed successfully!"
echo "Results in: artifacts/"
echo "================================================"