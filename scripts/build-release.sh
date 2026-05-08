#!/bin/bash
set -e

APP_NAME="Apidae"
BUNDLE_ID="app.getapidae.mac"

# TODO: fill in once an Apple Developer account is set up.
# After that, also run once locally to register the notarytool keychain profile:
#   xcrun notarytool store-credentials "apidae-notarize" \
#     --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "<app-specific-password>"
SIGNING_IDENTITY="Developer ID Application: TODO YOUR NAME (TODO_TEAM_ID)"
APPLE_ID="TODO@example.com"
TEAM_ID="TODO_TEAM_ID"

echo "==> Generating Xcode project..."
xcodegen generate

echo "==> Building Release (unsigned)..."
xcodebuild -project ${APP_NAME}.xcodeproj \
  -scheme ${APP_NAME} \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_ALLOWED=NO \
  clean build

APP_PATH="build/DerivedData/Build/Products/Release/${APP_NAME}.app"

echo "==> Preparing clean copy for signing..."
# Copy to /tmp to escape iCloud-managed xattrs that can't be cleared in ~/Documents
SIGN_DIR=$(mktemp -d /tmp/apidae-sign.XXXXXX)
ditto --norsrc "${APP_PATH}" "${SIGN_DIR}/${APP_NAME}.app"
APP_PATH="${SIGN_DIR}/${APP_NAME}.app"

echo "==> Signing with Developer ID + hardened runtime..."
codesign --force --sign "${SIGNING_IDENTITY}" --options runtime --timestamp "${APP_PATH}"

echo "==> Verifying signature..."
codesign --verify --verbose "${APP_PATH}"
spctl --assess --type exec "${APP_PATH}" && echo "   Gatekeeper: ACCEPTED" || echo "   Gatekeeper: will pass after notarization"

echo "==> Creating DMG..."
DMG_DIR="build/dmg"
DMG_PATH="build/${APP_NAME}.dmg"
RW_DMG="build/${APP_NAME}-rw.dmg"
rm -rf "${DMG_DIR}" "${DMG_PATH}" "${RW_DMG}"
mkdir -p "${DMG_DIR}"
cp -R "${APP_PATH}" "${DMG_DIR}/"
rm -rf "${SIGN_DIR}"

# Build R/W DMG directly — no intermediate conversions that lose metadata
DMG_SIZE_MB=$(( $(du -sm "${DMG_DIR}" | awk '{print $1}') + 20 ))
hdiutil create -size ${DMG_SIZE_MB}m -fs HFS+ -volname "${APP_NAME}" -o "${RW_DMG}"
MOUNT_DIR=$(hdiutil attach "${RW_DMG}" -readwrite -noverify | grep Apple_HFS | awk '{print $3}')
echo "   Mounted R/W at: ${MOUNT_DIR}"

# Copy app
cp -R "${DMG_DIR}/${APP_NAME}.app" "${MOUNT_DIR}/"

# Create Finder alias to /Applications (not a symlink — symlinks show broken icon on Sonoma+)
osascript -e "tell application \"Finder\" to make new alias file at POSIX file \"${MOUNT_DIR}\" to POSIX file \"/Applications\""
mv "${MOUNT_DIR}/Applications alias" "${MOUNT_DIR}/Applications" 2>/dev/null || true

# Apply Finder window styling via AppleScript
echo "   Applying Finder window layout..."
VOLNAME=$(basename "${MOUNT_DIR}")
osascript << APPLESCRIPT
tell application "Finder"
  tell disk "${VOLNAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 860, 600}
    set theViewOptions to icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 96
    set text size of theViewOptions to 14
    set position of item "${APP_NAME}.app" to {170, 170}
    set position of item "Applications" to {490, 170}
    try
      set position of item ".fseventsd" to {900, 900}
    end try
    try
      set position of item ".DS_Store" to {900, 900}
    end try
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

# Convert to compressed read-only (single conversion, no metadata loss)
sync
hdiutil detach "${MOUNT_DIR}"
hdiutil convert "${RW_DMG}" -format UDZO -o "${DMG_PATH}"
rm "${RW_DMG}"
rm -rf "${DMG_DIR}"

echo "==> Notarizing..."
xcrun notarytool submit "${DMG_PATH}" \
  --keychain-profile "apidae-notarize" \
  --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "${DMG_PATH}"

echo ""
echo "==> Done! DMG ready at: ${DMG_PATH}"
echo "    Upload this to getapidae.com or attach to a GitHub release."
