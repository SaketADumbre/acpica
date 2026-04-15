#!/usr/bin/env bash
set -euo pipefail

# Run a commit x compiler matrix for ASLTS between June and December 2021.
# Produces one CSV with parsed TOTAL metrics for each run and per-run logs.

DEFAULT_COMMITS=(
    ffceba1df  # R06_04_21
    2195f614e  # R07_30_21
    e01cc6b3d  # R09_30_21
    90088defc  # R12_17_21
)

DEFAULT_COMPILERS=(
    default
    gcc-9
)

MODE="n32"
REBUILD_TOOLS=0
RUN_INVENTORY=0
OUT_DIR=""
KEEP_RESULTS=0
ALLOW_DIRTY=0

COMMITS=()
COMPILERS=()

usage() {
    cat <<'EOF'
Usage:
  ./aslts_june_dec_matrix.sh [options]

Options:
  --mode <n32|n64|o32|o64>      ASLTS mode (default: n32)
  --rebuild-tools               Build tools in each run (omit -u)
  --run-inventory               Also run per-case inventory per matrix point
  --keep-results                Do not clear tests/aslts/tmp/RESULTS before each run
    --allow-dirty                 Allow running in a dirty worktree (not recommended)
  --out-dir <path>              Output dir (default: ./artifacts/aslts_matrix_<utc>)
  --commits "c1 c2 ..."         Space-separated commit list
  --compilers "default gcc-9"   Space-separated compilers
  -h, --help                    Show help

Examples:
  ./aslts_june_dec_matrix.sh
  ./aslts_june_dec_matrix.sh --rebuild-tools --compilers "default gcc-9"
  ./aslts_june_dec_matrix.sh --commits "ffceba1df 90088defc" --run-inventory
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --rebuild-tools)
            REBUILD_TOOLS=1
            shift
            ;;
        --run-inventory)
            RUN_INVENTORY=1
            shift
            ;;
        --keep-results)
            KEEP_RESULTS=1
            shift
            ;;
        --allow-dirty)
            ALLOW_DIRTY=1
            shift
            ;;
        --out-dir)
            OUT_DIR="$2"
            shift 2
            ;;
        --commits)
            read -r -a COMMITS <<< "$2"
            shift 2
            ;;
        --compilers)
            read -r -a COMPILERS <<< "$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 2
            ;;
    esac
done

case "$MODE" in
    n32|n64|o32|o64) ;;
    *)
        echo "Invalid mode '$MODE'. Use n32|n64|o32|o64." >&2
        exit 2
        ;;
esac

if [[ ! -d .git ]]; then
    echo "Run from ACPICA repo root (missing .git)." >&2
    exit 1
fi

if [[ "$ALLOW_DIRTY" -eq 0 ]]; then
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "Worktree has tracked modifications. Commit/stash first, or rerun with --allow-dirty." >&2
        exit 1
    fi
fi

