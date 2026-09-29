#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/Scripts/lib/common.sh"

require_command zip
require_command unzip
require_command codesign

DIST_DIR="$ROOT_DIR/dist"
APP="$DIST_DIR/Kyboardclean.app"
ZIP="$DIST_DIR/Kyboardclean.app.zip"
VERIFY_DIR="$(make_temp_dir Kyboardclean_ZIP_Verify)"
STAGE_DIR="$(make_temp_dir Kyboardclean_ZIP_Stage)"
export COPYFILE_DISABLE=1

cleanup() {
  cleanup_temp_dir "$VERIFY_DIR"
  cleanup_temp_dir "$STAGE_DIR"
}
trap cleanup EXIT

if [[ ! -d "$APP" ]]; then
  echo "ERROR: falta $APP" >&2
  echo "Ejecuta primero: Scripts/build_release.sh" >&2
  exit 1
fi

echo "==> Creando ZIP de la app"
rm -f "$ZIP"
ditto --noextattr --norsrc "$APP" "$STAGE_DIR/Kyboardclean.app"
find "$STAGE_DIR/Kyboardclean.app" -name ".DS_Store" -delete
find "$STAGE_DIR/Kyboardclean.app" -name "._*" -delete
verify_app_signature "$STAGE_DIR/Kyboardclean.app"
verify_release_entitlements "$STAGE_DIR/Kyboardclean.app"
(cd "$STAGE_DIR" && /usr/bin/zip -r -X "$ZIP" "Kyboardclean.app")
unzip -q "$ZIP" -d "$VERIFY_DIR"
verify_app_signature "$VERIFY_DIR/Kyboardclean.app"
verify_release_entitlements "$VERIFY_DIR/Kyboardclean.app"

echo "==> ZIP listo: $ZIP"
