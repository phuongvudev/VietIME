#!/bin/bash
# Build và cài VietIME vào ~/Library/Input Methods, đăng ký luôn (không cần log out).
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null; then
  echo "Cần XcodeGen: brew install xcodegen"; exit 1
fi

if [[ -d "/Library/Input Methods/VietIME.app" ]]; then
  echo "⚠️  Máy đang có VietIME cài bằng file .pkg (/Library/Input Methods)."
  echo "   Gỡ bản đó trước (menu Vi → Gỡ cài đặt VietIME…) để tránh hiện 2 VietIME."
  exit 1
fi

xcodegen generate --quiet
rm -rf build/Build/Products/Release/VietIME.app   # tránh cài nhầm bản build cũ nếu build lỗi
xcodebuild -project VietIME.xcodeproj -scheme VietIME -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build -quiet build 2>&1 \
  | grep -v 'IDERunDestination: Supported platforms' || true
[[ -d build/Build/Products/Release/VietIME.app ]] || { echo "❌ Build lỗi"; exit 1; }

APP="build/Build/Products/Release/VietIME.app"
DEST="$HOME/Library/Input Methods"
mkdir -p "$DEST"

# Tắt bản đang chạy (macOS sẽ tự mở lại bản mới khi cần)
killall VietIME 2>/dev/null || true
rm -rf "$DEST/VietIME.app"
ditto --norsrc --noextattr --noqtn "$APP" "$DEST/VietIME.app"
# Project trên ổ ngoài (exFAT…) có thể sinh file "._*" làm hỏng chữ ký → dọn và ký lại
find "$DEST/VietIME.app" -name '._*' -delete
xattr -cr "$DEST/VietIME.app"
codesign --force --deep --sign - "$DEST/VietIME.app" >/dev/null 2>&1

"$DEST/VietIME.app/Contents/MacOS/VietIME" --register

cat <<'MSG'

✅ Đã cài VietIME.
Nếu chưa thấy trong thanh menu: System Settings → Keyboard → Input Sources → Edit… → "+"
→ Vietnamese → VietIME. (Lần đầu đôi khi cần log out/log in.)
MSG
