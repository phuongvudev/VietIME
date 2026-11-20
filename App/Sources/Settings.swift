import Foundation
import VietEngine

/// Chế độ gõ theo từng app.
enum AppMode: String, CaseIterable {
    /// Gõ tiếng Việt bình thường (tự khôi phục từ không hợp lệ).
    case vietnamese
    /// Gõ tiếng Việt + giữ nguyên từ khoá / từ tiếng Anh trong từ điển ngoại lệ.
    case code
    /// Tắt bộ gõ.
    case english

    var title: String {
        switch self {
        case .vietnamese: return "Tiếng Việt"
        case .code: return "Tiếng Việt cho code (giữ từ khoá ngoài comment/chuỗi)"
        case .english: return "Tắt (English)"
        }
    }
}

/// Cách đưa chữ vào app.
enum InsertStyle: String {
    /// Thay chữ trực tiếp bằng insertText(_:replacementRange:) — không gạch chân, giữ suggestion.
    case direct
    /// Dùng marked text (có gạch chân) — cho app không hỗ trợ replacementRange (Terminal...).
    case marked
}

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private enum Key {
        static let method = "method"
        static let modernTone = "modernTone"
        static let autoRestore = "autoRestore"
        static let freeMarking = "freeMarking"
        static let wStandalone = "wStandalone"
        static let toggleHotkey = "toggleHotkey"
        static let vietnameseInStrings = "vietnameseInStrings"
        static let smartContext = "smartContext"
        static let editExistingWords = "editExistingWords"
        static let debugLog = "debugLog"
        static let appModes = "appModes"
        static let appInsertStyles = "appInsertStyles"
    }

    /// App lập trình: mặc định chế độ code.
    private let codeApps: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.exafunction.windsurf",
        "com.apple.dt.Xcode",
        "dev.zed.Zed",
        "dev.zed.Zed-Preview",
        "com.sublimetext.4",
        "com.panic.Nova",
        "com.google.android.studio",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "com.mitchellh.ghostty",
        "io.alacritty",
    ]
    private let codeAppPrefixes = ["com.jetbrains."]

    /// App không hỗ trợ thay chữ trực tiếp → dùng marked text.
    private let markedApps: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "com.mitchellh.ghostty",
        "io.alacritty",
    ]

    private init() {
        Self.migrateFromOldBundleID(into: d)
        d.register(defaults: [
            Key.method: InputMethod.telex.rawValue,
            Key.modernTone: true,
            Key.autoRestore: true,
            Key.freeMarking: false,
            Key.wStandalone: true,
            Key.toggleHotkey: true,
            Key.vietnameseInStrings: true,
            Key.smartContext: true,
            Key.editExistingWords: true,
        ])
    }

    /// Bản cũ dùng bundle ID "com.vuphuong.inputmethod.VietIME": chép tuỳ chọn sang domain mới một lần.
    private static func migrateFromOldBundleID(into d: UserDefaults) {
        let oldDomain = "com.vuphuong.inputmethod.VietIME"
        guard !d.bool(forKey: "migratedFromOldBundleID") else { return }
        if let old = UserDefaults.standard.persistentDomain(forName: oldDomain) {
            for (k, v) in old where d.object(forKey: k) == nil { d.set(v, forKey: k) }
        }
        d.set(true, forKey: "migratedFromOldBundleID")
    }

    var method: InputMethod {
        get { InputMethod(rawValue: d.integer(forKey: Key.method)) ?? .telex }
        set { d.set(newValue.rawValue, forKey: Key.method) }
    }
    var modernTone: Bool {
        get { d.bool(forKey: Key.modernTone) }
        set { d.set(newValue, forKey: Key.modernTone) }
    }
    var autoRestore: Bool {
        get { d.bool(forKey: Key.autoRestore) }
        set { d.set(newValue, forKey: Key.autoRestore) }
    }
    var freeMarking: Bool {
        get { d.bool(forKey: Key.freeMarking) }
        set { d.set(newValue, forKey: Key.freeMarking) }
    }
    var wStandalone: Bool {
        get { d.bool(forKey: Key.wStandalone) }
        set { d.set(newValue, forKey: Key.wStandalone) }
    }
    /// Ctrl+Shift (nhấn rồi thả) để bật/tắt tiếng Việt cho app hiện tại.
    var toggleHotkey: Bool {
        get { d.bool(forKey: Key.toggleHotkey) }
        set { d.set(newValue, forKey: Key.toggleHotkey) }
    }

    /// Chế độ code: tự nhận comment / chuỗi để gõ tiếng Việt bình thường ở đó.
    var smartContext: Bool {
        get { d.bool(forKey: Key.smartContext) }
        set { d.set(newValue, forKey: Key.smartContext) }
    }
    /// Trong chuỗi "..." cũng gõ tiếng Việt bình thường (tắt nếu hay gõ class Tailwind, key...).
    var vietnameseInStrings: Bool {
        get { d.bool(forKey: Key.vietnameseInStrings) }
        set { d.set(newValue, forKey: Key.vietnameseInStrings) }
    }

    /// Đặt con trỏ sau / giữa một từ đã gõ rồi gõ phím dấu → sửa dấu tại chỗ.
    var editExistingWords: Bool {
        get { d.bool(forKey: Key.editExistingWords) }
        set { d.set(newValue, forKey: Key.editExistingWords) }
    }

    /// Ghi log từng phím (để chẩn đoán lỗi với một app cụ thể).
    var debugLog: Bool {
        get { d.bool(forKey: Key.debugLog) }
        set { d.set(newValue, forKey: Key.debugLog) }
    }

    // MARK: Theo từng app

    func isCodeApp(_ bundleID: String) -> Bool {
        codeApps.contains(bundleID) || codeAppPrefixes.contains { bundleID.hasPrefix($0) }
    }

    func mode(for bundleID: String) -> AppMode {
        let map = d.dictionary(forKey: Key.appModes) as? [String: String] ?? [:]
        if let raw = map[bundleID], let m = AppMode(rawValue: raw) { return m }
        return isCodeApp(bundleID) ? .code : .vietnamese
    }

    func setMode(_ mode: AppMode, for bundleID: String) {
        var map = d.dictionary(forKey: Key.appModes) as? [String: String] ?? [:]
        map[bundleID] = mode.rawValue
        d.set(map, forKey: Key.appModes)
    }

    func insertStyle(for bundleID: String) -> InsertStyle {
        let map = d.dictionary(forKey: Key.appInsertStyles) as? [String: String] ?? [:]
        if let raw = map[bundleID], let s = InsertStyle(rawValue: raw) { return s }
        return markedApps.contains(bundleID) ? .marked : .direct
    }

    func setInsertStyle(_ style: InsertStyle, for bundleID: String) {
        var map = d.dictionary(forKey: Key.appInsertStyles) as? [String: String] ?? [:]
        map[bundleID] = style.rawValue
        d.set(map, forKey: Key.appInsertStyles)
    }

    // MARK: Từ điển ngoại lệ của người dùng (file text, mỗi dòng một từ)
    //  "+từ"  hoặc "từ"  → thêm vào ngoại lệ (giữ nguyên tiếng Anh)
    //  "-từ"             → bỏ khỏi danh sách có sẵn (để gõ được tiếng Việt)

    var wordsFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VietIME", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("words.txt")
    }

    func ensureWordsFile() {
        let url = wordsFileURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let template = """
        # Từ điển ngoại lệ của VietIME — mỗi dòng một từ (chỉ chữ cái/số ASCII).
        # Chỉ áp dụng cho app ở "chế độ code".
        #   tên_từ   → giữ nguyên, không bỏ dấu   (vd: kotlin, mesh)
        #   -tên_từ  → bỏ khỏi danh sách có sẵn  (vd: -max nếu bạn hay gõ "mã" trong comment)
        # Lưu file xong, đổi sang app khác rồi quay lại là có hiệu lực.

        """
        try? template.write(to: url, atomically: true, encoding: .utf8)
    }

    private var cachedWords: (date: Date, add: [String], remove: [String])?

    /// (thêm, bỏ) — đọc lại khi file thay đổi.
    func userWords() -> (add: [String], remove: [String]) {
        let url = wordsFileURL
        let date = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
        if let c = cachedWords, c.date == date { return (c.add, c.remove) }
        var add: [String] = [], remove: [String] = []
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("#") { continue }
                if t.hasPrefix("-") { remove.append(String(t.dropFirst())) }
                else if t.hasPrefix("+") { add.append(String(t.dropFirst())) }
                else { add.append(t) }
            }
        }
        cachedWords = (date, add, remove)
        return (add, remove)
    }
}
