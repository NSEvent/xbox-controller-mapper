#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CONFIG="${CONFIG:-Debug}"
WARMUP_SECONDS="${WARMUP_SECONDS:-5}"
SAMPLE_COUNT="${SAMPLE_COUNT:-8}"
PROCESS_NAME="ControllerKeys"

build_app() {
    if [[ "${SKIP_BUILD:-0}" == "1" ]]; then
        return
    fi

    make build BUILD_FROM_SOURCE=1 CONFIG="$CONFIG"
}

app_path() {
    make app-path CONFIG="$CONFIG" | tail -n 1
}

sample_cpu() {
    local pid="$1"
    top -pid "$pid" -stats pid,cpu -l 2 -s 1 | awk -v pid="$pid" '$1 == pid { value = $2 } END { gsub("%", "", value); print value + 0 }'
}

run_scenario() {
    local scenario="$1"
    local legacy_display="$2"
    local legacy_motion="$3"
    local force_motion_disabled="$4"
    local app_bundle
    local executable
    local log_file
    local pid
    local cpu_samples_file

    app_bundle="$(app_path)"
    executable="$app_bundle/Contents/MacOS/$PROCESS_NAME"
    log_file="$(mktemp "/tmp/xcm-${scenario}.XXXXXX")"
    cpu_samples_file="$(mktemp "/tmp/xcm-${scenario}-cpu.XXXXXX")"

    pkill -x "$PROCESS_NAME" || true
    sleep 1

    env \
        XCM_PERF_PROBE=1 \
        XCM_PERF_SCENARIO="$scenario" \
        XCM_PERF_FORCE_LEGACY_DISPLAY_PUBLISHING="$legacy_display" \
        XCM_PERF_FORCE_LEGACY_ALWAYS_ON_MOTION="$legacy_motion" \
        XCM_PERF_FORCE_MOTION_DISABLED="$force_motion_disabled" \
        "$executable" >"$log_file" 2>&1 &
    pid=$!

    sleep "$WARMUP_SECONDS"

    for _ in $(seq 1 "$SAMPLE_COUNT"); do
        sample_cpu "$pid" >> "$cpu_samples_file"
    done

    kill "$pid" || true
    wait "$pid" 2>/dev/null || true

    awk -v scenario="$scenario" '
        /\[PerfProbe\] interval/ {
            for (i = 1; i <= NF; i++) {
                split($i, kv, "=")
                if (kv[1] == "display_ticks") display_ticks += kv[2]
                else if (kv[1] == "display_noop_ticks") display_noops += kv[2]
                else if (kv[1] == "display_applies") display_applies += kv[2]
                else if (kv[1] == "display_field_writes") display_field_writes += kv[2]
                else if (kv[1] == "motion_callbacks_raw") motion_callbacks_raw += kv[2]
                else if (kv[1] == "motion_callbacks_processed") motion_callbacks_processed += kv[2]
            }
            intervals += 1
        }
        END {
            if (intervals == 0) {
                printf "%s\t0\t0\t0\t0\t0\t0\t0\n", scenario
                exit
            }
            printf "%s\t%d\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\n",
                scenario,
                intervals,
                display_ticks / intervals,
                display_noops / intervals,
                display_applies / intervals,
                display_field_writes / intervals,
                motion_callbacks_raw / intervals,
                motion_callbacks_processed / intervals
        }
    ' "$log_file" > "${log_file}.summary"

    local avg_cpu
    avg_cpu="$(awk '{ sum += $1; count += 1 } END { if (count == 0) print 0; else printf "%.2f", sum / count }' "$cpu_samples_file")"

    printf "%s\t%s\t%s\t%s\n" "$scenario" "$avg_cpu" "$log_file" "$cpu_samples_file"
}

