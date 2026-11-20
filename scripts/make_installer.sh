#!/bin/bash
# Đóng gói VietIME thành file cài đặt .pkg cho người dùng cuối.
#
#   ./scripts/make_installer.sh
#   → dist/VietIME-<version>.pkg
#
# Ký & notarize (bắt buộc khi phát hành cho người dùng — xem docs/PHAT_HANH.md):
#   export APP_SIGN_ID="Developer ID Application: Ten Ban (TEAMID)"
#   export PKG_SIGN_ID="Developer ID Installer: Ten Ban (TEAMID)"
#   export NOTARY_PROFILE="vietime"   # tạo 1 lần: xcrun notarytool store-credentials vietime ...
#   ./scripts/make_installer.sh
set -euo pipefail
cd "$(dirname "$0")/.."
# Không tạo file "._*" (AppleDouble) khi đóng gói — hay gặp khi project nằm trên ổ ngoài.
export COPYFILE_DISABLE=1

command -v xcodegen >/dev/null || { echo "Cần XcodeGen: brew install xcodegen"; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" App/Info.plist)
BUNDLE_ID="com.openmobilekit.inputmethod.VietIME"
PKG_ID="$BUNDLE_ID.pkg"
# Đóng gói trong thư mục tạm trên ổ hệ thống (APFS). Nếu project nằm trên ổ ngoài kiểu exFAT,
# macOS lưu thuộc tính file thành các file "._*"; chúng lọt vào app và làm hỏng chữ ký → bộ gõ không chạy.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/vietime-pkg.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
OUT="dist/VietIME-$VERSION.pkg"

echo "▶ Build VietIME $VERSION (Universal: Apple Silicon + Intel)"
xcodegen generate --quiet
rm -rf build/Build/Products/Release/VietIME.app
xcodebuild -project VietIME.xcodeproj -scheme VietIME -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build \
  ONLY_ACTIVE_ARCH=NO -quiet build 2>&1 | grep -v 'IDERunDestination: Supported platforms' || true
APP="build/Build/Products/Release/VietIME.app"
[[ -d "$APP" ]] || { echo "❌ Build lỗi"; exit 1; }

mkdir -p "$WORK/root" "$WORK/scripts" dist
ditto --norsrc --noextattr --noqtn "$APP" "$WORK/root/VietIME.app"
find "$WORK/root" -name '._*' -delete
xattr -cr "$WORK/root/VietIME.app"
cp installer/scripts/preinstall installer/scripts/postinstall "$WORK/scripts/"
find "$WORK/scripts" -name '._*' -delete
chmod 755 "$WORK/scripts/"*

if [[ -n "${APP_SIGN_ID:-}" ]]; then
  echo "▶ Ký app: $APP_SIGN_ID"
  codesign --force --deep --options runtime --timestamp --sign "$APP_SIGN_ID" "$WORK/root/VietIME.app"
else
  codesign --force --deep --sign - "$WORK/root/VietIME.app"   # ký ad-hoc lại cho chắc
fi
codesign --verify --deep --strict "$WORK/root/VietIME.app" \
  || { echo "❌ Chữ ký app không hợp lệ — không tạo gói"; exit 1; }

echo "▶ Tạo gói"
# Không cho Installer "relocate" sang chỗ khác nếu máy đã có bản build cùng bundle ID
pkgbuild --analyze --root "$WORK/root" "$WORK/component.plist" 2>&1 >/dev/null | sed 's/^/   [pkgbuild --analyze] /' || true
plutil -replace 0.BundleIsRelocatable -bool NO "$WORK/component.plist"
plutil -replace 0.BundleOverwriteAction -string upgrade "$WORK/component.plist"

# --filter: loại mọi file "._*" (AppleDouble) khỏi payload, phòng khi hệ thống tự sinh ra
pkgbuild --root "$WORK/root" \
  --filter '/\._[^/]*$' --filter '/\.DS_Store$' \
  --component-plist "$WORK/component.plist" \
  --install-location "/Library/Input Methods" \
  --scripts "$WORK/scripts" \
  --identifier "$PKG_ID" --version "$VERSION" \
  "$WORK/VietIME-component.pkg" 2>&1 >/dev/null \
  | grep -v '^write: Permission denied$' | sed 's/^/   [pkgbuild] /' || true
# ("write: Permission denied" của pkgbuild trên macOS mới: gói vẫn tạo đúng — đã kiểm tra, nên ẩn đi)
[[ -f "$WORK/VietIME-component.pkg" ]] || { echo "❌ pkgbuild lỗi"; exit 1; }

sed "s/__VERSION__/$VERSION/" installer/distribution.xml > "$WORK/distribution.xml"
mkdir -p "$WORK/resources" && cp installer/resources/*.html "$WORK/resources/"
SIGN_ARGS=()
[[ -n "${PKG_SIGN_ID:-}" ]] && SIGN_ARGS=(--sign "$PKG_SIGN_ID" --timestamp)
productbuild --distribution "$WORK/distribution.xml" \
  --resources "$WORK/resources" --package-path "$WORK" \
  ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} "$WORK/VietIME.pkg" 2>&1 >/dev/null | sed 's/^/   [productbuild] /' || true
[[ -f "$WORK/VietIME.pkg" ]] || { echo "❌ productbuild lỗi"; exit 1; }

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "▶ Notarize (vài phút)"
  xcrun notarytool submit "$WORK/VietIME.pkg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$WORK/VietIME.pkg"
fi

# Ghi chú: "pkgutil --payload-files" sẽ liệt kê các mục "._*". Đó KHÔNG phải file rác mà là
# thuộc tính com.apple.provenance macOS gắn vào mọi file; pkgbuild lưu dạng AppleDouble và
# Installer khôi phục lại thành thuộc tính khi cài (không tạo file ._ trên đĩa).
rm -f "$OUT"
ditto --norsrc --noextattr "$WORK/VietIME.pkg" "$OUT"

echo
echo "✅ $OUT ($(du -h "$OUT" | cut -f1))"
if [[ -z "${PKG_SIGN_ID:-}" ]]; then
  echo "   Gói CHƯA KÝ — chỉ dùng để thử. Máy khác mở sẽ bị chặn: System Settings → Privacy & Security → Open Anyway."
  echo "   Phát hành cho người dùng: ký + notarize, xem docs/PHAT_HANH.md"
fi
