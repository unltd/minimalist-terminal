#!/usr/bin/env bash
set -euo pipefail

# Deploy: publish a new release to GitHub
# Fill in the placeholders below for your setup.

VERSION="${1:-}"

if [ -z "$VERSION" ]; then
  echo "Usage: ./scripts/deploy.sh <version>"
  echo "Example: ./scripts/deploy.sh v0.2.0"
  exit 1
fi

# 1. Update version in manifest.json and package.json
# (edit manually or use: npm version <version> --no-git-tag-version)

# 2. Build
npm run build

# 3. Commit and tag
git add manifest.json package.json versions.json
git commit -m "chore: bump version to $VERSION"
git tag "$VERSION"

# 4. Push
git push origin main
git push origin "$VERSION"

# 5. Create GitHub Release
gh release create "$VERSION" \
  --title "$VERSION" \
  --notes "See [CHANGELOG.md](CHANGELOG.md) for details." \
  main.js manifest.json styles.css

echo "Release $VERSION created."
echo "For Obsidian Community Plugin submission, see: https://docs.obsidian.md/Plugins/Releasing/Submit+your+plugin"
