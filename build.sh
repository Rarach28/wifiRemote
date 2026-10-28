#!/usr/bin/env bash
# Build WiFi Remote.app and install it in ~/Applications.
#
# Needs Xcode 26+, XcodeGen (brew install xcodegen) and an "Apple Development" signing certificate (a free
# Apple account signed in to Xcode is enough): macOS only loads widgets from a signed extension.
#
# Usage: ./build.sh                build, then install in ~/Applications
#        ./build.sh --no-install   build only (build/dd/Build/Products/Release/WiFiRemote.app)
#        ./build.sh --release      build and zip for a GitHub release (build/WiFiRemote-<version>.zip)
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:-}"

# The team is the OU of the first Apple Development certificate in the keychain.
TEAM_ID="${TEAM_ID:-$(security find-certificate -c "Apple Development" -p 2>/dev/null | openssl x509 -noout -subject \
    | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p')}"
[ -n "$TEAM_ID" ] || { echo "No Apple Development certificate found. Sign in to Xcode or set TEAM_ID." >&2; exit 1; }
export TEAM_ID

# App icon
mkdir -p build
swift icon.swift build/icon.png
SET=build/Assets.xcassets/AppIcon.appiconset
rm -rf build/Assets.xcassets && mkdir -p $SET
printf '{"info":{"version":1,"author":"xcode"}}' > build/Assets.xcassets/Contents.json
IMAGES=""
for s in 16 32 128 256 512; do
    sips -z $s $s build/icon.png --out $SET/icon_$s.png >/dev/null
    sips -z $((s * 2)) $((s * 2)) build/icon.png --out $SET/icon_$s@2x.png >/dev/null
    IMAGES="$IMAGES{\"idiom\":\"mac\",\"size\":\"${s}x$s\",\"scale\":\"1x\",\"filename\":\"icon_$s.png\"},"
    IMAGES="$IMAGES{\"idiom\":\"mac\",\"size\":\"${s}x$s\",\"scale\":\"2x\",\"filename\":\"icon_$s@2x.png\"},"
done
printf '{"images":[%s],"info":{"version":1,"author":"xcode"}}' "${IMAGES%,}" > $SET/Contents.json

xcodegen generate --quiet
xcodebuild -project WiFiRemote.xcodeproj -scheme WiFiRemote -configuration Release -derivedDataPath build/dd \
    -destination 'generic/platform=macOS' -quiet build
APP="build/dd/Build/Products/Release/WiFiRemote.app"

case "$MODE" in
--no-install)
    echo "Built $APP" ;;
--release)
    VERSION=$(defaults read "$PWD/$APP/Contents/Info.plist" CFBundleShortVersionString)
    ZIP="build/WiFiRemote-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Built $ZIP" ;;
*)
    # Replace the installed copy; launchd restarts the agent from it (KeepAlive).
    pkill -x WiFiRemote 2>/dev/null || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/WiFiRemote.app
    cp -R "$APP" ~/Applications/
    pkill -f "^WiFiRemote --agent" 2>/dev/null || true
    echo "Installed ~/Applications/WiFiRemote.app" ;;
esac
