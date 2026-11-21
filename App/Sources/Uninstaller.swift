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
        for src in inputSources(bundleID: bundleID) {
            _ = enabled ? TISEnableInputSource(src) : TISDisableInputSource(src)
        }
    }

    /// Mọi input source thuộc bundle (kể cả chưa bật).
    static func inputSources(bundleID: String = Uninstaller.bundleID) -> [TISInputSource] {
        let props = [kTISPropertyBundleID as String: bundleID] as CFDictionary
        return TISCreateInputSourceList(props, true)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    private static func boolProperty(_ src: TISInputSource, _ key: CFString) -> Bool {
        guard let raw = TISGetInputSourceProperty(src, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue())
    }

    /// Đăng ký bộ gõ với hệ thống và bật nó trong Input Sources, để dùng được ngay sau khi cài,
    /// không phải log out. Trả false nếu hệ thống vẫn chưa thấy bộ gõ.
    ///
    /// Vì sao cần chờ: ngay sau TISRegisterInputSource, danh sách input source của tiến trình có thể
    /// chưa cập nhật. Nếu tìm ngay, danh sách rỗng → không bật được gì → người dùng phải log out
    /// mới thấy VietIME trong System Settings.
    @discardableResult
    static func register(select: Bool) -> Bool {
        let url = Bundle.main.bundleURL as CFURL
        var status = TISRegisterInputSource(url)
        print("TISRegisterInputSource(\(Bundle.main.bundlePath)): \(status == noErr ? "OK" : "lỗi \(status)")")

        var sources: [TISInputSource] = []
        for attempt in 1...30 {                       // chờ tối đa ~6 giây
            sources = inputSources()
            if !sources.isEmpty { break }
            if attempt == 10 {                        // thử đăng ký lại một lần
                status = TISRegisterInputSource(url)
                print("Đăng ký lại: \(status == noErr ? "OK" : "lỗi \(status)")")
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        }
        guard !sources.isEmpty else {
            print("❌ Hệ thống chưa thấy bộ gõ \(bundleID) — cần log out rồi log in lại.")
            return false
        }

        for src in sources where boolProperty(src, kTISPropertyInputSourceIsEnableCapable) {
            let st = TISEnableInputSource(src)
            print("Bật input source: \(st == noErr ? "OK" : "lỗi \(st)")")
        }
        // Tắt bộ gõ của bản cũ (bundle ID cũ) để không hiện 2 VietIME
        setInputSourceEnabled(false, bundleID: oldBundleID)

        if select, let src = sources.first(where: { boolProperty($0, kTISPropertyInputSourceIsSelectCapable) }) {
            let st = TISSelectInputSource(src)
            print("Chọn VietIME làm bộ gõ hiện tại: \(st == noErr ? "OK" : "lỗi \(st)")")
        }

        let enabled = inputSources().contains { boolProperty($0, kTISPropertyInputSourceIsEnabled) }
        print(enabled ? "✅ VietIME đã có trong Input Sources." : "⚠️ Đã đăng ký nhưng chưa bật được VietIME.")
        return enabled
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
