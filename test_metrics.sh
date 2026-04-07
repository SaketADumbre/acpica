#!/bin/bash
# Extract test metrics from ASLTS results
# Usage: ./test_metrics.sh

RESULTS_DIR="/workspaces/acpica/tests/aslts/tmp/RESULTS"

# Get the most recent result
LATEST=$(ls -t "$RESULTS_DIR" | head -1)

if [ -z "$LATEST" ]; then
    echo "No test results found"
    exit 1
fi

SUMMARY_FILE="$RESULTS_DIR/$LATEST/Summary"

if [ ! -f "$SUMMARY_FILE" ]; then
    echo "Summary file not found: $SUMMARY_FILE"
    exit 1
fi

# Extract totals from the end of the Summary file
echo "=== ASLTS Test Results: $LATEST ==="
tail -20 "$SUMMARY_FILE" | grep -A 10 "^TOTAL:"
