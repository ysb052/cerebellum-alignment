#!/bin/bash
set -euo pipefail

# ==========================================
# 1. Paths
# ==========================================

BASE="/volume_4/research/seongbong/align/Final_cerebellum_alignment"

SIFT_IMG="file://$BASE/render_sift_new_masked_normalized"

OUTPUT="file://$BASE/corgie_mip5_prior_mip7_z70_100_with_multi"

QUEUE="fq://$BASE/corgie_queue_mip5_multi_test"

MODEL_CONFIG="$BASE/metroem_corgie_adapter/configs/metroem_processor_with_field_sm_3_mip5.yaml"

PRIOR_FIELD="file://$BASE/corgie_mip7_no_prior_z70_1173/field/composed_aligned"

# ==========================================
# 2. Alignment parameters
# ==========================================

PROCESSOR_MIP=5

BLOCK_SIZE=7
STITCH_SIZE=3
VOTE_DIST=3

Z_START=70
Z_END=100

CHUNK_XY=512
RENDER_CHUNK_XY=512
PAD=64


# ==========================================
# 3. Preparation
# ==========================================

if [[ ! -f "$MODEL_CONFIG" ]]; then
    echo "ERROR: Model config not found: $MODEL_CONFIG"
    exit 1
fi

mkdir -p "$BASE/corgie_queue_mip5_multi_test"

echo "=========================================="
echo "Corgie MIP5 Distributed Alignment"
echo "=========================================="
echo "Input       : $SIFT_IMG"
echo "Output      : $OUTPUT"
echo "Queue       : $QUEUE"
echo "Model config: $MODEL_CONFIG"
echo "MIP         : $PROCESSOR_MIP"
echo "Z range     : [$Z_START, $Z_END)"
echo "Block size  : $BLOCK_SIZE"
echo "Stitch size : $STITCH_SIZE"
echo "Vote dist   : $VOTE_DIST"
echo "Prior field : $PRIOR_FIELD"
echo "=========================================="


# ==========================================
# 4. Run Corgie alignment
# ==========================================

corgie align \
    --src_layer_spec "{\"name\":\"img\",\"type\":\"img\",\"path\":\"$SIFT_IMG\"}" \
    --src_layer_spec "{\"name\":\"prior\",\"type\":\"field\",\"path\":\"$PRIOR_FIELD\",\"args\":{\"data_mip\":7}}" \
    --dst_folder "$OUTPUT" \
    --processor_spec "$(cat "$MODEL_CONFIG")" \
    --processor_mip "$PROCESSOR_MIP" \
    --block_size "$BLOCK_SIZE" \
    --stitch_size "$STITCH_SIZE" \
    --vote_dist "$VOTE_DIST" \
    --start_coord "0,0,$Z_START" \
    --end_coord "249600,230400,$Z_END" \
    --coord_mip 0 \
    --chunk_xy "$CHUNK_XY" \
    --render_chunk_xy "$RENDER_CHUNK_XY" \
    --pad "$PAD" \
    --device cuda \
    --queue_name "$QUEUE" \
    --verbose

echo "Corgie alignment finished."
