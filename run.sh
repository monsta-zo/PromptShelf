#!/bin/bash
# 빌드 → 권한 초기화 → 설치 → 실행
# 처음 한 번만 손쉬운 사용 허용하면 됨

set -e
cd "$(dirname "$0")"

echo "🔨 빌드 중..."
swift build 2>&1 | tail -3

echo "📦 /Applications 업데이트..."
killall PromptShelf 2>/dev/null || true
sleep 0.3

sudo cp .build/debug/PromptShelf /Applications/PromptShelf.app/Contents/MacOS/
codesign --force --sign - /Applications/PromptShelf.app

echo "🔐 Accessibility 권한 초기화..."
sudo tccutil reset Accessibility com.promptshelf.app 2>/dev/null || true

echo "🚀 실행 중..."
open /Applications/PromptShelf.app

echo ""
echo "⚠️  손쉬운 사용 권한 요청이 뜨면 허용 후, 앱을 한 번 재시작하세요:"
echo "   killall PromptShelf && open /Applications/PromptShelf.app"
