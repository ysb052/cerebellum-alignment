# 경로 설정
BASE="/volume_4/research/seongbong/align/cerebellum_align_verified2"

SRC_IMG="file://$BASE/rendered_sift_new/img/img_rendered"

CONFIG_DIR="/volume_4/research/seongbong/align/cerebellum_align_verified2/metroem_corgie_adapter/configs"

PROCESSOR_SPEC="$(cat "$CONFIG_DIR/metroem_processor.yaml")"

# Z 범위
Z_START=325
Z_END=455
BLOCK_SIZE=40

# 40 section씩 순차 실행
for ((z=$Z_START; z<$Z_END; z+=BLOCK_SIZE)); do

    end=$((z + BLOCK_SIZE))

    if ((end > Z_END)); then
        end=$Z_END
    fi

    DST="file://$BASE/align_block_mip8/block_${z}_${end}"

    echo "========================================"
    echo "Aligning z=$z to z=$((end-1))"
    echo "Output: $DST"
    echo "========================================"

    CUDA_VISIBLE_DEVICES=0 corgie align-block \
      --src_layer_spec "{\"name\":\"img\",\"type\":\"img\",\"path\":\"$SRC_IMG\",\"args\":{\"data_mip\":8}}" \
      --dst_folder "$DST" \
      --processor_spec "$PROCESSOR_SPEC" \
      --processor_mip 8 \
      --vote_dist 3 \
      --mode forward \
      --chunk_xy 512 \
      --pad 64 \
      --start_coord "0,0,$z" \
      --end_coord "249600,230400,$end" \
      --coord_mip 0 \
      --device cuda \
      --verbose || break

done
