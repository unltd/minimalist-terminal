#!/usr/bin/env bash
set -euo pipefail

echo "==> Running Gauge BDD tests..."
gauge run tests/specs/

echo "==> Running pytest CDP tests..."
pytest tests/ -v
