#!/bin/bash
# Serve Bonsai 2 27B (PQ2_0) with the prism llama.cpp fork on an OpenAI-compatible port.
# Wraps the demo's own start script so every flag it sets (Metal offload, --jinja tool calling,
# mmproj vision, sampling defaults) stays exactly as tested. Run from a Bonsai-demo checkout.
set -euo pipefail
cd "${BONSAI_DEMO:-$HOME/projects/bonsai-demo}"
export PORT="${PORT:-8091}"
export BONSAI_FAMILY=bonsai2 BONSAI_MODEL=27B
export BONSAI_CTX="${BONSAI_CTX:-131072}"      # Studio 128 GB. Use 65536 on a 24 GB Mac mini.
exec ./scripts/start_llama_server.sh --parallel 1 --alias Ternary-Bonsai-2-27B "$@"
