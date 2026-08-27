#!/usr/bin/env bash

set -e

exec distrobox enter llama-vulkan-radv -- \
  llama-server \
    -m /home/evo/models/Qwen3.8/bartowski/Qwen3.8-27B-Q4_K_L.gguf \
    -ngl 999 \
    -c 65536 \
    -np 1 \
    --spec-type draft-mtp \
    --spec-draft-n-max 2 \
    --spec-draft-p-min 0.8 \
    --host 0.0.0.0 \
    --port 8080