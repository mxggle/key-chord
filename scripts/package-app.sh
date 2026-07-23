#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
PRODUCT_NAME="App Switcher"
BUILD_DIR="${PROJECT_DIR}/.build"
APP_PATH="${BUILD_DIR}/${PRODUCT_NAME}.app"
EXECUTABLE_PATH="${PROJECT_DIR}/.build/release/AppSwitcher"

cd "${PROJECT_DIR}"
swift build -c release

if [[ "${APP_PATH}" != "${PROJECT_DIR}/.build/${PRODUCT_NAME}.app" ]]; then
    print -u2 "Refusing to replace an unexpected bundle path: ${APP_PATH}"
    exit 1
fi

rm -rf "${APP_PATH}"
mkdir -p "${APP_PATH}/Contents/MacOS"
cp "${EXECUTABLE_PATH}" "${APP_PATH}/Contents/MacOS/AppSwitcher"
cp "${PROJECT_DIR}/packaging/Info.plist" "${APP_PATH}/Contents/Info.plist"

SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [[ -z "${SIGNING_IDENTITY}" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/valid identities found/ { next } /\) [A-F0-9]{40} / { print $2; exit }')"
fi
if [[ -z "${SIGNING_IDENTITY}" ]]; then
    SIGNING_IDENTITY="-"
fi

codesign --force --options runtime --sign "${SIGNING_IDENTITY}" "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
print "${APP_PATH}"
