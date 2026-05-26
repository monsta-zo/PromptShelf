#!/bin/bash
# Build → reset Accessibility permission → install → launch
# Grant Accessibility access once when the system dialog appears

set -e
cd "$(dirname "$0")"

echo "🔨 Building..."
swift build 2>&1 | tail -3

echo "📦 Updating /Applications..."
killall PromptShelf 2>/dev/null || true
sleep 0.3

sudo cp .build/debug/PromptShelf /Applications/PromptShelf.app/Contents/MacOS/
codesign --force --sign - /Applications/PromptShelf.app

echo "🔐 Resetting Accessibility permission..."
sudo tccutil reset Accessibility com.promptshelf.app 2>/dev/null || true

echo "🚀 Launching..."
open /Applications/PromptShelf.app

echo ""
echo "⚠️  If an Accessibility permission dialog appears, allow it then restart the app:"
echo "   killall PromptShelf && open /Applications/PromptShelf.app"
