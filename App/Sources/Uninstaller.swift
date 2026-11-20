import Cocoa
import Carbon

/// Gỡ VietIME ngay từ menu bộ gõ: hỏi xác nhận → tắt khỏi Input Sources → xoá app (quyền admin) → thoát.
/// Dùng osascript cho hộp thoại vì bộ gõ là tiến trình nền (LSBackgroundOnly), không tự đưa cửa sổ lên được.
enum Uninstaller {
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.openmobilekit.inputmethod.VietIME"

    static func run() {
        DispatchQueue.global(qos: .userInitiated).async {
            let ask = """
            set r to display dialog "Gỡ VietIME khỏi máy?" & return & return & ¬
              "• Gỡ cài đặt: xoá bộ gõ, giữ lại tuỳ chọn và từ điển ngoại lệ." & return & ¬
              "• Gỡ sạch: xoá luôn tuỳ chọn và từ điển ngoại lệ." ¬
              buttons {"Huỷ", "Gỡ sạch", "Gỡ cài đặt"} default button "Gỡ cài đặt" cancel button "Huỷ" ¬
              with title "VietIME" with icon caution
            return button returned of r
            """
            guard let choice = osascript(ask), choice != "Huỷ" else { return }
            let purge = (choice == "Gỡ sạch")

            guard let helper = Bundle.main.path(forResource: "uninstall-helper", ofType: "sh") else {
                _ = osascript(#"display alert "Không tìm thấy uninstall-helper.sh trong bộ cài." as critical"#)
                return
            }
            let remove = """
            do shell script "/bin/bash " & quoted form of \(appleScriptString(helper)) & " " & ¬
              quoted form of \(appleScriptString(NSHomeDirectory())) & " \(purge ? "purge" : "keep")" ¬
              with administrator privileges with prompt "VietIME cần quyền quản trị để gỡ bộ gõ."
            return "ok"
            """
            // Tắt khỏi Input Sources trước, để macOS chuyển sang bộ gõ khác
            DispatchQueue.main.sync { setInputSourceEnabled(false) }
            guard osascript(remove) == "ok" else {
                // Người dùng huỷ nhập mật khẩu → bật lại như cũ
                DispatchQueue.main.sync { setInputSourceEnabled(true) }
                return
            }
            if purge { UserDefaults.standard.removePersistentDomain(forName: bundleID) }
            _ = osascript("""
            display dialog "Đã gỡ VietIME." & return & ¬
              "Nếu biểu tượng còn trên thanh menu, hãy log out rồi log in lại." ¬
              buttons {"OK"} default button "OK" with title "VietIME"
            """)
            DispatchQueue.main.async { exit(0) }
        }
    }

    /// Bundle ID của các bản trước khi đổi tên.
    static let oldBundleID = "com.vuphuong.inputmethod.VietIME"

    static func setInputSourceEnabled(_ enabled: Bool, bundleID: String = Uninstaller.bundleID) {
        let props = [kTISPropertyBundleID as String: bundleID] as CFDictionary
        guard let list = TISCreateInputSourceList(props, true)?.takeRetainedValue() as? [TISInputSource] else { return }
        for src in list {
            _ = enabled ? TISEnableInputSource(src) : TISDisableInputSource(src)
        }
    }

    /// Chạy AppleScript, trả về kết quả (nil nếu lỗi / người dùng bấm Huỷ).
    private static func osascript(_ script: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appleScriptString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
