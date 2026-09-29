#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/Scripts/lib/common.sh"

require_command ditto
require_command codesign
require_command hdiutil

DIST_DIR="$ROOT_DIR/dist"
APP="$DIST_DIR/Kyboardclean.app"
DMG="$DIST_DIR/Kyboardclean.dmg"
DMG_ROOT="$(make_temp_dir Kyboardclean_DMG_Root)"
export COPYFILE_DISABLE=1

cleanup() {
  cleanup_temp_dir "$DMG_ROOT"
}
trap cleanup EXIT

if [[ ! -d "$APP" ]]; then
  echo "ERROR: falta $APP" >&2
  echo "Ejecuta primero: Scripts/build_release.sh" >&2
  exit 1
fi

echo "==> Preparando contenido del DMG"
ditto --noextattr --norsrc "$APP" "$DMG_ROOT/Kyboardclean.app"
ln -s /Applications "$DMG_ROOT/Applications"
find "$DMG_ROOT" -name ".DS_Store" -delete
find "$DMG_ROOT" -name "._*" -delete
xattr -cr "$DMG_ROOT" 2>/dev/null || true
xattr -d com.apple.FinderInfo "$DMG_ROOT" 2>/dev/null || true
xattr -dr com.apple.FinderInfo "$DMG_ROOT" 2>/dev/null || true
xattr -cr "$DMG_ROOT/Kyboardclean.app" 2>/dev/null || true
verify_app_signature "$DMG_ROOT/Kyboardclean.app"
verify_release_entitlements "$DMG_ROOT/Kyboardclean.app"

echo "==> Creando $DMG"
rm -f "$DMG"
hdiutil create \
  -volname "Kyboardclean" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG"

echo "==> DMG listo: $DMG"
echo "==> En otro Mac: abre el DMG y arrastra Kyboardclean.app a Applications."
echo "==> Si Gatekeeper avisa, usa clic derecho > Abrir."
