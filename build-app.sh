#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="PromptShelf"
APP_PATH="$SCRIPT_DIR/$APP_NAME.app"

echo "🔨 Building $APP_NAME (release)..."
swift build -c release

echo "📦 Creating .app bundle..."
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# Copy binary
cp ".build/release/$APP_NAME" "$APP_PATH/Contents/MacOS/"

# Copy Info.plist (must live at the bundle root)
cp "Sources/$APP_NAME/Resources/Info.plist" "$APP_PATH/Contents/"

# Copy app icon
cp "Sources/$APP_NAME/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/"

# Ad-hoc signing (required to preserve permission grants)
echo "✍️  Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_PATH"

echo ""
echo "✅ $APP_NAME.app created!"
echo ""
echo "Next steps:"
echo "  1. cp -r $APP_PATH /Applications/"
echo "  2. Launch /Applications/$APP_NAME.app"
echo "  3. System Settings → Privacy & Security → Accessibility → enable PromptShelf"
echo "  4. Restart the app — permission is now permanent"
