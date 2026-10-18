#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
bash Scripts/fetch-upstream.sh
revision="$(tr -d '\n' < upstream.lock)"
cmake -S vendor/llama.cpp -B build-mac -DCMAKE_BUILD_TYPE=Release \
    -DGGML_RPC=ON -DGGML_RPC_RDMA=OFF -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_ACCELERATE=ON \
    -DGGML_CPU_KLEIDIAI=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_UI=OFF \
    -DLLAMA_USE_PREBUILT_UI=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_APP=OFF \
    -DLLAMA_BUILD_COMMIT="$revision" -DLLAMA_BUILD_NUMBER=0
cmake --build build-mac --target llama-server llama-bench --parallel "${JOBS:-4}"
