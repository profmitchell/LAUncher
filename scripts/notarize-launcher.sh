#!/usr/bin/env bash
# Build LAUncher with Developer ID, zip, submit to Apple Notary Service, staple.
#
# Auth (pick one):
#   1) NOTARY_KEYCHAIN_PROFILE — from: xcrun notarytool store-credentials "notary-profile" ...
#   2) NOTARY_APPLE_ID + NOTARY_PASSWORD + NOTARY_TEAM_ID (default team 84MVV46VM6)
#   3) NOTARY_KEY + NOTARY_KEY_ID + NOTARY_ISSUER (App Store Connect API key)
#
# Optional: SKIP_BUILD=1 NOTARIZE_APP_PATH=/path/to/LAUncher.app
# Optional: CREATE_DMG=1 writes LAUncher-<version>-arm64.dmg next to the app

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="${ROOT}/build/notarize/DerivedData"
OUTDIR="${ROOT}/build/notarize"
TEAM_ID="${NOTARY_TEAM_ID:-84MVV46VM6}"
SIGN_ID="${CODE_SIGN_IDENTITY:-Developer ID Application: Mitchell Cohen (${TEAM_ID})}"

mkdir -p "${OUTDIR}"

auth_args=()
if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  auth_args+=(--keychain-profile "${NOTARY_KEYCHAIN_PROFILE}")
elif [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]; then
  auth_args+=(--apple-id "${NOTARY_APPLE_ID}" --password "${NOTARY_PASSWORD}" --team-id "${TEAM_ID}")
elif [[ -n "${NOTARY_KEY:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER:-}" ]]; then
  auth_args+=(--key "${NOTARY_KEY}" --key-id "${NOTARY_KEY_ID}" --issuer "${NOTARY_ISSUER}")
else
  echo "Notary credentials missing. Set one of:" >&2
  echo "  NOTARY_KEYCHAIN_PROFILE, or NOTARY_APPLE_ID+NOTARY_PASSWORD+NOTARY_TEAM_ID, or NOTARY_KEY+NOTARY_KEY_ID+NOTARY_ISSUER" >&2
  echo "See CODE_SIGNING.md in this repo." >&2
  exit 1
fi

if [[ "${SKIP_BUILD:-0}" == "1" && -n "${NOTARIZE_APP_PATH:-}" ]]; then
  APP="${NOTARIZE_APP_PATH}"
else
  echo "Building Release (Developer ID)…"
  xcodebuild -project "${ROOT}/LAUncher.xcodeproj" \
    -scheme LAUncher \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "${DERIVED}" \
    CODE_SIGN_IDENTITY="${SIGN_ID}" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    build
  APP="${DERIVED}/Build/Products/Release/LAUncher.app"
fi

[[ -d "${APP}" ]] || { echo "Missing app: ${APP}" >&2; exit 1; }

# Ensure secure timestamp (required for notarization) even if Xcode omitted it.
ENTITLEMENTS="${ROOT}/LAUncher/LAUncher.entitlements"
if [[ -f "${ENTITLEMENTS}" ]]; then
  codesign --force --deep --options runtime --timestamp \
    --entitlements "${ENTITLEMENTS}" \
    --sign "${SIGN_ID}" "${APP}"
else
  codesign --force --deep --options runtime --timestamp \
    --sign "${SIGN_ID}" "${APP}"
fi

codesign --verify --deep --strict --verbose=2 "${APP}"

VER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "${APP}/Contents/Info.plist" 2>/dev/null || echo "0.0.0")"
ZIP="${OUTDIR}/LAUncher-${VER}-notarize.zip"

echo "Zipping ${ZIP}…"
rm -f "${ZIP}"
ditto -c -k --keepParent "${APP}" "${ZIP}"

echo "Submitting to Apple Notary Service (--wait)…"
xcrun notarytool submit "${ZIP}" "${auth_args[@]}" --wait

echo "Stapling ticket to app…"
xcrun stapler staple "${APP}"

echo "Validating staple…"
xcrun stapler validate "${APP}"

echo "Gatekeeper (should accept when notarized):"
spctl -a -vv "${APP}" 2>&1 || true

if [[ "${CREATE_DMG:-0}" == "1" ]]; then
  DMG="${OUTDIR}/LAUncher-${VER}-arm64.dmg"
  echo "Creating ${DMG}…"
  rm -f "${DMG}"
  hdiutil create -volname "LAUncher" -srcfolder "${APP}" -ov -format UDZO "${DMG}"
  echo "Submitting DMG for notarization (second ticket for the disk image)…"
  xcrun notarytool submit "${DMG}" "${auth_args[@]}" --wait
  xcrun stapler staple "${DMG}"
  xcrun stapler validate "${DMG}"
  echo "Done. DMG: ${DMG}"
else
  echo "Done. Signed + stapled app: ${APP}"
  echo "Optional: CREATE_DMG=1 $0 to also build a stapled DMG."
fi
