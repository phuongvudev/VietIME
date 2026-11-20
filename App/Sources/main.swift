import Cocoa
import Carbon
import InputMethodKit

// `VietIME --register`: đăng ký & bật bộ gõ ngay, không cần log out (scripts/install.sh gọi).
if CommandLine.arguments.contains("--register") {
    let status = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
    print(status == noErr ? "Đã đăng ký bộ gõ." : "TISRegisterInputSource lỗi \(status)")
    Uninstaller.setInputSourceEnabled(true)
    // Tắt bộ gõ của bản cũ (bundle ID cũ) để không hiện 2 VietIME
    Uninstaller.setInputSourceEnabled(false, bundleID: Uninstaller.oldBundleID)
    print("Đã bật bộ gõ trong Input Sources.")
    exit(0)
}

// `VietIME --disable`: tắt bộ gõ khỏi Input Sources (scripts/uninstall.sh gọi trước khi xoá).
if CommandLine.arguments.contains("--disable") {
    Uninstaller.setInputSourceEnabled(false)
    print("Đã tắt bộ gõ trong Input Sources.")
    exit(0)
}

guard let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String else {
    fatalError("Info.plist thiếu InputMethodConnectionName")
}

// Giữ tham chiếu để server sống suốt vòng đời app.
let server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
_ = server

NSApplication.shared.run()
