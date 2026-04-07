#!/bin/bash
set -euo pipefail

cd /workspaces/acpica
OUT=/workspaces/acpica/aslts_count_probe_results.txt
: > "$OUT"

commits=("051eccad3" "051eccad3^")

echo "Probe started: $(date -u)" | tee -a "$OUT"
for c in "${commits[@]}"; do
  echo "===== COMMIT $c =====" | tee -a "$OUT"
  git checkout "$c" >/dev/null 2>&1
  echo "Checked out: $(git log -1 --format='%h %ad %s' --date=iso)" | tee -a "$OUT"

  rm -rf tests/aslts/tmp/RESULTS/* 2>/dev/null || true
  start_ts=$(date +%s)

  set +e
  tests/aslts.sh -u > "/tmp/aslts_${c}.log" 2>&1
  rc=$?
  set -e

  echo "ExitCode: $rc" | tee -a "$OUT"

  latest=$(ls -t tests/aslts/tmp/RESULTS 2>/dev/null | head -1 || true)
  if [[ -n "$latest" ]]; then
    summary="tests/aslts/tmp/RESULTS/$latest/Summary"
    if [[ -f "$summary" ]]; then
      pass=$(tail -30 "$summary" | awk '/PASS/{print $3; exit}')
      fail=$(tail -30 "$summary" | awk '/FAIL/{print $3; exit}')
      blocked=$(tail -30 "$summary" | awk '/BLOCKED/{print $3; exit}')
      testsn=$(tail -30 "$summary" | awk '/Tests/{print $3; exit}')
      echo "LatestResult: $latest" | tee -a "$OUT"
      echo "PASS=$pass FAIL=$fail BLOCKED=$blocked TESTS=$testsn" | tee -a "$OUT"
      echo "SummaryTail:" | tee -a "$OUT"
      tail -20 "$summary" | tee -a "$OUT"
    else
      echo "No Summary file found in latest result dir" | tee -a "$OUT"
    fi
  else
    echo "No RESULTS directory created" | tee -a "$OUT"
  fi

  end_ts=$(date +%s)
  echo "DurationSec: $((end_ts-start_ts))" | tee -a "$OUT"
  echo "LogTail:" | tee -a "$OUT"
  tail -30 "/tmp/aslts_${c}.log" | tee -a "$OUT"
  echo | tee -a "$OUT"
done

git checkout master >/dev/null 2>&1 || true
echo "Probe finished: $(date -u)" | tee -a "$OUT"
