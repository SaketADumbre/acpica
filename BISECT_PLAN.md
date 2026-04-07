# ACPICA ASLTS Regression Bisect - Plan & Execution Guide

## Objective
Find the single commit between 7/5/2022 (last good ASLTS build) and 8/18/2022 (first bad ASLTS build) that caused the ASL Test Suite regression.

## Timeline & Identified Commits

**Last Good Commit:**
- Commit: `761b6f167` 
- Date: 2022-07-05 13:43:46
- Message: "AcpiHelp: Fix fault using -v option standalone."

**First Bad Commit:**
- Commit: `fd6b8f895`
- Date: 2022-08-18 12:50:05
- Message: "As per Issue #783"

**Commits Between:** ~20 commits in the timeframe

## Test Metrics

The ASLTS test generates a Summary file with these key metrics:
- **PASS**: Count of passing tests
- **FAIL**: Count of failing tests  
- **BLOCKED**: Count of blocked tests
- **SKIPPED**: Count of skipped tests

Current baseline (2026-04-06 from master):
- PASS: 1105
- FAIL: 37
- BLOCKED: 12

The regression will show a **lower PASS count** and/or **higher FAIL count**.

## Execution Plan

### Phase 1: Verification (Quick ~10 minutes)
1. Checkout good commit (761b6f167) and run full ASLTS test suite
   - Record the PASS/FAIL/BLOCKED metrics
   - This establishes the baseline

2. Checkout bad commit (fd6b8f895) and run full ASLTS test suite
   - Record the PASS/FAIL/BLOCKED metrics
   - Confirm metrics are worse than good baseline

### Phase 2: Automated Bisect (~30-60 minutes)
The `bisect_aslts.sh` script will:
1. Start git bisect with good and bad commits
2. Automatically test each midpoint commit
3. Stop when the culprit commit is found

### Phase 3: Verification & Analysis (~5 minutes)
1. Review the culprit commit details
2. Show what changed in that commit
3. Verify by reverting the commit and re-testing

## Scripts Provided

### 1. `/workspaces/acpica/test_metrics.sh`
Extracts and displays test metrics from the latest ASLTS results.

Usage:
```bash
./test_metrics.sh
```

Output: Shows TOTAL section from Summary file with PASS/FAIL counts

### 2. `/workspaces/acpica/bisect_aslts.sh`
Automated bisect script that:
- Tests the good commit
- Tests the bad commit
- Runs git bisect automatically
- Finds the culprit commit
- Shows detailed analysis of the culprit

Usage:
```bash
cd /workspaces/acpica
./bisect_aslts.sh
```

This will take 30-60 minutes total.

## Alternative: Manual Interactive Bisect

If you prefer manual control, you can run bisect step-by-step:

```bash
cd /workspaces/acpica

# Start bisect
git bisect start
git bisect good 761b6f167
git bisect bad fd6b8f895

# For each commit, run tests and mark as good/bad
tests/aslts.sh
./test_metrics.sh

# If tests pass: git bisect good
# If tests fail: git bisect bad

# When done: git bisect reset
```

## Estimated Time

- **Full ASLTS test per commit:** ~3-5 minutes
- **Number of bisect iterations:** ~4-5 (log2 of 20 commits)
- **Total time:** 15-25 minutes for automated bisect

## Next Steps

Please choose one of the following:

1. **Run automated bisect**: Execute `./bisect_aslts.sh` 
   - Fully automated, takes ~30-60 minutes
   - Finds and analyzes the culprit commit
   - Recommended for efficiency

2. **Run manual bisect**: Use the manual commands above
   - More control over each step
   - Useful if you want to examine intermediate commits

3. **Run verification first**: Just test the boundary commits
   - Quick check (10 minutes) to confirm regression
   - Then decide on automated vs manual bisect

Which approach would you prefer?
