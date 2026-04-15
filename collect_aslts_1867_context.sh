#!/usr/bin/env bash
set -euo pipefail

# Collect reproducibility data for ASLTS count investigations.
# Intended use: run on the machine that reports ~1867 at the Dec 2021 release commit.

TARGET_COMMIT_DEFAULT="90088defc"
MODE_DEFAULT="n32"

TARGET_COMMIT="$TARGET_COMMIT_DEFAULT"
MODE="$MODE_DEFAULT"
OUT_ROOT=""
RUN_DEFAULT=1
RUN_INVENTORY=0
KEEP_TMP=0

usage() {
    cat <<'EOF'
Usage:
  ./collect_aslts_1867_context.sh [options]

Options:
  --target-commit <sha>   Commit expected for the run (default: 90088defc)
  --mode <n32|n64|o32|o64> ASLTS mode for default run (default: n32)
  --out-dir <path>        Output directory (default: ./artifacts/aslts_1867_capture_<utc>)
  --no-run                Capture config only; do not run ASLTS
  --run-inventory         Also run isolated per-case inventory across all available cases
  --keep-tmp              Keep per-case tmp results during inventory runs
  -h, --help              Show this help

Examples:
  ./collect_aslts_1867_context.sh
  ./collect_aslts_1867_context.sh --target-commit 90088defc --mode n32 --run-inventory
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target-commit)
            TARGET_COMMIT="$2"
            shift 2
            ;;
        --mode)
            MODE="$2"
            shift 2
            ;;
        --out-dir)
            OUT_ROOT="$2"
            shift 2
            ;;
        --no-run)
            RUN_DEFAULT=0
            shift
            ;;
        --run-inventory)
            RUN_INVENTORY=1
            shift
            ;;
        --keep-tmp)
            KEEP_TMP=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

if [[ ! -d .git ]]; then
    echo "Error: run this script from the ACPICA repository root (missing .git)." >&2
    exit 1
fi

case "$MODE" in
    n32|n64|o32|o64) ;;
    *)
        echo "Error: unsupported mode '$MODE'. Use n32|n64|o32|o64." >&2
        exit 2
        ;;
esac

UTC_NOW="$(date -u +%Y%m%dT%H%M%SZ)"
if [[ -z "$OUT_ROOT" ]]; then
    OUT_ROOT="./artifacts/aslts_1867_capture_${UTC_NOW}"
fi

mkdir -p "$OUT_ROOT"
SYS_DIR="$OUT_ROOT/system"
GIT_DIR="$OUT_ROOT/git"
ASLTS_DIR="$OUT_ROOT/aslts"
RUN_DIR="$OUT_ROOT/run"
mkdir -p "$SYS_DIR" "$GIT_DIR" "$ASLTS_DIR" "$RUN_DIR"

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$OUT_ROOT/collector.log"
}

run_capture() {
    local label="$1"
    shift
    {
        echo "### $label"
        echo "$ $*"
        "$@"
    } > "$OUT_ROOT/raw_${label}.txt" 2>&1 || true
}

capture_cmd_or_na() {
    local cmd="$1"
    local out="$2"
    if command -v "$cmd" >/dev/null 2>&1; then
        {
            echo "$cmd: $(command -v "$cmd")"
            "$cmd" --version || "$cmd" -v || true
        } > "$out" 2>&1
    else
        echo "$cmd: not found" > "$out"
    fi
}

