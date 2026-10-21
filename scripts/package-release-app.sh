#!/usr/bin/env bash
# Build Release and copy LAUncher.app + a .app.zip into build/dist/ for sharing or GitHub Releases.
# macOS GUI apps must be distributed as the .app bundle (or zip/dmg of it), not the bare Mach-O in Contents/MacOS/.
#
# Optional overrides:
#   CODE_SIGN_IDENTITY="Developer ID Application: …" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=…
#   DERIVED_DATA_PATH=/custom/path

set -euo pipefail

# Avoid AppleDouble `._*` files in zips when the repo lives on some network volumes.
export COPYFILE_DISABLE=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="${DERIVED_DATA_PATH:-${ROOT}/build/release/DerivedData}"
DIST="${ROOT}/build/dist"
mkdir -p "${DIST}"

xcargs=(
  -project "${ROOT}/LAUncher.xcodeproj"
  -scheme LAUncher
  -configuration Release
  -destination "platform=macOS"
  -derivedDataPath "${DERIVED}"
)
[[ -n "${CODE_SIGN_IDENTITY:-}" ]] && xcargs+=(CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY}")
[[ -n "${CODE_SIGN_STYLE:-}" ]] && xcargs+=(CODE_SIGN_STYLE="${CODE_SIGN_STYLE}")
[[ -n "${DEVELOPMENT_TEAM:-}" ]] && xcargs+=(DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}")

echo "Building Release…"
xcodebuild "${xcargs[@]}" build

APP_SRC="${DERIVED}/Build/Products/Release/LAUncher.app"
[[ -d "${APP_SRC}" ]] || { echo "Missing ${APP_SRC}" >&2; exit 1; }

VER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "${APP_SRC}/Contents/Info.plist" 2>/dev/null || echo "0.0.0")"
ARCH="$(uname -m)"

rm -rf "${DIST}/LAUncher.app"
ditto "${APP_SRC}" "${DIST}/LAUncher.app"

ZIP="${DIST}/LAUncher-${VER}-macos-${ARCH}.app.zip"
rm -f "${ZIP}"
ditto -c -k --keepParent "${DIST}/LAUncher.app" "${ZIP}"

echo ""
echo "Output:"
echo "  ${DIST}/LAUncher.app"
echo "  ${ZIP}"
echo ""
echo "Upload the .app.zip (or notarized DMG) to GitHub Releases — not a bare binary from Contents/MacOS/."
