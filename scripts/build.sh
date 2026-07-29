#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing dependencies..."
npm ci

echo "==> Building..."
npm run build

echo "==> Build complete: main.js"