parse_total_block() {
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

collect_system_info() {
    log "Collecting system and toolchain information"

    date -u +"%Y-%m-%dT%H:%M:%SZ" > "$SYS_DIR/utc_now.txt"
    date > "$SYS_DIR/local_now.txt"
    uname -a > "$SYS_DIR/uname.txt" 2>&1 || true
    (cat /etc/os-release || true) > "$SYS_DIR/os-release.txt" 2>&1
    (lsb_release -a || true) > "$SYS_DIR/lsb_release.txt" 2>&1
    (hostnamectl || true) > "$SYS_DIR/hostnamectl.txt" 2>&1
    (timedatectl || true) > "$SYS_DIR/timedatectl.txt" 2>&1
    (locale || true) > "$SYS_DIR/locale.txt" 2>&1
    (umask || true) > "$SYS_DIR/umask.txt" 2>&1
    (ulimit -a || true) > "$SYS_DIR/ulimit.txt" 2>&1
    (nproc || true) > "$SYS_DIR/nproc.txt" 2>&1
    (getconf _NPROCESSORS_ONLN || true) > "$SYS_DIR/nproc_onln.txt" 2>&1
    (free -h || true) > "$SYS_DIR/free.txt" 2>&1
    (cat /proc/cpuinfo || true) > "$SYS_DIR/cpuinfo.txt" 2>&1
    (cat /proc/meminfo || true) > "$SYS_DIR/meminfo.txt" 2>&1
    (df -h || true) > "$SYS_DIR/df_h.txt" 2>&1
    (mount || true) > "$SYS_DIR/mount.txt" 2>&1
    (env | sort || true) > "$SYS_DIR/env_sorted.txt" 2>&1

    capture_cmd_or_na bash "$SYS_DIR/bash_version.txt"
    capture_cmd_or_na gcc "$SYS_DIR/gcc_version.txt"
    capture_cmd_or_na g++ "$SYS_DIR/gpp_version.txt"
    capture_cmd_or_na gcc-9 "$SYS_DIR/gcc9_version.txt"
    capture_cmd_or_na clang "$SYS_DIR/clang_version.txt"
    capture_cmd_or_na make "$SYS_DIR/make_version.txt"
    capture_cmd_or_na cmake "$SYS_DIR/cmake_version.txt"
    capture_cmd_or_na ld "$SYS_DIR/ld_version.txt"
    capture_cmd_or_na as "$SYS_DIR/as_version.txt"
    capture_cmd_or_na ar "$SYS_DIR/ar_version.txt"
    capture_cmd_or_na nm "$SYS_DIR/nm_version.txt"
    capture_cmd_or_na objdump "$SYS_DIR/objdump_version.txt"
    capture_cmd_or_na strip "$SYS_DIR/strip_version.txt"
    capture_cmd_or_na perl "$SYS_DIR/perl_version.txt"
    capture_cmd_or_na python3 "$SYS_DIR/python3_version.txt"
    capture_cmd_or_na xargs "$SYS_DIR/xargs_version.txt"

    if command -v ldd >/dev/null 2>&1; then
        ldd --version > "$SYS_DIR/ldd_version.txt" 2>&1 || true
    else
        echo "ldd: not found" > "$SYS_DIR/ldd_version.txt"
    fi

    if command -v dpkg-query >/dev/null 2>&1; then
        dpkg-query -W > "$SYS_DIR/dpkg_packages.txt" 2>/dev/null || true
    elif command -v rpm >/dev/null 2>&1; then
        rpm -qa > "$SYS_DIR/rpm_packages.txt" 2>/dev/null || true
    fi
}

collect_git_info() {
    log "Collecting git state and script fingerprints"

    git rev-parse --show-toplevel > "$GIT_DIR/repo_root.txt"
    git rev-parse HEAD > "$GIT_DIR/head_sha.txt"
    git branch --show-current > "$GIT_DIR/branch.txt" 2>&1 || true
    git status --porcelain=v1 > "$GIT_DIR/status_porcelain.txt" 2>&1 || true
    git status > "$GIT_DIR/status.txt" 2>&1 || true
    git remote -v > "$GIT_DIR/remotes.txt" 2>&1 || true
    git show -s --format=fuller HEAD > "$GIT_DIR/head_full.txt" 2>&1 || true
    git log --decorate --oneline -20 > "$GIT_DIR/log_last20.txt" 2>&1 || true
    git diff > "$GIT_DIR/diff_worktree.patch" 2>&1 || true
    git diff --cached > "$GIT_DIR/diff_staged.patch" 2>&1 || true

    {
        echo "target_commit=$TARGET_COMMIT"
        echo "head_commit=$(git rev-parse HEAD)"
        if git merge-base --is-ancestor "$TARGET_COMMIT" HEAD 2>/dev/null; then
            echo "target_is_ancestor_of_head=yes"
        else
            echo "target_is_ancestor_of_head=no_or_unknown"
        fi
        if [[ "$(git rev-parse HEAD)" = "$TARGET_COMMIT" ]]; then
            echo "head_matches_target=yes"
        else
            echo "head_matches_target=no"
        fi
    } > "$GIT_DIR/target_commit_check.txt"

    local key_files=(
        "tests/aslts.sh"
        "tests/aslts/bin/asltsrun"
        "tests/aslts/bin/Do"
        "tests/aslts/bin/settings"
        "tests/aslts/bin/common"
        "tests/aslts/bin/config"
    )

    : > "$ASLTS_DIR/key_files_sha256.txt"
    for f in "${key_files[@]}"; do
        if [[ -f "$f" ]]; then
            sha256sum "$f" >> "$ASLTS_DIR/key_files_sha256.txt"
            cp "$f" "$ASLTS_DIR/$(basename "$f")"
        else
            echo "MISSING $f" >> "$ASLTS_DIR/key_files_sha256.txt"
        fi
    done
}

collect_aslts_config() {
    log "Collecting ASLTS settings expansion"

    if [[ ! -f tests/aslts/bin/settings || ! -f tests/aslts/bin/common ]]; then
        echo "Required ASLTS scripts not found under tests/aslts/bin" > "$ASLTS_DIR/settings_expanded.txt"
        return
    fi

    {
        set +u
        source tests/aslts/bin/common
        source tests/aslts/bin/settings
        RESET_SETTINGS
        INIT_ALL_AVAILABLE_CASES
        INIT_ALL_AVAILABLE_MODES
        INIT_SET_OF_TEST_CASES
        INIT_SET_OF_TEST_MODES

        echo "ALL_AVAILABLE_TEST_CASES=$ALL_AVAILABLE_TEST_CASES"
        echo "ALL_AVAILABLE_TEST_MODES=$ALL_AVAILABLE_TEST_MODES"
        echo "ENABLED_TCASES=$ENABLED_TCASES"
        echo "ENABLED_TMODES=$ENABLED_TMODES"
        echo "NUM_ALL_CASES=$(wc -w <<< \"$ALL_AVAILABLE_TEST_CASES\")"
        echo "NUM_ENABLED_CASES=$(wc -w <<< \"$ENABLED_TCASES\")"
        echo "ENABLELOG=$ENABLELOG"
        echo "MAXBDEMO=$MAXBDEMO"
    } > "$ASLTS_DIR/settings_expanded.txt" 2>&1 || true
}

run_default_aslts() {
    log "Running default ASLTS invocation (tests/aslts.sh -u -m $MODE)"

    rm -rf tests/aslts/tmp/RESULTS/* 2>/dev/null || true

    set +e
    tests/aslts.sh -u -m "$MODE" > "$RUN_DIR/aslts_default.log" 2>&1
    local rc=$?
    set -e
    echo "$rc" > "$RUN_DIR/aslts_default.exit_code"

    local latest summary
    latest=$(ls -t tests/aslts/tmp/RESULTS 2>/dev/null | head -1 || true)
    if [[ -n "$latest" ]]; then
        echo "$latest" > "$RUN_DIR/latest_results_dir.txt"
        summary="tests/aslts/tmp/RESULTS/$latest/Summary"
        if [[ -f "$summary" ]]; then
            cp "$summary" "$RUN_DIR/Summary"
            parse_total_block "$summary" > "$RUN_DIR/Summary_TOTAL_block.txt"
            local pass fail blocked skipped tests tcases tcols
            pass=$(extract_field "PASS" "$RUN_DIR/Summary_TOTAL_block.txt")
            fail=$(extract_field "FAIL" "$RUN_DIR/Summary_TOTAL_block.txt")
            blocked=$(extract_field "BLOCKED" "$RUN_DIR/Summary_TOTAL_block.txt")
            skipped=$(extract_field "SKIPPED" "$RUN_DIR/Summary_TOTAL_block.txt")
            tests=$(extract_field "Tests" "$RUN_DIR/Summary_TOTAL_block.txt")
            tcases=$(extract_meta "Test Cases" "$RUN_DIR/Summary_TOTAL_block.txt")
            tcols=$(extract_meta "Test Collections" "$RUN_DIR/Summary_TOTAL_block.txt")

            {
                echo "mode=$MODE"
                echo "exit_code=$rc"
                echo "PASS=${pass:-}"
                echo "FAIL=${fail:-}"
                echo "BLOCKED=${blocked:-}"
                echo "SKIPPED=${skipped:-}"
                echo "Tests=${tests:-}"
                echo "Test Cases=${tcases:-}"
                echo "Test Collections=${tcols:-}"
            } > "$RUN_DIR/default_run_metrics.txt"
        fi
    fi
}

run_case_inventory() {
    log "Running isolated per-case inventory across all available test cases"

    local inventory_csv="$RUN_DIR/case_inventory_${MODE}.csv"
    echo "case,pass,fail,blocked,skipped,total,summary_found,exit_code" > "$inventory_csv"

    {
        set +u
        source tests/aslts/bin/common
        source tests/aslts/bin/settings
        RESET_SETTINGS
        INIT_ALL_AVAILABLE_CASES
        INIT_ALL_AVAILABLE_MODES

        for tc in $ALL_AVAILABLE_TEST_CASES; do
            if [[ "$KEEP_TMP" -eq 0 ]]; then
                rm -rf tests/aslts/tmp/RESULTS/* 2>/dev/null || true
            fi

            set +e
            tests/aslts.sh -u -m "$MODE" -c "$tc" > "$RUN_DIR/aslts_case_${tc}.log" 2>&1
            rc=$?
            set -e

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
            log "case=$tc total=$total found=$found rc=$rc"
        done
    } > "$RUN_DIR/inventory_driver.log" 2>&1
}

write_manifest() {
    log "Writing manifest and packaging artifacts"

    {
        echo "collector_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "target_commit=$TARGET_COMMIT"
        echo "mode=$MODE"
        echo "run_default=$RUN_DEFAULT"
        echo "run_inventory=$RUN_INVENTORY"
        echo "output_dir=$OUT_ROOT"
        echo "head_commit=$(git rev-parse HEAD)"
        echo "head_branch=$(git branch --show-current 2>/dev/null || true)"
    } > "$OUT_ROOT/manifest.txt"

    tar -czf "${OUT_ROOT}.tar.gz" -C "$(dirname "$OUT_ROOT")" "$(basename "$OUT_ROOT")"
}

main() {
    log "Starting ASLTS context collection"
    log "target_commit=$TARGET_COMMIT mode=$MODE run_default=$RUN_DEFAULT run_inventory=$RUN_INVENTORY"

    collect_system_info
    collect_git_info
    collect_aslts_config

    if [[ "$RUN_DEFAULT" -eq 1 ]]; then
        run_default_aslts
    fi

    if [[ "$RUN_INVENTORY" -eq 1 ]]; then
        run_case_inventory
    fi

    write_manifest

    log "Done"
    log "Artifacts: $OUT_ROOT"
    log "Archive: ${OUT_ROOT}.tar.gz"
}

main
