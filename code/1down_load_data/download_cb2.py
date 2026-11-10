
from cloudvolume import CloudVolume
from concurrent.futures import ThreadPoolExecutor, as_completed
from tqdm.auto import tqdm
import numpy as np
import threading
from pathlib import Path
import time

SRC_URL = "https://bossdb-open-data.s3.amazonaws.com/nguyen_thomas2022/cb2/em"
DST_URL = "file:///volume_4/research/seongbong/align/Final_cerebellum_alignment/img_raw"

Z_START = 0
Z_END = 1200  # exclusive: z=700까지 포함

WORKERS_BY_MIP = {
    8: 4,
    7: 16,
    6: 32,
    5: 32,
    4: 32,
    3: 32,
    2: 32,
}


CHECKPOINT_DIR = Path(
    "/volume_4/research/seongbong/align/"
    "Final_cerebellum_alignment/download_checkpoints"
)
CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)

# Worker마다 별도 CloudVolume 객체 사용
thread_local = threading.local()


def get_volumes(mip):
    if getattr(thread_local, "mip", None) != mip:
        thread_local.src = CloudVolume(
            SRC_URL,
            mip=mip,
            progress=False,
            fill_missing=False
        )
        thread_local.dst = CloudVolume(
            DST_URL,
            mip=mip,
            progress=False,
            compress=False
        )
        thread_local.mip = mip

    return thread_local.src, thread_local.dst


def download_tile(task):
    mip, x, xe, y, ye, z_batch, ze = task

    src, dst = get_volumes(mip)

    # S3에서 Z chunk 단위로 다운로드
    block = np.asarray(
        src[x:xe, y:ye, z_batch:ze, :]
    )

    # 필요한 section만 저장
    zs = max(z_batch, Z_START)
    zend = min(ze, Z_END)

    for z in range(zs, zend):
        k = z - z_batch

        dst[x:xe, y:ye, z:z+1, :] = (
            block[:, :, k:k+1, :]
        )

    return len(range(zs, zend))


for mip in 	[8,7,6,5,4,3,2]:
    MAX_WORKERS = WORKERS_BY_MIP[mip]
    src = CloudVolume(
        SRC_URL,
        mip=mip,
        progress=False,
        fill_missing=False
    )

    dst = CloudVolume(
        DST_URL,
        mip=mip,
        progress=False,
        compress=False
    )

    x0, y0 = map(int, src.bounds.minpt[:2])
    x1, y1 = map(int, src.bounds.maxpt[:2])

    cx, cy, _ = map(int, dst.chunk_size)
    src_cz = int(src.chunk_size[2])

    src_zmin = int(src.bounds.minpt.z)
    src_zmax = int(src.bounds.maxpt.z)

    if not (src_zmin <= Z_START < Z_END <= src_zmax):
        raise ValueError("Requested Z range exceeds source bounds")

    # 병렬 쓰기 시 목적지 chunk가 겹치지 않도록 확인
    ox, oy = map(int, dst.bounds.minpt[:2])

    if (x0 - ox) % cx or (y0 - oy) % cy:
        raise ValueError(
            "XY tile boundaries are not aligned to destination chunks"
        )

    z0 = src_zmin + (
        (Z_START - src_zmin) // src_cz
    ) * src_cz

    print(f"\nMIP {mip}")
    print("Source chunk:", src.chunk_size)
    print("Destination chunk:", dst.chunk_size)
    print("Workers:", MAX_WORKERS)

    with ThreadPoolExecutor(
        max_workers=MAX_WORKERS
    ) as executor:

        for z_batch in range(z0, Z_END, src_cz):
            checkpoint = CHECKPOINT_DIR / f"mip{mip}_z{z_batch}.done"
            
            if checkpoint.exists():
                print(f"Skipping MIP {mip}, z={z_batch}")
                continue
            
            start_time = time.time()
            
            ze = min(
                z_batch + src_cz,
                src_zmax,
                Z_END
            )

            tasks = [
                (mip, x, min(x + cx, x1),
                 y, min(y + cy, y1),
                 z_batch, ze)
                for y in range(y0, y1, cy)
                for x in range(x0, x1, cx)
            ]

            futures = [
                executor.submit(download_tile, task)
                for task in tasks
            ]

            for future in tqdm(
                as_completed(futures),
                total=len(futures),
                desc=f"MIP{mip} z={z_batch}"
            ):
                future.result()
                
            checkpoint.touch()

            elapsed = time.time() - start_time
            print(
                f"MIP {mip}, z={z_batch} completed "
                f"in {elapsed:.1f} seconds"
            )

    print(f"MIP{mip} completed")
