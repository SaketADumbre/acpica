#!/bin/bash
set -euo pipefail

# Normalized ASLTS probe runner
# - uses existing built binaries via tests/aslts.sh -u
# - avoids stale summaries by selecting files modified after run start
# - emits one-line CSV-style checkpoint rows for resumable investigation

cd /workspaces/acpica

OUT=/workspaces/acpica/aslts_normalized_probe_results.txt
: > "$OUT"

echo "run_utc,commit,exit_code,summary_found,pass,fail,blocked,tests,test_cases,test_collections,warning" >> "$OUT"

extract_total_block() {
    local summary_file="$1"
    awk '
        /^TOTAL:/ {in_total=1; print; next}
        in_total==1 {
            if ($0 ~ /^$/) {exit}
            print
        }
    ' "$summary_file"
}

extract_field() {
    local label="$1"
    local block="$2"
    echo "$block" | awk -v key="$label" '$1==key {print $3; exit}'
}

extract_meta() {
    local label="$1"
    local block="$2"
    echo "$block" | sed -n "s/^    ${label}[[:space:]]*:[[:space:]]*//p" | head -1
}

probe_commit() {
    local commit="$1"
    local run_utc rc summary pass fail blocked tests tcases tcols warn total_block

    run_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    start_epoch=$(date +%s)

    git checkout "$commit" >/dev/null 2>&1

    rm -rf tests/aslts/tmp/RESULTS/* 2>/dev/null || true

    set +e
    tests/aslts.sh -u > "/tmp/aslts_norm_${commit}.log" 2>&1
    rc=$?
    set -e

    summary=$(find tests/aslts/tmp/RESULTS -type f -name Summary -newermt "@${start_epoch}" 2>/dev/null | sort | tail -1 || true)

    if [[ -n "$summary" && -f "$summary" ]]; then
        total_block=$(extract_total_block "$summary")
        pass=$(extract_field "PASS" "$total_block")
        fail=$(extract_field "FAIL" "$total_block")
        blocked=$(extract_field "BLOCKED" "$total_block")
        tests=$(extract_field "Tests" "$total_block")
        tcases=$(extract_meta "Test Cases" "$total_block")
        tcols=$(extract_meta "Test Collections" "$total_block")
        warn=$(grep -E "WARNING:|dont have AML code|No summary file" "/tmp/aslts_norm_${commit}.log" | tr '\n' ';' | sed 's/,/;/g' | sed 's/"/\"/g' || true)
        echo "${run_utc},${commit},${rc},yes,${pass:-},${fail:-},${blocked:-},${tests:-},\"${tcases:-}\",\"${tcols:-}\",\"${warn:-}\"" >> "$OUT"
    else
        warn=$(grep -E "WARNING:|dont have AML code|No summary file|ASLTS Compile Failure|Could not find" "/tmp/aslts_norm_${commit}.log" | tr '\n' ';' | sed 's/,/;/g' | sed 's/"/\"/g' || true)
        echo "${run_utc},${commit},${rc},no,,,,,, ,\"${warn:-no_summary}\"" >> "$OUT"
    fi

    echo "[$commit] rc=$rc summary=${summary:-none}" >&2
}

if [[ "$#" -eq 0 ]]; then
    echo "Usage: $0 <commit1> [commit2 ...]" >&2
    exit 2
fi

for c in "$@"; do
    probe_commit "$c"
done

git checkout master >/dev/null 2>&1 || true

echo "Normalized probe complete. Results: $OUT"
