#!/bin/bash
set -euo pipefail

BASE="/volume_4/research/seongbong/align/Final_cerebellum_alignment"
QUEUE="fq://$BASE/corgie_queue_mip5_multi_test"

WORKERS_PER_GPU=3

mkdir -p "$BASE/worker_logs_mip5_multi_test"

for GPU in {0..9}; do
    for W in $(seq 1 "$WORKERS_PER_GPU"); do

        echo "Starting GPU $GPU Worker $W"

        CUDA_VISIBLE_DEVICES=$GPU \
        corgie-worker \
            --queue_name "$QUEUE" \
            --lease_seconds 30 \
            --verbose \
            > "$BASE/worker_logs_mip5_multi_test/gpu_${GPU}_worker_${W}.log" 2>&1 &

    done
done

wait
