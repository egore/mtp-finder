#!/bin/sh
# Install the launch agent plist, bundle libmtp + libusb next to
# the helper and re-sign.
set -eu

APP="$TARGET_BUILD_DIR/$WRAPPER_NAME"
HELPER="$APP/Contents/MacOS/MTPHelper"
FRAMEWORKS="$APP/Contents/Frameworks"
BREW="${BREW_PREFIX:-/opt/homebrew}"
MTP="$BREW/opt/libmtp/lib/libmtp.9.dylib"
USB="$BREW/opt/libusb/lib/libusb-1.0.0.dylib"

mkdir -p "$APP/Contents/Library/LaunchAgents" "$FRAMEWORKS"

if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
    echo "error: DEVELOPMENT_TEAM is empty. Create Config/Local.xcconfig (see README)." >&2
    exit 1
fi

PLIST="com.cbrill.mtpfinder.helper.plist"
sed "s/__TEAM_ID__/$DEVELOPMENT_TEAM/" "$SRCROOT/Resources/$PLIST" > "$APP/Contents/Library/LaunchAgents/$PLIST"

# codesign does not expand build settings in entitlements, Xcode only does for its own signing.
ENTITLEMENTS="$TEMP_DIR/Helper.expanded.entitlements"
sed "s/\$(TeamIdentifierPrefix)/$DEVELOPMENT_TEAM./" "$SRCROOT/Helper/Helper.entitlements" > "$ENTITLEMENTS"

cp -f "$MTP" "$USB" "$FRAMEWORKS/"
chmod u+w "$FRAMEWORKS"/*.dylib

install_name_tool -id @rpath/libmtp.9.dylib "$FRAMEWORKS/libmtp.9.dylib"
install_name_tool -id @rpath/libusb-1.0.0.dylib "$FRAMEWORKS/libusb-1.0.0.dylib"

USB_REF=$(otool -L "$FRAMEWORKS/libmtp.9.dylib" | awk '/libusb-1.0.0.dylib/ {print $1}')
install_name_tool -change "$USB_REF" @rpath/libusb-1.0.0.dylib "$FRAMEWORKS/libmtp.9.dylib"

MTP_REF=$(otool -L "$HELPER" | awk '/libmtp.9.dylib/ {print $1}')
if [ "$MTP_REF" != "@rpath/libmtp.9.dylib" ]; then
    install_name_tool -change "$MTP_REF" @rpath/libmtp.9.dylib "$HELPER"
fi
install_name_tool -add_rpath @executable_path/../Frameworks "$HELPER" 2>/dev/null || true

for lib in "$FRAMEWORKS"/*.dylib; do
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$lib"
done
codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" \
    --entitlements "$ENTITLEMENTS" "$HELPER"
