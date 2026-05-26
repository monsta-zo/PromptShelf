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

# 바이너리 복사
cp ".build/release/$APP_NAME" "$APP_PATH/Contents/MacOS/"

# Info.plist 복사 (번들 루트에 위치해야 함)
cp "Sources/$APP_NAME/Resources/Info.plist" "$APP_PATH/Contents/"

# 앱 아이콘 복사
cp "Sources/$APP_NAME/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/"

# Ad-hoc 서명 (권한 등록 후 유지되게 하려면 필수)
echo "✍️  Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_PATH"

echo ""
echo "✅ $APP_NAME.app 생성 완료!"
echo ""
echo "다음 단계:"
echo "  1. cp -r $APP_PATH /Applications/"
echo "  2. /Applications/$APP_NAME.app 실행"
echo "  3. 시스템 설정 → 개인 정보 보호 → 손쉬운 사용 → PromptShelf 체크"
echo "  4. 앱 재시작 → 이제 권한이 영구 유지됩니다"
