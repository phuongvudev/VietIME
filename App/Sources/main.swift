import Cocoa
import Carbon
import InputMethodKit

// `VietIME --register [--select]`: đăng ký & bật bộ gõ ngay, không cần log out.
// Gọi bởi postinstall của bộ cài .pkg và scripts/install.sh, chạy với quyền của người dùng.
if CommandLine.arguments.contains("--register") {
    let ok = Uninstaller.register(select: CommandLine.arguments.contains("--select"))
    exit(ok ? 0 : 1)
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
