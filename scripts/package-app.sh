#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
PRODUCT_NAME="KeyChord"
BUILD_DIR="${PROJECT_DIR}/.build"
APP_PATH="${BUILD_DIR}/${PRODUCT_NAME}.app"
EXECUTABLE_PATH="${PROJECT_DIR}/.build/release/KeyChord"

cd "${PROJECT_DIR}"
swift build -c release

if [[ "${APP_PATH}" != "${PROJECT_DIR}/.build/${PRODUCT_NAME}.app" ]]; then
    print -u2 "Refusing to replace an unexpected bundle path: ${APP_PATH}"
    exit 1
fi

rm -rf "${APP_PATH}"
mkdir -p "${APP_PATH}/Contents/MacOS"
mkdir -p "${APP_PATH}/Contents/Resources"
cp "${EXECUTABLE_PATH}" "${APP_PATH}/Contents/MacOS/KeyChord"
cp "${PROJECT_DIR}/packaging/Info.plist" "${APP_PATH}/Contents/Info.plist"
if [[ -f "${PROJECT_DIR}/packaging/AppIcon.icns" ]]; then
    cp "${PROJECT_DIR}/packaging/AppIcon.icns" "${APP_PATH}/Contents/Resources/AppIcon.icns"
fi

SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [[ -z "${SIGNING_IDENTITY}" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/valid identities found/ { next } /\) [A-F0-9]{40} / { print $2; exit }')"
fi
if [[ -z "${SIGNING_IDENTITY}" ]]; then
    SIGNING_IDENTITY="-"
fi

codesign --force --options runtime --sign "${SIGNING_IDENTITY}" "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
print "App bundle created: ${APP_PATH}"

# Generate ZIP archive
ZIP_PATH="${BUILD_DIR}/${PRODUCT_NAME}.zip"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"
print "ZIP archive created: ${ZIP_PATH}"

# Generate DMG installer
DMG_ROOT="${BUILD_DIR}/dmg_root"
DMG_PATH="${BUILD_DIR}/${PRODUCT_NAME}.dmg"
rm -rf "${DMG_ROOT}" "${DMG_PATH}"
mkdir -p "${DMG_ROOT}"
cp -R "${APP_PATH}" "${DMG_ROOT}/"
ln -s /Applications "${DMG_ROOT}/Applications"
hdiutil create -volname "${PRODUCT_NAME}" -srcfolder "${DMG_ROOT}" -ov -format UDZO "${DMG_PATH}" >/dev/null
rm -rf "${DMG_ROOT}"
print "DMG image created: ${DMG_PATH}"

