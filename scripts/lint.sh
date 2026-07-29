#!/usr/bin/env bash
set -euo pipefail

echo "==> TypeScript type-check..."
npx tsc -noEmit -skipLibCheck

echo "==> ESLint (if configured)..."
if [ -f ".eslintrc.js" ] || [ -f ".eslintrc.json" ] || [ -f "eslint.config.mjs" ]; then
  npx eslint .
else
  echo "(no ESLint config found — skipping)"
fi
