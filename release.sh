#!/bin/bash
# PromptShelf Release Script
# Developer ID 서명 + Notarization + DMG 패키징
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ── 설정 ────────────────────────────────────────────────────────────────────
APP_NAME="PromptShelf"
BUNDLE_ID="com.promptshelf.app"
SIGNING_IDENTITY="Developer ID Application: TOGG (U2QA72Q6BP)"
TEAM_ID="U2QA72Q6BP"
ENTITLEMENTS="$SCRIPT_DIR/PromptShelf.entitlements"

APP_PATH="$SCRIPT_DIR/$APP_NAME.app"
RELEASE_DIR="$SCRIPT_DIR/release"
ZIP_PATH="$RELEASE_DIR/$APP_NAME.zip"
DMG_PATH="$RELEASE_DIR/$APP_NAME.dmg"

# ── Notarization 자격증명 (환경변수 또는 직접 입력) ─────────────────────────
# 환경변수로 미리 설정하거나 여기에 직접 입력:
#   export APPLE_ID="your@email.com"
#   export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"  ← appleid.apple.com에서 생성
APPLE_ID="${APPLE_ID:-}"
APPLE_APP_PASSWORD="${APPLE_APP_PASSWORD:-}"

if [ -z "$APPLE_ID" ] || [ -z "$APPLE_APP_PASSWORD" ]; then
    echo "❌ Apple ID 정보가 필요해요."
    echo ""
    echo "실행 전에 환경변수를 설정하세요:"
    echo "  export APPLE_ID=\"your@email.com\""
    echo "  export APPLE_APP_PASSWORD=\"xxxx-xxxx-xxxx-xxxx\""
    echo ""
    echo "앱 전용 비밀번호 생성: https://appleid.apple.com → 보안 → 앱 전용 암호"
    exit 1
fi

mkdir -p "$RELEASE_DIR"

# ── 1. 빌드 ─────────────────────────────────────────────────────────────────
echo "🔨 [1/6] Release 빌드 중..."
swift build -c release

# ── 2. .app 번들 생성 ────────────────────────────────────────────────────────
echo "📦 [2/6] .app 번들 생성 중..."
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

cp ".build/release/$APP_NAME"              "$APP_PATH/Contents/MacOS/"
cp "Sources/$APP_NAME/Resources/Info.plist" "$APP_PATH/Contents/"

# 앱 아이콘 복사
cp "Sources/$APP_NAME/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/"

# Sounds 리소스 복사 (번들에 포함된 리소스)
if [ -d ".build/release/$APP_NAME.bundle" ]; then
    cp -r ".build/release/$APP_NAME.bundle" "$APP_PATH/Contents/Resources/"
fi

# ── 3. Developer ID 서명 (Hardened Runtime 필수) ────────────────────────────
echo "✍️  [3/6] Developer ID 서명 중..."
codesign \
    --force \
    --deep \
    --options=runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY" \
    --timestamp \
    "$APP_PATH"

echo "🔍 서명 검증..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type exec --verbose "$APP_PATH" 2>&1 || true

# ── 4. ZIP 압축 (notarytool 제출용) ─────────────────────────────────────────
echo "🗜️  [4/6] ZIP 압축 중..."
cd "$RELEASE_DIR"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
cd "$SCRIPT_DIR"

# ── 5. Notarization 제출 ─────────────────────────────────────────────────────
echo "🍎 [5/6] Apple Notarization 제출 중... (보통 1~3분 소요)"
xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait

# ── 6. Staple (Notarization 티켓을 앱에 첨부) ───────────────────────────────
echo "📎 [6/6] Notarization 티켓 Staple 중..."
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

# ── DMG 생성 (create-dmg 설치된 경우) ───────────────────────────────────────
if command -v create-dmg &>/dev/null; then
    echo "💿 DMG 패키징 중..."
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

    # DMG도 서명
    codesign --sign "$SIGNING_IDENTITY" "$DMG_PATH"
    echo "✅ DMG 생성 완료: $DMG_PATH"
else
    echo "ℹ️  create-dmg 없음 → ZIP만 생성됨"
    echo "   설치: brew install create-dmg"
fi

echo ""
echo "🎉 릴리즈 완료!"
echo "   앱:  $APP_PATH"
echo "   ZIP: $ZIP_PATH"
[ -f "$DMG_PATH" ] && echo "   DMG: $DMG_PATH"
echo ""
echo "GitHub Release에 ZIP 또는 DMG를 업로드하세요."
