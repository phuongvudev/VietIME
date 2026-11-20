#!/bin/bash
# Gỡ VietIME khỏi máy.
#   ./scripts/uninstall.sh          gỡ bộ gõ, giữ cài đặt và từ điển ngoại lệ
#   ./scripts/uninstall.sh --purge  gỡ sạch: xoá luôn cài đặt, từ điển, thư mục build
set -uo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="com.openmobilekit.inputmethod.VietIME"
OLD_BUNDLE_ID="com.vuphuong.inputmethod.VietIME"   # bản cũ
APP="$HOME/Library/Input Methods/VietIME.app"
SYSTEM_APP="/Library/Input Methods/VietIME.app"
PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

# 1. Tắt khỏi Input Sources để macOS không chuyển về bộ gõ đã mất
#    Giới hạn 5 giây: bản cũ (chưa có --disable) sẽ chạy như bộ gõ bình thường và không tự thoát.
for A in "$APP" "$SYSTEM_APP"; do
  [[ -x "$A/Contents/MacOS/VietIME" ]] || continue
  "$A/Contents/MacOS/VietIME" --disable 2>/dev/null &
  PID=$!
  ( sleep 5; kill "$PID" 2>/dev/null && echo "(Bản đang cài không hỗ trợ --disable — bỏ qua, vẫn gỡ bình thường.)" ) &
  wait "$PID" 2>/dev/null || true
  break
done

# 2. Dừng tiến trình
killall VietIME 2>/dev/null || true

# 3. Xoá app
if [[ -d "$APP" ]]; then
  rm -rf "$APP"
  echo "Đã xoá $APP"
else
  echo "Không thấy VietIME trong ~/Library/Input Methods (có thể đã gỡ)."
fi

# 3b. Bản cài bằng file .pkg nằm ở /Library (cần mật khẩu)
if [[ -d "$SYSTEM_APP" ]]; then
  echo "Gỡ bản cài bằng .pkg trong /Library/Input Methods (cần mật khẩu)…"
  sudo rm -rf "$SYSTEM_APP" && sudo pkgutil --forget "$BUNDLE_ID.pkg" >/dev/null 2>&1
  sudo pkgutil --forget "$OLD_BUNDLE_ID.pkg" >/dev/null 2>&1 || true
  echo "Đã xoá $SYSTEM_APP"
fi

# 4. Dọn sạch (tuỳ chọn)
if [[ $PURGE -eq 1 ]]; then
  defaults delete "$BUNDLE_ID" 2>/dev/null && echo "Đã xoá cài đặt."
  defaults delete "$OLD_BUNDLE_ID" 2>/dev/null || true
  rm -rf "$HOME/Library/Application Support/VietIME" && echo "Đã xoá từ điển ngoại lệ."
  rm -rf "$HOME/Library/Preferences/$BUNDLE_ID.plist"
  rm -rf build VietIME.xcodeproj && echo "Đã xoá thư mục build."
fi

cat <<'MSG'

✅ Đã gỡ VietIME.
Nếu còn thấy trong danh sách Input Sources: System Settings → Keyboard → Input Sources → Edit…
→ chọn VietIME → bấm "−". Biểu tượng sẽ mất hẳn sau khi log out/log in.
MSG
