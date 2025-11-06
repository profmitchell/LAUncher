# Code Signing & Notarization Guide

This guide explains how to code sign and notarize LAUncher for distribution.

## Prerequisites

1. **Apple Developer Account** - Active paid membership ($99/year)
2. **Xcode** - Latest version installed
3. **App-Specific Password** - For notarization (create at appleid.apple.com)

## Code Signing Setup

### 1. Configure Signing in Xcode

1. Open `LAUncher.xcodeproj` in Xcode
2. Select the **LAUncher** target
3. Go to **Signing & Capabilities** tab
4. Check **"Automatically manage signing"**
5. Select your **Team** from the dropdown
6. Xcode will automatically configure signing certificates

### 2. Verify Entitlements

Ensure `LAUncher.entitlements` includes:
- `com.apple.security.cs.disable-library-validation` (required for AU plugins)
- `com.apple.security.temporary-exception.audio-unit-host` (required for AU plugins)

## Building for Distribution

### Archive the App

1. In Xcode, select **Product** → **Archive**
2. Wait for the archive to complete
3. The Organizer window will open automatically

### Export for Distribution

1. In Organizer, select your archive
2. Click **Distribute App**
3. Choose **Developer ID** (for distribution outside App Store)
4. Select **Export** (not Upload)
5. Choose export options:
   - **Export as:** App
   - **Include bitcode:** No
   - **Strip Swift symbols:** Yes
6. Click **Export** and choose a location

## Notarization

### Automatic Notarization (Recommended)

If you selected "Upload" instead of "Export", Xcode will automatically notarize.

### Manual Notarization

1. **Create an app-specific password:**
   - Go to appleid.apple.com
   - Sign in → App-Specific Passwords
   - Create a password for "Xcode Notarization"

2. **Create a notarization keychain profile:**
   ```bash
   xcrun notarytool store-credentials --apple-id "your@email.com" \
     --team-id "YOUR_TEAM_ID" \
     --password "app-specific-password" \
     "notary-profile"
   ```

3. **Submit for notarization:**
   ```bash
   xcrun notarytool submit LAUncher.app \
     --keychain-profile "notary-profile" \
     --wait
   ```

4. **Staple the notarization ticket:**
   ```bash
   xcrun stapler staple LAUncher.app
   ```

5. **Verify notarization:**
   ```bash
   xcrun stapler validate LAUncher.app
   spctl --assess --verbose LAUncher.app
   ```

## Distribution

### Create a DMG (Optional)

1. Create a disk image:
   ```bash
   hdiutil create -volname "LAUncher" -srcfolder LAUncher.app -ov -format UDZO LAUncher.dmg
   ```

2. Notarize the DMG:
   ```bash
   xcrun notarytool submit LAUncher.dmg --keychain-profile "notary-profile" --wait
   xcrun stapler staple LAUncher.dmg
   ```

### Distribution Checklist

- [ ] App is code signed with Developer ID
- [ ] App is notarized by Apple
- [ ] Notarization ticket is stapled
- [ ] App passes `spctl --assess`
- [ ] Entitlements are correct
- [ ] Version number is updated
- [ ] Build number is incremented

## Troubleshooting

### "Code signature is invalid"
- Clean build folder (⌘⇧K)
- Delete DerivedData
- Rebuild and re-archive

### "Notarization failed"
- Check entitlements are correct
- Ensure all frameworks are signed
- Check for hardcoded paths
- Review notarization logs: `xcrun notarytool log <submission-id> --keychain-profile "notary-profile"`

### "App is damaged and can't be opened"
- Ensure notarization ticket is stapled
- Check Gatekeeper: `spctl --assess --verbose LAUncher.app`
- User may need to right-click → Open (first time only)

## Notes

- Notarization can take 5-30 minutes
- Keep notarization logs for troubleshooting
- Test on a clean macOS system before distribution
- Update version/build numbers for each release

