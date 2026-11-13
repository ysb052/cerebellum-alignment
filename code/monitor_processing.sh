#!/bin/bash

BASE="/volume_4/research/seongbong/align/Final_cerebellum_alignment"
OUT="$BASE/corgie_mip5_prior_mip7_z70_100_with_multi"

get_count() {
    find "$OUT/even/field/field_aligned" \
         "$OUT/odd/field/field_aligned" \
         -name '*.gz' 2>/dev/null | wc -l
}

START=$(get_count)
echo "시작: $(date), $START files"

sleep 300

END=$(get_count)
DIFF=$((END - START))

echo "종료: $(date), $END files"
echo "5분간 생성: $DIFF files"
echo "분당 처리량: $((DIFF / 5)) files/min"
