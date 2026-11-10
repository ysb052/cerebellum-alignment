
#!/bin/bash
set -euo pipefail

# ==================================================
# 1. Configuration
# ==================================================

SRC_PATH="file:///volume_4/research/seongbong/align/Final_cerebellum_alignment/img_raw"

FIELD_PATH="file:///volume_4/research/seongbong/align/Final_cerebellum_alignment/img_sift_new/field/field_sift"

DST_PATH="file:///volume_4/research/seongbong/align/Final_cerebellum_alignment/render_sift_new"

GPUS=(0 1 2 3 4 5 6 7 8 9)
MIPS=(7 6 5)

Z_START=0
Z_END=1200

X_END=249600
Y_END=230400

CHUNK=512
PAD=128

LOG_DIR="render_logs"
mkdir -p "$LOG_DIR"

MONITOR_INTERVAL=5
START_TIME=$(date +%s)

# ==================================================
# 2. Progress functions
# ==================================================

format_time() {
    local seconds=$1
    printf "%02d:%02d:%02d" \
        $((seconds / 3600)) \
        $(((seconds % 3600) / 60)) \
        $((seconds % 60))
}

progress_bar() {
    local percent=$1
    local width=30
    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    printf "["
    printf "%${filled}s" "" | tr ' ' '#'
    printf "%${empty}s" "" | tr ' ' '-'
    printf "]"
}

# Determine progress from log.
# This is an estimate based on the highest written Z.
get_progress() {
    local log=$1
    local start=$2
    local end=$3

    if [[ ! -f "$log" ]]; then
        echo 0
        return
    fi

    if grep -q "Flagging job as FINISHED" "$log"; then
        echo $((end - start))
        return
    fi

    local last_z

    last_z=$(
        grep -E 'z: \[[0-9]+, [0-9]+\]' "$log" |
        sed -n 's/.*z: \[\([0-9]*\), \([0-9]*\)\].*/\1/p' |
        sort -n |
        tail -n 1
    )

    if [[ -z "$last_z" ]]; then
        echo 0
        return
    fi

    local count=$((last_z - start + 1))
    local total=$((end - start))

    if ((count < 0)); then count=0; fi
    if ((count > total)); then count=$total; fi

    echo "$count"
}

# ==================================================
# 3. Monitor
# ==================================================

monitor_progress() {
    local mip=$1
    local -n pids_ref=$2
    local -n starts_ref=$3
    local -n ends_ref=$4

    while true; do

        printf '\033[2J\033[H'

        echo "=============================================================="
        echo "                  CORGIE RENDER MONITOR"
        echo "=============================================================="
        echo "MIP: $mip"
        echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Elapsed: $(format_time $(($(date +%s) - START_TIME)))"
        echo

        printf "%-6s %-14s %-12s %-10s %-35s\n" \
            "GPU" "Z RANGE" "STATUS" "PROGRESS" "BAR"

        echo "--------------------------------------------------------------"

        local total_done=0
        local total_sections=0

        for i in "${!GPUS[@]}"; do

            local gpu=${GPUS[$i]}
            local z0=${starts_ref[$i]}
            local z1=${ends_ref[$i]}
            local pid=${pids_ref[$i]}
            local log="$LOG_DIR/mip${mip}_gpu${gpu}.log"

            local total=$((z1 - z0))
            local done
            done=$(get_progress "$log" "$z0" "$z1")

            local percent=$((done * 100 / total))

            local status="RUNNING"

            if grep -q "Flagging job as FINISHED" "$log" 2>/dev/null; then
                status="DONE"
                done=$total
                percent=100
            elif ! kill -0 "$pid" 2>/dev/null; then
                status="EXITED"
            fi

            total_done=$((total_done + done))
            total_sections=$((total_sections + total))

            printf "%-6s %-14s %-12s %3d%%       " \
                "$gpu" "$z0-$((z1-1))" "$status" "$percent"

            progress_bar "$percent"
            echo

        done

        echo "--------------------------------------------------------------"

        local overall=$((total_done * 100 / total_sections))

        printf "MIP $mip overall: %d / %d sections (%d%%)\n" \
            "$total_done" "$total_sections" "$overall"

        progress_bar "$overall"
        echo
        echo

        sleep "$MONITOR_INTERVAL"
    done
}

# ==================================================
# 4. Rendering
# ==================================================

for MIP in "${MIPS[@]}"; do

    echo "Starting MIP $MIP"

    PIDS=()
    Z_STARTS=()
    Z_ENDS=()

    NUM_GPUS=${#GPUS[@]}
    TOTAL_Z=$((Z_END - Z_START))

    for i in "${!GPUS[@]}"; do

        GPU=${GPUS[$i]}

        Z0=$((Z_START + i * TOTAL_Z / NUM_GPUS))
        Z1=$((Z_START + (i + 1) * TOTAL_Z / NUM_GPUS))

        Z_STARTS+=("$Z0")
        Z_ENDS+=("$Z1")

        LOG="$LOG_DIR/mip${MIP}_gpu${GPU}.log"

        CUDA_VISIBLE_DEVICES="$GPU" corgie render \
            --src_layer_spec "{\"name\":\"img\",\"type\":\"img\",\"path\":\"$SRC_PATH\",\"args\":{\"data_mip\":$MIP}}" \
            --src_layer_spec "{\"name\":\"field\",\"type\":\"field\",\"path\":\"$FIELD_PATH\",\"args\":{\"data_mip\":8}}" \
            --dst_folder "$DST_PATH" \
            --start_coord "0,0,$Z0" \
            --end_coord "$X_END,$Y_END,$Z1" \
            --coord_mip 0 \
            --mip "$MIP" \
            --chunk_xy "$CHUNK" \
            --pad "$PAD" \
            --device cuda \
            --verbose \
            > "$LOG" 2>&1 &

        PIDS+=("$!")

    done

    # Start progress monitor
    monitor_progress "$MIP" PIDS Z_STARTS Z_ENDS &
    MONITOR_PID=$!

    FAILED=0

    for PID in "${PIDS[@]}"; do
        if ! wait "$PID"; then
            FAILED=1
        fi
    done

    # Stop monitor
    kill "$MONITOR_PID" 2>/dev/null || true
    wait "$MONITOR_PID" 2>/dev/null || true

    if [[ "$FAILED" -ne 0 ]]; then
        echo "ERROR: MIP $MIP failed."
        echo "Check logs in $LOG_DIR"
        exit 1
    fi

    echo "MIP $MIP completed."

done

echo "=========================================="
echo "All rendering completed successfully."
echo "Total elapsed: $(format_time $(($(date +%s) - START_TIME)))"
echo "=========================================="

