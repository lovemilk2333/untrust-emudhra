#!/usr/bin/env bash
# Build Magisk/KernelSU installable zip
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

VERSION=$(grep '^version=' module.prop | cut -d= -f2)
ID=$(grep '^id=' module.prop | cut -d= -f2)
OUT_DIR="$ROOT/dist"
ZIP_NAME="${ID}-${VERSION}.zip"
OUT="$OUT_DIR/$ZIP_NAME"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# Ensure scripts are executable in the archive
chmod 755 post-fs-data.sh service.sh uninstall.sh customize.sh build.sh 2>/dev/null || true
chmod 644 module.prop common.sh README.md 2>/dev/null || true
chmod 755 META-INF/com/google/android/update-binary 2>/dev/null || true

# Zip contents (no parent folder)
zip -r9 "$OUT" \
  META-INF \
  module.prop \
  common.sh \
  post-fs-data.sh \
  service.sh \
  uninstall.sh \
  customize.sh \
  README.md \
  LICENSE \
  -x '*.DS_Store' -x '*~' -x 'workspace/*' -x 'dist/*' -x '.git/*'

echo "Built: $OUT"
unzip -l "$OUT"
