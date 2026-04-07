#!/bin/bash
# Git bisect script to find regression in ASLTS test suite
# The regression is between 7/5/2022 (good) and 8/18/2022 (bad)

set -e

GOOD_COMMIT="761b6f167"  # Last good: 2022-07-05, "AcpiHelp: Fix fault using -v option standalone."
BAD_COMMIT="fd6b8f895"   # First bad: 2022-08-18, "As per Issue #783"
WORKDIR="/workspaces/acpica"

echo "===== ACPICA ASLTS Regression Bisect ====="
echo ""
echo "Good commit: $GOOD_COMMIT (2022-07-05)"
echo "Bad commit:  $BAD_COMMIT (2022-08-18)"
echo ""

# Make sure we start clean
cd "$WORKDIR"
git status

# Step 1: Verify the good commit
echo ""
echo "Step 1: Testing GOOD commit ($GOOD_COMMIT)..."
echo "========================================"
git checkout "$GOOD_COMMIT"
echo "Commit: $(git log -1 --oneline)"
echo "Running tests (this may take a few minutes)..."
tests/aslts.sh 2>&1 | tail -20
bash test_metrics.sh
GOOD_METRICS=$(tail -20 tests/aslts/tmp/RESULTS/$(ls -t tests/aslts/tmp/RESULTS | head -1)/Summary | grep -A 8 "^TOTAL:")
echo ""
echo "=== GOOD METRICS ==="
echo "$GOOD_METRICS"

# Step 2: Verify the bad commit
echo ""
echo "Step 2: Testing BAD commit ($BAD_COMMIT)..."
echo "========================================"
git checkout "$BAD_COMMIT"
echo "Commit: $(git log -1 --oneline)"
echo "Running tests (this may take a few minutes)..."
tests/aslts.sh 2>&1 | tail -20
bash test_metrics.sh
BAD_METRICS=$(tail -20 tests/aslts/tmp/RESULTS/$(ls -t tests/aslts/tmp/RESULTS | head -1)/Summary | grep -A 8 "^TOTAL:")
echo ""
echo "=== BAD METRICS ==="
echo "$BAD_METRICS"

# Step 3: Start bisect
echo ""
echo "Step 3: Starting git bisect..."
echo "================================"
git bisect start
git bisect good "$GOOD_COMMIT"
git bisect bad "$BAD_COMMIT"

# Step 4: Automated bisect test
echo ""
echo "Step 4: Running automated bisect..."
echo "===================================="
echo "Bisect will run until it finds the culprit commit."
echo ""

BISECT_SCRIPT=$(mktemp)
cat > "$BISECT_SCRIPT" << 'EOF'
#!/bin/bash
# Bisect test script
echo "Testing commit: $(git log -1 --oneline)"
cd /workspaces/acpica

# Run ASLTS tests
tests/aslts.sh > /dev/null 2>&1

# Extract pass count from results
LATEST=$(ls -t tests/aslts/tmp/RESULTS | head -1)
SUMMARY_FILE="tests/aslts/tmp/RESULTS/$LATEST/Summary"

# Get PASS count
PASS_COUNT=$(tail -20 "$SUMMARY_FILE" | grep "PASS" | head -1 | awk '{print $NF}')

echo "PASS count: ${PASS_COUNT:-0}"

# Compare with the good baseline (should be around 1105)
# If PASS < 1100, it's bad, otherwise good
if [ "$PASS_COUNT" -lt 1100 ]; then
    echo "FAIL - Test regression detected"
    exit 1  # bisect bad
else
    echo "PASS - Tests passing"
    exit 0  # bisect good
fi
EOF

chmod +x "$BISECT_SCRIPT"

git bisect run "$BISECT_SCRIPT"

echo ""
echo "===== BISECT COMPLETE ====="
echo ""
echo "The culprit commit has been found:"
git log -1 --format="Commit: %H%nAuthor: %an%nDate: %ai%nMessage: %B"

# Show the changes
echo ""
echo "Changes in this commit:"
git show --stat

# Cleanup
rm "$BISECT_SCRIPT"
git bisect reset

echo ""
echo "Bisect script complete. Check the output above for the culprit commit."
