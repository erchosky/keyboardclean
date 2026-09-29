#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/Scripts/lib/common.sh"

require_command rsync
require_command zip

DIST_DIR="$ROOT_DIR/dist"
ZIP="$DIST_DIR/Kyboardclean_Source.zip"
TMP_DIR="$(make_temp_dir Kyboardclean_Source_Package)"
export COPYFILE_DISABLE=1

cleanup() {
  cleanup_temp_dir "$TMP_DIR"
}
trap cleanup EXIT

echo "==> Creando ZIP limpio del codigo fuente"
mkdir -p "$DIST_DIR"
mkdir -p "$TMP_DIR/Kyboardclean_Source"

rsync -a \
  --exclude ".git" \
  --exclude "dist" \
  --exclude "DerivedData" \
  --exclude ".build" \
  --exclude ".swiftpm" \
  --exclude "*/xcshareddata/swiftpm" \
  --exclude "*/xcshareddata/swiftpm/**" \
  --exclude "xcuserdata" \
  --exclude "*.xcuserstate" \
  --exclude ".DS_Store" \
  --exclude "*.log" \
  --exclude "*.cache" \
  --exclude "*.tmp" \
  --exclude "*.app" \
  --exclude "*.dmg" \
  --exclude "*.zip" \
  --exclude "*.dSYM" \
  --exclude "*.o" \
  --exclude "*.swiftmodule" \
  --exclude "*.swiftdoc" \
  "$ROOT_DIR/" "$TMP_DIR/Kyboardclean_Source/"

rm -f "$ZIP"
(cd "$TMP_DIR" && /usr/bin/zip -r -X "$ZIP" Kyboardclean_Source)

echo "==> ZIP de fuente listo: $ZIP"
