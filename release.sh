#!/bin/bash
# PromptShelf Release Script
# Developer ID signing + Notarization + DMG packaging
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ── Configuration ────────────────────────────────────────────────────────────
APP_NAME="PromptShelf"
BUNDLE_ID="com.promptshelf.app"
SIGNING_IDENTITY="Developer ID Application: TOGG (U2QA72Q6BP)"
TEAM_ID="U2QA72Q6BP"
ENTITLEMENTS="$SCRIPT_DIR/PromptShelf.entitlements"

APP_PATH="$SCRIPT_DIR/$APP_NAME.app"
RELEASE_DIR="$SCRIPT_DIR/release"
ZIP_PATH="$RELEASE_DIR/$APP_NAME.zip"
DMG_PATH="$RELEASE_DIR/$APP_NAME.dmg"

# ── Notarization credentials (set via env vars or fill in directly) ──────────
#   export APPLE_ID="your@email.com"
#   export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"  ← generate at appleid.apple.com
APPLE_ID="${APPLE_ID:-}"
APPLE_APP_PASSWORD="${APPLE_APP_PASSWORD:-}"

if [ -z "$APPLE_ID" ] || [ -z "$APPLE_APP_PASSWORD" ]; then
    echo "❌ Apple ID credentials are required."
    echo ""
    echo "Set the following environment variables before running:"
    echo "  export APPLE_ID=\"your@email.com\""
    echo "  export APPLE_APP_PASSWORD=\"xxxx-xxxx-xxxx-xxxx\""
    echo ""
    echo "Generate an app-specific password at: https://appleid.apple.com → Security → App-Specific Passwords"
    exit 1
fi

mkdir -p "$RELEASE_DIR"

# ── 1. Build ─────────────────────────────────────────────────────────────────
echo "🔨 [1/6] Building release..."
swift build -c release

# ── 2. Create .app bundle ────────────────────────────────────────────────────
echo "📦 [2/6] Creating .app bundle..."
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

cp ".build/release/$APP_NAME"               "$APP_PATH/Contents/MacOS/"
cp "Sources/$APP_NAME/Resources/Info.plist" "$APP_PATH/Contents/"

# App icon
cp "Sources/$APP_NAME/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/"

# Resource bundle (sounds, videos, etc.)
if [ -d ".build/release/$APP_NAME.bundle" ]; then
    cp -r ".build/release/$APP_NAME.bundle" "$APP_PATH/Contents/Resources/"
fi

# ── 3. Developer ID signing (Hardened Runtime required) ──────────────────────
echo "✍️  [3/6] Signing with Developer ID..."
codesign \
    --force \
    --deep \
    --options=runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY" \
    --timestamp \
    "$APP_PATH"

echo "🔍 Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type exec --verbose "$APP_PATH" 2>&1 || true

# ── 4. ZIP for notarytool submission ─────────────────────────────────────────
echo "🗜️  [4/6] Compressing to ZIP..."
cd "$RELEASE_DIR"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
cd "$SCRIPT_DIR"

# ── 5. Submit for Notarization ───────────────────────────────────────────────
echo "🍎 [5/6] Submitting for Apple Notarization... (usually 1–3 min)"
xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait

# ── 6. Staple notarization ticket ────────────────────────────────────────────
echo "📎 [6/6] Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

# ── DMG packaging (requires create-dmg) ──────────────────────────────────────
if command -v create-dmg &>/dev/null; then
    echo "💿 Packaging DMG..."
    rm -f "$DMG_PATH"
    create-dmg \
        --volname "$APP_NAME" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 175 190 \
        --hide-extension "$APP_NAME.app" \
        --app-drop-link 425 190 \
        "$DMG_PATH" \
        "$APP_PATH"

    # Sign the DMG as well
    codesign --sign "$SIGNING_IDENTITY" "$DMG_PATH"
    echo "✅ DMG ready: $DMG_PATH"
else
    echo "ℹ️  create-dmg not found — ZIP only. Install with: brew install create-dmg"
fi

echo ""
echo "🎉 Release complete!"
echo "   App: $APP_PATH"
echo "   ZIP: $ZIP_PATH"
[ -f "$DMG_PATH" ] && echo "   DMG: $DMG_PATH"
echo ""
echo "Upload the ZIP or DMG to GitHub Releases."
