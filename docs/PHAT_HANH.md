# Phát hành VietIME cho người dùng

Mục tiêu: người dùng bấm đúp file `.pkg` là cài được, macOS **không** hiện cảnh báo. Muốn vậy, gói phải được **ký bằng Developer ID** và **notarize** (gửi Apple kiểm tra tự động).

## 1. Chuẩn bị (làm 1 lần)

### 1.1. Đăng ký Apple Developer Program

Đăng ký tại [developer.apple.com/programs](https://developer.apple.com/programs/), phí khoảng 99 USD/năm. Có hai loại tài khoản:

| Loại | Tên hiện khi người dùng cài | Cần thêm |
|---|---|---|
| **Individual** (cá nhân) | Tên bạn, ví dụ "Vu Phuong" | Không |
| **Organization** (tổ chức) | Tên tổ chức, ví dụ "OpenMobileKit" | Tư cách pháp nhân và số D-U-N-S |

Bundle ID của app là `com.openmobilekit…`. Nếu muốn người dùng thấy tên "OpenMobileKit" thì đăng ký loại Organization.

### 1.2. Tạo 2 chứng chỉ Developer ID

Chỉ tài khoản có vai trò **Account Holder** mới tạo được hai chứng chỉ này.

1. Mở Xcode → **Settings → Accounts** → đăng nhập Apple ID → chọn team → **Manage Certificates…**
2. Bấm **+** → **Developer ID Application** (để ký app).
3. Bấm **+** → **Developer ID Installer** (để ký gói .pkg).

Kiểm tra lại bằng lệnh:

```bash
security find-identity -v | grep "Developer ID"
#  1) ABC123… "Developer ID Application: Ten Ban (TEAMID)"
#  2) DEF456… "Developer ID Installer: Ten Ban (TEAMID)"
```

> Sao lưu hai chứng chỉ, gồm cả private key, bằng Keychain Access → chuột phải → Export (.p12). Mất private key thì phải thu hồi chứng chỉ và tạo lại.

### 1.3. Lưu thông tin notarize vào Keychain

1. Tạo **app-specific password** tại [account.apple.com](https://account.apple.com) → Sign-In and Security → App-Specific Passwords.
2. Lưu vào Keychain dưới tên `vietime`:

```bash
xcrun notarytool store-credentials vietime \
  --apple-id "email-apple-id@example.com" \
  --team-id "TEAMID" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

## 2. Mỗi lần phát hành

**Cách nhanh:** chỉ cần chạy một lệnh, script làm hết các bước 2.1 → 2.4 và hỏi những gì còn thiếu:

```bash
./scripts/release.sh
```

Các bước chi tiết bên dưới là những gì script làm, phòng khi bạn muốn tự làm tay.

### 2.1. Tăng phiên bản

Trong `App/Info.plist`:
- tăng `CFBundleShortVersionString` (ví dụ `0.3.1` → `0.4.0`), và
- tăng `CFBundleVersion` thêm 1.

Installer dựa vào `CFBundleVersion` để biết gói nào mới hơn.

### 2.2. Chạy test

```bash
cd VietEngine && make test && make fuzz && cd ..
./tools/run_corpus.sh
```

### 2.3. Build, ký, notarize

```bash
export APP_SIGN_ID="Developer ID Application: Ten Ban (TEAMID)"
export PKG_SIGN_ID="Developer ID Installer: Ten Ban (TEAMID)"
export NOTARY_PROFILE="vietime"
./scripts/make_installer.sh
```

Script làm lần lượt:
1. Build bản Universal.
2. Ký app với hardened runtime và timestamp.
3. Ký gói `.pkg`.
4. Gửi Apple notarize, thường mất vài phút.
5. Gắn vé notarize vào gói (staple), để máy người dùng không có mạng vẫn mở được.

Nếu notarize bị từ chối, xem lý do bằng lệnh:

```bash
xcrun notarytool history --keychain-profile vietime
xcrun notarytool log <submission-id> --keychain-profile vietime
```

### 2.4. Kiểm tra trước khi phát hành

```bash
PKG=dist/VietIME-<version>.pkg
pkgutil --check-signature "$PKG"        # Status: signed by a developer certificate issued by Apple
spctl -a -vvv -t install "$PKG"         # accepted — source=Notarized Developer ID
xcrun stapler validate "$PKG"           # The validate action worked!
```

Sau đó **cài thử trên một máy sạch**, tức là máy chưa từng cài VietIME. Có thể dùng máy ảo macOS hoặc một tài khoản user mới:
- Bấm đúp file `.pkg`, macOS **không** được hiện cảnh báo.
- Cài xong, chọn VietIME và gõ được ngay, không phải log out.
- Gõ thử: `tieengs Vieetj`, gõ code trong VS Code, Ctrl+Shift, sửa dấu tại chỗ.
- Thử **Gỡ cài đặt VietIME…** từ menu bộ gõ.

### 2.5. Đăng tải

Gợi ý: đăng lên **GitHub Releases**, kèm các thông tin sau:
- File `VietIME-<version>.pkg`.
- Ghi chú phiên bản: có gì mới, lỗi đã sửa, yêu cầu macOS 12 trở lên.
- Mã SHA-256 của file, lấy bằng lệnh `shasum -a 256 dist/VietIME-<version>.pkg`.

## 3. Lưu ý

- **Không đổi bundle ID nữa.** Mỗi lần đổi, macOS coi đó là bộ gõ mới, và người dùng phải xoá bộ gõ cũ rồi log out.
- **Không chạy `make_installer.sh` có ký trên máy lạ.** Private key của chứng chỉ chỉ nên nằm trên máy của bạn.
- **Build chưa ký** (lúc dev, hoặc gửi bản thử): trên macOS 15 trở lên, người dùng **không** mở được bằng chuột phải → Open nữa. Họ phải bấm đúp file, chọn **Done**, rồi vào **System Settings → Privacy & Security**, kéo xuống cuối và bấm **Open Anyway**.
- **Chứng chỉ hết hạn** (Developer ID có hạn 5 năm): các gói đã ký và notarize trước đó vẫn cài được nhờ timestamp. Chỉ cần tạo chứng chỉ mới cho các lần phát hành sau.
