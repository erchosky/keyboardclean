#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/Scripts/lib/common.sh"

require_command xcodebuild
require_command ditto
require_command codesign
require_command security

DIST_DIR="$ROOT_DIR/dist"
DERIVED_DATA="$(make_temp_dir Kyboardclean_Distribution_DerivedData)"
APP_NAME="Kyboardclean.app"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME"
DIST_APP="$DIST_DIR/$APP_NAME"
ENTITLEMENTS="$ROOT_DIR/Kyboardclean/Resources/Kyboardclean.entitlements"
export COPYFILE_DISABLE=1

cleanup() {
  cleanup_temp_dir "$DERIVED_DATA"
}
trap cleanup EXIT

echo "==> Compilando Kyboardclean en Release"
mkdir -p "$DIST_DIR"

xcodebuild \
  -project "$ROOT_DIR/Kyboardclean.xcodeproj" \
  -scheme Kyboardclean \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS="arm64 x86_64" \
  build

if [[ ! -d "$BUILT_APP" ]]; then
  echo "ERROR: no se encontro $BUILT_APP" >&2
  exit 1
fi

echo "==> Copiando app a dist/"
rm -rf "$DIST_APP"
ditto "$BUILT_APP" "$DIST_APP"
find "$DIST_APP" -name ".DS_Store" -delete
clean_app_metadata "$DIST_APP"

DEVELOPER_ID_CERT="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '\"' '/Developer ID Application/ { print $2; exit }')"

if [[ -n "$DEVELOPER_ID_CERT" ]]; then
  echo "==> Firmando con Developer ID Application: $DEVELOPER_ID_CERT"
  if ! codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$DEVELOPER_ID_CERT" "$DIST_APP"; then
    echo "AVISO: fallo la firma con timestamp. Reintentando sin timestamp para uso local."
    codesign --force --options runtime --timestamp=none --entitlements "$ENTITLEMENTS" --sign "$DEVELOPER_ID_CERT" "$DIST_APP"
  fi
  echo "==> App firmada. Para distribucion publica, notariza la app con Apple."
else
  echo "==> No se encontro certificado Developer ID Application."
  echo "==> Se conserva la firma local generada por Xcode. Es valida para uso personal."
  echo "==> Sin notarizacion, Gatekeeper puede mostrar avisos en otros Mac."
fi

verify_app_signature "$DIST_APP"
verify_release_entitlements "$DIST_APP"

echo "==> Release listo: $DIST_APP"
