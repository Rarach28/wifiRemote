#!/usr/bin/env bash
# Build WiFi Remote.app and install it in ~/Applications.
#
# The app's login agent runs helper/remote.py from this checkout, so keep the repository where it is
# (or rebuild after moving it). Needs Xcode 26+, xcodegen (brew install xcodegen) and an "Apple Development"
# signing certificate: macOS only loads widgets from a signed extension.
#
# Usage: ./build.sh                       add TVs later in the app's Settings
#        TV_HOST=192.168.1.50 ./build.sh  start with this TV already in the list
#        ./build.sh --no-install          build only (build/dd/Build/Products/Release/WiFiRemote.app)
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"
TV_HOST="${TV_HOST:-}"

# Python environment for the ADB helper.
PY="$ROOT/helper/.venv/bin/python"
if [ ! -x "$PY" ]; then
    echo "Creating helper/.venv"
    python3 -m venv helper/.venv
    "$PY" -m pip install --quiet -r helper/requirements.txt
fi

# The team is the OU of the first Apple Development certificate in the keychain.
TEAM_ID="${TEAM_ID:-$(security find-certificate -c "Apple Development" -p 2>/dev/null | openssl x509 -noout -subject \
    | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p')}"
[ -n "$TEAM_ID" ] || { echo "No Apple Development certificate found. Sign in to Xcode or set TEAM_ID." >&2; exit 1; }
export TEAM_ID

mkdir -p build
# A random token the agent wants on every request; kept across rebuilds so a running agent and new widgets agree.
[ -f build/token ] || "$PY" -I -c 'import secrets; print(secrets.token_hex(16))' > build/token
cat > build/BuildConfig.swift <<SWIFT
enum BuildConfig {
    static let repo = "$ROOT"
    static let python = "$PY"
    static let tvHost = "$TV_HOST"
    static let agentPort: UInt16 = 47811
    static let agentToken = "$(cat build/token)"
}
SWIFT

# App icon
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
    -quiet build
APP="build/dd/Build/Products/Release/WiFiRemote.app"
if [ "${1:-}" = --no-install ]; then echo "Built $APP"; exit 0; fi

# Replace the installed copy; launchd restarts the agent from it (KeepAlive).
pkill -x WiFiRemote 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/WiFiRemote.app
cp -R "$APP" ~/Applications/
pkill -f "^WiFiRemote --agent" 2>/dev/null || true
echo "Installed ~/Applications/WiFiRemote.app"
