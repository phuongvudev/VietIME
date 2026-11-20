#!/bin/bash
# Chạy với quyền quản trị (gọi từ menu "Gỡ cài đặt VietIME…").
#   $1 = thư mục home của người dùng, $2 = "purge" để xoá luôn cài đặt & từ điển
HOME_DIR="$1"
MODE="${2:-keep}"
BUNDLE_ID="com.openmobilekit.inputmethod.VietIME"
OLD_BUNDLE_ID="com.vuphuong.inputmethod.VietIME"   # bản cũ

rm -rf "/Library/Input Methods/VietIME.app" "/Library/Input Methods/._VietIME.app"
[[ -n "$HOME_DIR" ]] && rm -rf "$HOME_DIR/Library/Input Methods/VietIME.app"
pkgutil --forget "$BUNDLE_ID.pkg" >/dev/null 2>&1 || true
pkgutil --forget "$OLD_BUNDLE_ID.pkg" >/dev/null 2>&1 || true

if [[ "$MODE" == "purge" && -n "$HOME_DIR" ]]; then
  rm -rf "$HOME_DIR/Library/Application Support/VietIME"
  rm -f "$HOME_DIR/Library/Preferences/$BUNDLE_ID.plist" "$HOME_DIR/Library/Preferences/$OLD_BUNDLE_ID.plist"
fi
exit 0