if [[ ${#COMMITS[@]} -eq 0 ]]; then
    COMMITS=("${DEFAULT_COMMITS[@]}")
fi

if [[ ${#COMPILERS[@]} -eq 0 ]]; then
    COMPILERS=("${DEFAULT_COMPILERS[@]}")
fi

for compiler in "${COMPILERS[@]}"; do
    if [[ "$compiler" != "default" ]] && ! command -v "$compiler" >/dev/null 2>&1; then
        echo "Compiler '$compiler' not found on PATH." >&2
        exit 2
    fi
done

utc_now="$(date -u +%Y%m%dT%H%M%SZ)"
if [[ -z "$OUT_DIR" ]]; then
    OUT_DIR="./artifacts/aslts_matrix_${utc_now}"
fi

mkdir -p "$OUT_DIR"
RUNS_DIR="$OUT_DIR/runs"
mkdir -p "$RUNS_DIR"

RESULTS_CSV="$OUT_DIR/matrix_results.csv"
echo "run_utc,commit,compiler,mode,rebuild_tools,exit_code,summary_found,pass,fail,blocked,skipped,tests,test_cases,test_collections,warnings" > "$RESULTS_CSV"

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$OUT_DIR/matrix.log"
}

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
    local block_file="$2"
    awk -v key="$label" '$1==key {print $3; exit}' "$block_file"
}

extract_meta() {
    local label="$1"
    local block_file="$2"
    sed -n "s/^    ${label}[[:space:]]*:[[:space:]]*//p" "$block_file" | head -1
}

sanitize_csv_text() {
    tr '\n' ';' | sed 's/,/;/g' | sed 's/"/""/g'
}

run_inventory_for_point() {
    local commit="$1"
    local compiler="$2"
    local run_subdir="$3"

    local inventory_csv="$run_subdir/case_inventory_${commit}_${compiler}_${MODE}.csv"
    echo "case,pass,fail,blocked,skipped,total,summary_found,exit_code" > "$inventory_csv"

    {
        set +u
        source tests/aslts/bin/common
        source tests/aslts/bin/settings
        RESET_SETTINGS
        INIT_ALL_AVAILABLE_CASES
        INIT_ALL_AVAILABLE_MODES

        for tc in $ALL_AVAILABLE_TEST_CASES; do
            if [[ "$KEEP_RESULTS" -eq 0 ]]; then
                rm -rf tests/aslts/tmp/RESULTS/* 2>/dev/null || true
            fi

            rc=0
            if [[ "$compiler" = "default" ]]; then
                tests/aslts.sh -u -m "$MODE" -c "$tc" > "$run_subdir/aslts_case_${tc}.log" 2>&1 || rc=$?
            else
                CC="$compiler" tests/aslts.sh -u -m "$MODE" -c "$tc" > "$run_subdir/aslts_case_${tc}.log" 2>&1 || rc=$?
            fi

            latest=$(ls -t tests/aslts/tmp/RESULTS 2>/dev/null | head -1 || true)
            summary=""
            pass=0
            fail=0
            blocked=0
            skipped=0
            total=0
            found=no

            if [[ -n "$latest" ]]; then
                summary="tests/aslts/tmp/RESULTS/$latest/Summary"
            fi

            if [[ -f "$summary" ]]; then
                parsed=$(awk -v c="$tc" '
                    $0 ~ ("^" c ":") {in_case=1; next}
                    in_case && $1=="PASS" {pass=$3}
                    in_case && $1=="FAIL" {fail=$3}
                    in_case && $1=="BLOCKED" {blocked=$3}
                    in_case && $1=="SKIPPED" {skipped=$3}
                    in_case && $1=="total" {total=$3; print pass","fail","blocked","skipped","total; found=1; exit}
                    END {if (!found) print ""}
                ' "$summary")
                if [[ -n "$parsed" ]]; then
                    IFS=',' read -r pass fail blocked skipped total <<< "$parsed"
                    found=yes
                fi
            fi

            echo "$tc,$pass,$fail,$blocked,$skipped,$total,$found,$rc" >> "$inventory_csv"
        done
    } > "$run_subdir/inventory_driver.log" 2>&1
}

start_head="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
start_sha="$(git rev-parse HEAD)"

restore_start() {
    git checkout "$start_sha" >/dev/null 2>&1 || true
}
trap restore_start EXIT

log "Start matrix run: mode=$MODE rebuild_tools=$REBUILD_TOOLS run_inventory=$RUN_INVENTORY"
log "Commits: ${COMMITS[*]}"
log "Compilers: ${COMPILERS[*]}"
log "Starting from: branch='${start_head:-detached}' sha=$start_sha"

for commit in "${COMMITS[@]}"; do
    log "Checking out commit $commit"
    if ! git checkout "$commit" >/dev/null; then
        log "Checkout failed for $commit. See git output above."
        exit 1
    fi

    for compiler in "${COMPILERS[@]}"; do
        run_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        run_id="${commit}_${compiler}_${MODE}"
        run_subdir="$RUNS_DIR/$run_id"
        mkdir -p "$run_subdir"

        if [[ "$KEEP_RESULTS" -eq 0 ]]; then
            rm -rf tests/aslts/tmp/RESULTS/* 2>/dev/null || true
        fi

        start_epoch="$(date +%s)"
        log "Run: commit=$commit compiler=$compiler mode=$MODE rebuild=$REBUILD_TOOLS"

        rc=0
        if [[ "$REBUILD_TOOLS" -eq 1 ]]; then
            if [[ "$compiler" = "default" ]]; then
                tests/aslts.sh -m "$MODE" > "$run_subdir/aslts.log" 2>&1 || rc=$?
            else
                CC="$compiler" tests/aslts.sh -m "$MODE" > "$run_subdir/aslts.log" 2>&1 || rc=$?
            fi
        else
            if [[ "$compiler" = "default" ]]; then
                tests/aslts.sh -u -m "$MODE" > "$run_subdir/aslts.log" 2>&1 || rc=$?
            else
                CC="$compiler" tests/aslts.sh -u -m "$MODE" > "$run_subdir/aslts.log" 2>&1 || rc=$?
            fi
        fi

        summary=$(find tests/aslts/tmp/RESULTS -type f -name Summary -newermt "@${start_epoch}" 2>/dev/null | sort | tail -1 || true)
        pass=""
        fail=""
        blocked=""
        skipped=""
        tests=""
        tcases=""
        tcols=""
        summary_found=no
        warnings=""

        if [[ -n "$summary" && -f "$summary" ]]; then
            summary_found=yes
            cp "$summary" "$run_subdir/Summary"
            extract_total_block "$summary" > "$run_subdir/Summary_TOTAL_block.txt"
            pass=$(extract_field "PASS" "$run_subdir/Summary_TOTAL_block.txt")
            fail=$(extract_field "FAIL" "$run_subdir/Summary_TOTAL_block.txt")
            blocked=$(extract_field "BLOCKED" "$run_subdir/Summary_TOTAL_block.txt")
            skipped=$(extract_field "SKIPPED" "$run_subdir/Summary_TOTAL_block.txt")
            tests=$(extract_field "Tests" "$run_subdir/Summary_TOTAL_block.txt")
            tcases=$(extract_meta "Test Cases" "$run_subdir/Summary_TOTAL_block.txt")
            tcols=$(extract_meta "Test Collections" "$run_subdir/Summary_TOTAL_block.txt")
        fi

        warnings=$(grep -E "WARNING:|dont have AML code|No summary file|ASLTS Compile Failure|Could not find" "$run_subdir/aslts.log" 2>/dev/null | sanitize_csv_text || true)

        echo "${run_utc},${commit},${compiler},${MODE},${REBUILD_TOOLS},${rc},${summary_found},${pass:-},${fail:-},${blocked:-},${skipped:-},${tests:-},\"${tcases:-}\",\"${tcols:-}\",\"${warnings:-}\"" >> "$RESULTS_CSV"

        {
            echo "commit=$commit"
            echo "compiler=$compiler"
            echo "mode=$MODE"
            echo "rebuild_tools=$REBUILD_TOOLS"
            echo "exit_code=$rc"
            echo "summary_found=$summary_found"
            echo "summary_path=${summary:-}"
            echo "PASS=${pass:-}"
            echo "FAIL=${fail:-}"
            echo "BLOCKED=${blocked:-}"
            echo "SKIPPED=${skipped:-}"
            echo "Tests=${tests:-}"
            echo "Test Cases=${tcases:-}"
            echo "Test Collections=${tcols:-}"
        } > "$run_subdir/metrics.txt"

        if [[ "$RUN_INVENTORY" -eq 1 ]]; then
            log "Inventory: commit=$commit compiler=$compiler"
            run_inventory_for_point "$commit" "$compiler" "$run_subdir"
        fi
    done
done

git checkout "$start_sha" >/dev/null 2>&1 || true

{
    echo "start_branch=${start_head:-detached}"
    echo "start_sha=$start_sha"
    echo "mode=$MODE"
    echo "rebuild_tools=$REBUILD_TOOLS"
    echo "run_inventory=$RUN_INVENTORY"
    echo "commits=${COMMITS[*]}"
    echo "compilers=${COMPILERS[*]}"
    echo "results_csv=$RESULTS_CSV"
} > "$OUT_DIR/manifest.txt"

tar -czf "${OUT_DIR}.tar.gz" -C "$(dirname "$OUT_DIR")" "$(basename "$OUT_DIR")"

log "Done. Results CSV: $RESULTS_CSV"
log "Artifacts dir: $OUT_DIR"
log "Archive: ${OUT_DIR}.tar.gz"
