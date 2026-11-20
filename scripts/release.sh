#!/bin/bash
# Phát hành VietIME: kiểm tra chứng chỉ → (tăng phiên bản) → test → build + ký + notarize → kiểm tra.
#
#   ./scripts/release.sh               # hỏi từng bước
#   ./scripts/release.sh --skip-tests  # bỏ qua test (không khuyến khích)
#
# Có thể đặt sẵn: APP_SIGN_ID, PKG_SIGN_ID, NOTARY_PROFILE (mặc định "vietime").
set -euo pipefail
cd "$(dirname "$0")/.."

SKIP_TESTS=0
[[ "${1:-}" == "--skip-tests" ]] && SKIP_TESTS=1
PLIST="App/Info.plist"
NOTARY_PROFILE="${NOTARY_PROFILE:-vietime}"

step() { printf '\n\033[1m▶ %s\033[0m\n' "$*"; }
ok()   { printf '  ✅ %s\n' "$*"; }
die()  { printf '  ❌ %s\n' "$*"; exit 1; }

pick_identity() {   # $1 = "Developer ID Application" | "Developer ID Installer"
  local kind="$1" list
  list=$( { security find-identity -v -p codesigning; security find-identity -v -p basic; } 2>/dev/null \
          | sed -n "s/.*\"\($kind: [^\"]*\)\".*/\1/p" | sort -u)
  local n; n=$(printf '%s\n' "$list" | grep -c . || true)
  if [[ $n -eq 0 ]]; then
    return 1
  elif [[ $n -eq 1 ]]; then
    printf '%s\n' "$list"
  else
    echo "  Có nhiều chứng chỉ \"$kind\":" >&2
    local IFS=$'\n' choice
    select choice in $list; do [[ -n "$choice" ]] && { printf '%s\n' "$choice"; break; }; done
  fi
}

# ---------------------------------------------------------------- 1. Chứng chỉ
step "Kiểm tra chứng chỉ Developer ID"
command -v xcodegen >/dev/null || die "Cần XcodeGen: brew install xcodegen"
if [[ -z "${APP_SIGN_ID:-}" ]]; then
  APP_SIGN_ID=$(pick_identity "Developer ID Application") \
    || die "Không thấy chứng chỉ \"Developer ID Application\" trong Keychain. Xem docs/PHAT_HANH.md mục 1.2."
fi
ok "App:   $APP_SIGN_ID"
if [[ -z "${PKG_SIGN_ID:-}" ]]; then
  PKG_SIGN_ID=$(pick_identity "Developer ID Installer") \
    || die "Không thấy chứng chỉ \"Developer ID Installer\" trong Keychain. Xem docs/PHAT_HANH.md mục 1.2."
fi
ok "Gói:   $PKG_SIGN_ID"
TEAM_ID=$(sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p' <<<"$APP_SIGN_ID")

# ---------------------------------------------------------------- 2. Notarize
step "Kiểm tra thông tin notarize (profile \"$NOTARY_PROFILE\")"
if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  ok "Đã có trong Keychain"
else
  echo "  Chưa có — nhập 1 lần, sẽ được lưu vào Keychain."
  echo "  (App-specific password: account.apple.com → Sign-In and Security → App-Specific Passwords)"
  read -r -p "  Apple ID (email): " APPLE_ID
  read -r -p "  Team ID [${TEAM_ID:-?}]: " IN_TEAM; TEAM_ID="${IN_TEAM:-$TEAM_ID}"
  read -r -s -p "  App-specific password: " APP_PW; echo
  xcrun notarytool store-credentials "$NOTARY_PROFILE" \
    --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PW" \
    || die "Không lưu được thông tin notarize — kiểm tra Apple ID / Team ID / mật khẩu."
  unset APP_PW
  ok "Đã lưu"
fi

# ---------------------------------------------------------------- 3. Phiên bản
step "Phiên bản"
VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST")
echo "  Hiện tại: $VER (build $BUILD)"
read -r -p "  Phiên bản mới (Enter = giữ $VER): " NEWVER
if [[ -n "$NEWVER" && "$NEWVER" != "$VER" ]]; then
  /usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $NEWVER" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set CFBundleVersion $((BUILD + 1))" "$PLIST"
  VER="$NEWVER"; BUILD=$((BUILD + 1))
  ok "Đã đổi thành $VER (build $BUILD)"
else
  ok "Giữ $VER (build $BUILD)"
fi

# ---------------------------------------------------------------- 4. Test
if [[ $SKIP_TESTS -eq 0 ]]; then
  step "Chạy test"
  make -s -C VietEngine test | tail -1
  make -s -C VietEngine fuzz | tail -1
  if command -v python3 >/dev/null; then ./tools/run_corpus.sh 2>&1 | grep -E "đúng" ; fi
  ok "Test đạt"
fi

# ---------------------------------------------------------------- 5. Build + ký + notarize
step "Build, ký và notarize (notarize mất vài phút)"
export APP_SIGN_ID PKG_SIGN_ID NOTARY_PROFILE
./scripts/make_installer.sh
PKG="dist/VietIME-$VER.pkg"
[[ -f "$PKG" ]] || die "Không thấy $PKG"

# ---------------------------------------------------------------- 6. Kiểm tra
step "Kiểm tra gói"
pkgutil --check-signature "$PKG" | grep -q "signed by a developer certificate issued by Apple" \
  && ok "Gói đã ký bằng Developer ID" || die "Gói chưa được ký đúng (pkgutil --check-signature)"
spctl -a -vvv -t install "$PKG" 2>&1 | grep -q "Notarized Developer ID" \
  && ok "Gatekeeper chấp nhận: Notarized Developer ID" || die "Gatekeeper chưa chấp nhận (spctl -a -vvv -t install)"
xcrun stapler validate "$PKG" >/dev/null 2>&1 \
  && ok "Đã gắn vé notarize (staple)" || die "Chưa staple được vé notarize"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
pkgutil --expand-full "$PKG" "$TMP/x" >/dev/null
APPX=$(find "$TMP/x" -name VietIME.app -type d | head -1)
codesign --verify --deep --strict "$APPX" && ok "Chữ ký app hợp lệ"
codesign -dvv "$APPX" 2>&1 | grep -q "flags=0x10000(runtime)" && ok "Hardened runtime: bật"

SHA=$(shasum -a 256 "$PKG" | cut -d' ' -f1)
printf '\n\033[1m🎉 Sẵn sàng phát hành\033[0m\n'
echo "  File:    $PKG ($(du -h "$PKG" | cut -f1))"
echo "  Version: $VER (build $BUILD)"
echo "  SHA-256: $SHA"
echo
echo "  Việc còn lại: cài thử trên một máy/tài khoản chưa từng cài VietIME (docs/PHAT_HANH.md mục 2.4),"
echo "  rồi đăng $PKG lên GitHub Releases kèm SHA-256 ở trên."
