#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
# Source archives contain the patched engine and do not need a Git checkout.
python3 Scripts/verify-source.py --engine-only