print_report() {
    local legacy_summary="$1"
    local fixed_summary="$2"
    local fixed_no_motion_summary="$3"
    local legacy_cpu="$4"
    local fixed_cpu="$5"
    local fixed_no_motion_cpu="$6"
    local legacy_log="$7"
    local fixed_log="$8"
    local fixed_no_motion_log="$9"

    local legacy_metrics fixed_metrics fixed_no_motion_metrics
    legacy_metrics="$(cat "$legacy_summary")"
    fixed_metrics="$(cat "$fixed_summary")"
    fixed_no_motion_metrics="$(cat "$fixed_no_motion_summary")"

    printf "\nIdle DualSense benchmark\n"
    printf "keep controller connected; leave it untouched during all runs\n\n"
    printf "%-17s %-8s %-10s %-10s %-10s %-12s %-12s %-12s\n" "scenario" "cpu_avg" "intervals" "ticks/s" "noops/s" "applies/s" "motion_raw/s" "motion_used/s"

    printf "%-17s %-8s %-10s %-10s %-10s %-10s %-12s %-12s\n" \
        "$(echo "$legacy_metrics" | cut -f1)" \
        "$legacy_cpu" \
        "$(echo "$legacy_metrics" | cut -f2)" \
        "$(echo "$legacy_metrics" | cut -f3)" \
        "$(echo "$legacy_metrics" | cut -f4)" \
        "$(echo "$legacy_metrics" | cut -f5)" \
        "$(echo "$legacy_metrics" | cut -f7)" \
        "$(echo "$legacy_metrics" | cut -f8)"

    printf "%-17s %-8s %-10s %-10s %-10s %-10s %-12s %-12s\n" \
        "$(echo "$fixed_metrics" | cut -f1)" \
        "$fixed_cpu" \
        "$(echo "$fixed_metrics" | cut -f2)" \
        "$(echo "$fixed_metrics" | cut -f3)" \
        "$(echo "$fixed_metrics" | cut -f4)" \
        "$(echo "$fixed_metrics" | cut -f5)" \
        "$(echo "$fixed_metrics" | cut -f7)" \
        "$(echo "$fixed_metrics" | cut -f8)"

    printf "%-17s %-8s %-10s %-10s %-10s %-10s %-12s %-12s\n" \
        "$(echo "$fixed_no_motion_metrics" | cut -f1)" \
        "$fixed_no_motion_cpu" \
        "$(echo "$fixed_no_motion_metrics" | cut -f2)" \
        "$(echo "$fixed_no_motion_metrics" | cut -f3)" \
        "$(echo "$fixed_no_motion_metrics" | cut -f4)" \
        "$(echo "$fixed_no_motion_metrics" | cut -f5)" \
        "$(echo "$fixed_no_motion_metrics" | cut -f7)" \
        "$(echo "$fixed_no_motion_metrics" | cut -f8)"

    printf "\nlogs\n"
    printf "legacy: %s\n" "$legacy_log"
    printf "fixed:  %s\n" "$fixed_log"
    printf "fixed-no-motion: %s\n" "$fixed_no_motion_log"
}

build_app

legacy_result="$(run_scenario legacy 1 1 0)"
fixed_result="$(run_scenario fixed 0 0 0)"
fixed_no_motion_result="$(run_scenario fixed-no-motion 0 0 1)"

legacy_cpu="$(echo "$legacy_result" | cut -f2)"
legacy_log="$(echo "$legacy_result" | cut -f3)"
legacy_summary="${legacy_log}.summary"

fixed_cpu="$(echo "$fixed_result" | cut -f2)"
fixed_log="$(echo "$fixed_result" | cut -f3)"
fixed_summary="${fixed_log}.summary"

fixed_no_motion_cpu="$(echo "$fixed_no_motion_result" | cut -f2)"
fixed_no_motion_log="$(echo "$fixed_no_motion_result" | cut -f3)"
fixed_no_motion_summary="${fixed_no_motion_log}.summary"

print_report \
    "$legacy_summary" \
    "$fixed_summary" \
    "$fixed_no_motion_summary" \
    "$legacy_cpu" \
    "$fixed_cpu" \
    "$fixed_no_motion_cpu" \
    "$legacy_log" \
    "$fixed_log" \
    "$fixed_no_motion_log"
