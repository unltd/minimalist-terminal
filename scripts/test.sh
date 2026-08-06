#!/usr/bin/env bash
set -euo pipefail

echo "==> Running pytest CDP tests..."
pytest tests/test_mvp_dod.py -v
