import Cocoa
import InputMethodKit
import os
import VietEngine

/// Log chẩn đoán: bật trong menu bộ gõ → xem bằng
///   log stream --predicate 'subsystem == "com.openmobilekit.inputmethod.VietIME"' --level debug
let imeLog = Logger(subsystem: "com.openmobilekit.inputmethod.VietIME", category: "keys")

/// Bộ điều khiển IMK. macOS tạo một instance cho mỗi ô nhập (client).
///
/// Hai cách đưa chữ vào app:
///  - direct (mặc định): phím thường để app tự chèn (passthrough), chỉ khi cần bỏ dấu mới gọi
///    insertText(_:replacementRange:) để thay đúng mấy ký tự vừa đổi. Không gạch chân, editor
///    thấy từng ký tự ngay → popup suggestion, auto-close ngoặc... hoạt động bình thường.
///  - marked: chữ đang gõ là marked text (gạch chân), chốt khi hết từ. Dùng cho Terminal & app
///    không hỗ trợ replacementRange.
@objc(InputController)
final class InputController: IMKInputController {
    private var engine = VietEngine()
    private var engineWordsStamp = ""

    private var bundleID = ""
    private var mode: AppMode = .vietnamese
    private var style: InsertStyle = .direct

    /// Vị trí con trỏ mong đợi sau thao tác gần nhất (direct mode) — để phát hiện người dùng
    /// click chuột / đổi dòng / editor tự chèn chữ, khi đó phải bắt đầu từ mới.
    private var expectedLocation: Int?

    /// Từ đang soạn ở marked mode.
    private var composing = false

    // Phím tắt Ctrl+Shift (nhấn rồi thả)
    private var hotkeyArmed = false

    private enum KeyCode {
        static let backspace: UInt16 = 51
        static let forwardDelete: UInt16 = 117
        static let returnKey: UInt16 = 36
        static let enter: UInt16 = 76
        static let tab: UInt16 = 48
        static let escape: UInt16 = 53
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
        static let home: UInt16 = 115
        static let end: UInt16 = 119
        static let pageUp: UInt16 = 116
        static let pageDown: UInt16 = 121
    }

    // MARK: Vòng đời

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        let client = sender as? IMKTextInput
        bundleID = client?.bundleIdentifier() ?? ""
        reloadSettings()
        resetWord()
    }

    override func deactivateServer(_ sender: Any!) {
        commitIfComposing(sender as? IMKTextInput)
        resetWord()
        super.deactivateServer(sender)
    }

    override func commitComposition(_ sender: Any!) {
        commitIfComposing(sender as? IMKTextInput)
        resetWord()
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    private func reloadSettings() {
        let s = Settings.shared
        s.ensureWordsFile()
        let words = s.userWords()
        let stamp = words.add.joined(separator: ",") + "|" + words.remove.joined(separator: ",")
        if stamp != engineWordsStamp {
            engine = VietEngine()
            words.add.forEach { engine.addWord($0) }
            words.remove.forEach { engine.removeWord($0) }
            engineWordsStamp = stamp
        }
        engine.method = s.method
        engine.modernTone = s.modernTone
        engine.autoRestore = s.autoRestore
        engine.freeMarking = s.freeMarking
        engine.wStandalone = s.wStandalone
        mode = s.mode(for: bundleID)
        style = s.insertStyle(for: bundleID)
        engine.englishCheck = (mode == .code)
    }

    private func resetWord() {
        engine.reset()
        expectedLocation = nil
        composing = false
    }

    // MARK: Xử lý phím

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event, let client = sender as? IMKTextInput else { return false }

        if event.type == .flagsChanged {
            handleFlagsChanged(event, client: client)
            return false
        }
        guard event.type == .keyDown else { return false }
        hotkeyArmed = false

        if mode == .english { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !flags.intersection([.command, .control, .option]).isEmpty {
            // Phím tắt (⌘S, ⌃Space, ⌥...) → kết thúc từ, để app xử lý.
            commitIfComposing(client)
            resetWord()
            return false
        }

        switch event.keyCode {
        case KeyCode.backspace:
            return handleBackspace(client)
        case KeyCode.returnKey, KeyCode.enter, KeyCode.tab, KeyCode.escape,
             KeyCode.left, KeyCode.right, KeyCode.up, KeyCode.down,
             KeyCode.home, KeyCode.end, KeyCode.pageUp, KeyCode.pageDown, KeyCode.forwardDelete:
            // Không nuốt các phím này: Tab/Enter để chọn suggestion, mũi tên để di chuyển.
            commitIfComposing(client)
            resetWord()
            return false
        default:
            break
        }

        guard let chars = event.characters, chars.unicodeScalars.count == 1,
              let scalar = chars.unicodeScalars.first else {
            commitIfComposing(client)
            resetWord()
            return false
        }

        return style == .marked
            ? handleMarked(scalar, client: client)
            : handleDirect(scalar, client: client)
    }

    // MARK: Direct mode (không gạch chân)

    private func handleDirect(_ scalar: Unicode.Scalar, client: IMKTextInput) -> Bool {
        let sel = client.selectedRange()
        if sel.location == NSNotFound {
            // App không cho biết vị trí con trỏ → không thay chữ được, chuyển sang marked cho phiên này.
            style = .marked
            return handleMarked(scalar, client: client)
        }

        if !engine.currentWord.isEmpty && !wordStillBeforeCursor(client, sel: sel) {
            engine.reset()
        }
        if sel.length > 0 {
            // Đang bôi đen: chữ gõ vào sẽ thay vùng chọn → bắt đầu từ mới.
            engine.reset()
        }
        if engine.currentWord.isEmpty {
            applyContext(client, location: sel.location)
            if sel.length == 0, Settings.shared.editExistingWords,
               let handled = editExistingWord(scalar, client: client, location: sel.location) {
                return handled
            }
        }

        let wordBefore = engine.currentWord
        let edit = engine.process(scalar)
        debug("key '\(Character(scalar))' sel=\(sel.location) word '\(wordBefore)' → '\(engine.currentWord)' "
              + "pass=\(edit.passthrough) bs=\(edit.backspaces) ins='\(edit.insert)'")
        if edit.passthrough {
            expectedLocation = sel.location + 1
            return false
        }
        if edit.backspaces == 0 && edit.insert.isEmpty && sel.length == 0 {
            // Phím chỉ huỷ dấu mà chữ không đổi (vd "tẽ" → "tex", gõ thêm x lần nữa).
            // Không được chỉ "nuốt" phím: app Chromium/Electron (Chrome, VS Code, Slack...) thấy bộ gõ
            // không chèn gì sẽ tự chèn phím đó vào sau → "texxt". Nên thay ký tự cuối bằng chính nó.
            let word = engine.currentWord.utf16
            if let last = word.last, sel.location >= 1 {
                let ch = String(utf16CodeUnits: [last], count: 1)
                client.insertText(ch, replacementRange: NSRange(location: sel.location - 1, length: 1))
            }
            expectedLocation = sel.location
            return true
        }

        let start = sel.location - edit.backspaces
        guard start >= 0 else {
            engine.reset()
            expectedLocation = nil
            return false
        }
        let range = NSRange(location: start, length: edit.backspaces + sel.length)
        client.insertText(edit.insert, replacementRange: range)
        expectedLocation = start + edit.insert.utf16.count
        return true
    }

    // MARK: Sửa dấu từ đã gõ

    /// Con trỏ đặt sau / giữa một từ có sẵn (vd click vào sau "việt") rồi gõ phím:
    ///  - Con trỏ ở cuối từ: nạp từ vào engine, phím được xử lý như đang gõ tiếp → "việt" + s = "viết".
    ///  - Con trỏ giữa từ: chỉ nhận phím dấu; thay đúng mấy ký tự đổi, con trỏ giữ nguyên chỗ
    ///    khi phần đổi nằm trước con trỏ ("việ|t" + s → "viế|t").
    /// Trả nil để xử lý phím như bình thường.
    private func editExistingWord(_ scalar: Unicode.Scalar, client: IMKTextInput, location: Int) -> Bool? {
        let maxLen = 16
        guard location > 0 else { return nil }
        let beforeLen = min(location, maxLen + 1)
        guard let beforeText = client.attributedSubstring(
            from: NSRange(location: location - beforeLen, length: beforeLen))?.string,
            !beforeText.isEmpty else { return nil }

        let before = Array(beforeText.unicodeScalars)
        var i = before.count
        while i > 0 && VietEngine.isWordChar(before[i - 1]) { i -= 1 }
        let prefix = before[i...]
        // Không có từ ngay trước con trỏ, hoặc từ dài quá (có thể chưa lấy hết) → bỏ qua
        guard !prefix.isEmpty, prefix.count <= maxLen, i > 0 || beforeLen == location else { return nil }
        let prefixStr = String(String.UnicodeScalarView(prefix))

        let suffixStr = wordAfterCursor(client, location: location, maxLen: maxLen)

        if suffixStr.isEmpty {
            // Con trỏ ở cuối từ: tiếp tục từ đó.
            engine.loadWord(prefixStr)
            expectedLocation = location
            return nil
        }

        // Con trỏ giữa từ: chỉ xử lý phím dấu.
        guard engine.isMarkKey(scalar) else { return nil }
        let old = prefixStr + suffixStr
        guard engine.loadWord(old) else {
            engine.reset()
            return nil
        }
        let edit = engine.process(scalar)
        let new = engine.currentWord
        engine.reset()
        expectedLocation = nil
        if edit.passthrough || new == old + String(scalar) { return false }

        // Thay phần khác nhau nhỏ nhất (đơn vị UTF-16 cho NSRange)
        let o = Array(old.utf16), n = Array(new.utf16)
        var p = 0
        while p < o.count && p < n.count && o[p] == n[p] { p += 1 }
        var s = 0
        while s < o.count - p && s < n.count - p && o[o.count - 1 - s] == n[n.count - 1 - s] { s += 1 }
        let wordStart = location - prefixStr.utf16.count
        let range = NSRange(location: wordStart + p, length: o.count - s - p)
        let insert = String(utf16CodeUnits: Array(n[p..<(n.count - s)]), count: n.count - s - p)
        client.insertText(insert, replacementRange: range)
        return true
    }

    private func wordAfterCursor(_ client: IMKTextInput, location: Int, maxLen: Int) -> String {
        // Một số app trả nil khi range vượt quá cuối văn bản → thử độ dài ngắn dần
        for len in [maxLen, 4, 1] {
            if let t = client.attributedSubstring(from: NSRange(location: location, length: len))?.string,
               !t.isEmpty {
                var out = String.UnicodeScalarView()
                for u in t.unicodeScalars {
                    if VietEngine.isWordChar(u) { out.append(u) } else { break }
                }
                return String(out)
            }
        }
        return ""
    }

    /// Đầu mỗi từ: chọn có dùng từ điển ngoại lệ hay không.
    ///  - App ở chế độ Tiếng Việt: không dùng.
    ///  - App ở chế độ code: dùng khi đang ở code; tắt trong comment (và chuỗi nếu bật tuỳ chọn),
    ///    để gõ "mã", "tét"... bình thường. App không trả được text → coi như đang ở code.
    private func applyContext(_ client: IMKTextInput, location: Int) {
        guard mode == .code else {
            engine.englishCheck = false
            return
        }
        let s = Settings.shared
        guard s.smartContext, location != NSNotFound, location > 0 else {
            engine.englishCheck = true
            return
        }
        let len = min(location, 4000)
        guard let text = client.attributedSubstring(from: NSRange(location: location - len, length: len))?.string,
              !text.isEmpty else {
            engine.englishCheck = true
            return
        }
        switch VietEngine.detectContext(text) {
        case .code: engine.englishCheck = true
        case .comment: engine.englishCheck = false
        case .string: engine.englishCheck = !s.vietnameseInStrings
        }
    }

    /// Kiểm tra chữ ngay trước con trỏ vẫn là từ engine đang giữ.
    private func wordStillBeforeCursor(_ client: IMKTextInput, sel: NSRange) -> Bool {
        let word = engine.currentWord
        let len = word.utf16.count
        let positionOK = expectedLocation == nil || expectedLocation == sel.location

        guard sel.location >= len else {
            debug("reset: sel=\(sel.location) < len(\(word))")
            return false
        }
        let text = client.attributedSubstring(from: NSRange(location: sel.location - len, length: len))?.string
        if let text = text, !text.isEmpty, text == word { return true }
        // Text không khớp / app không trả text: vẫn giữ từ nếu con trỏ đúng chỗ mình đã đặt
        // (một số app Electron/Chromium trả text không chính xác).
        let positionMatches = expectedLocation != nil && expectedLocation == sel.location
        if !positionMatches {
            debug("reset: text '\(text ?? "nil")' ≠ '\(word)', sel=\(sel.location) expected=\(String(describing: expectedLocation)) app=\(bundleID)")
        }
        return positionMatches || (text == nil && positionOK)
    }

    private func debug(_ message: @autoclosure () -> String) {
        guard Settings.shared.debugLog else { return }
        let m = message()
        imeLog.debug("\(m, privacy: .public)")
    }

    private func handleBackspace(_ client: IMKTextInput) -> Bool {
        if style == .marked && composing {
            engine.backspace()
            let word = engine.currentWord
            if word.isEmpty {
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: 0))
                composing = false
            } else {
                setMarked(word, client: client)
            }
            return true
        }
        if engine.currentWord.isEmpty {
            expectedLocation = nil
            return false
        }
        let sel = client.selectedRange()
        if sel.location != NSNotFound, sel.length > 0 || !wordStillBeforeCursor(client, sel: sel) {
            resetWord()
            return false
        }
        engine.backspace()
        if let loc = expectedLocation { expectedLocation = max(0, loc - 1) }
        if engine.currentWord.isEmpty { expectedLocation = nil }
        return false // app tự xoá
    }

    // MARK: Marked mode (gạch chân)

    private func handleMarked(_ scalar: Unicode.Scalar, client: IMKTextInput) -> Bool {
        if !composing {
            applyContext(client, location: client.selectedRange().location)
        }
        let before = engine.currentWord
        let edit = engine.process(scalar)
        let word = engine.currentWord
        if edit.passthrough && word.isEmpty {
            // Ký tự ngoài từ (dấu cách, dấu câu): chốt từ trước rồi để app chèn ký tự.
            commitIfComposing(client, word: before)
            resetWord()
            return false
        }
        setMarked(word, client: client)
        composing = true
        return true
    }

    private func setMarked(_ word: String, client: IMKTextInput) {
        let len = word.utf16.count
        client.setMarkedText(word, selectionRange: NSRange(location: len, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func commitIfComposing(_ client: IMKTextInput?, word: String? = nil) {
        guard composing, let client = client else { return }
        let text = word ?? engine.currentWord
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        composing = false
    }

    // MARK: Ctrl+Shift bật/tắt

    private func handleFlagsChanged(_ event: NSEvent, client: IMKTextInput) {
        guard Settings.shared.toggleHotkey else { return }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if flags == [.control, .shift] {
            hotkeyArmed = true
        } else if flags.isEmpty {
            if hotkeyArmed { toggleVietnamese(client) }
            hotkeyArmed = false
        } else if !flags.isSubset(of: [.control, .shift]) {
            hotkeyArmed = false
        }
    }

    private func toggleVietnamese(_ client: IMKTextInput?) {
        commitIfComposing(client)
        resetWord()
        let newMode: AppMode
        if mode == .english {
            newMode = Settings.shared.isCodeApp(bundleID) ? .code : .vietnamese
        } else {
            newMode = .english
        }
        mode = newMode
        engine.englishCheck = (mode == .code)
        if !bundleID.isEmpty { Settings.shared.setMode(newMode, for: bundleID) }
        ModeHUD.shared.show(newMode == .english ? "EN" : "VI", near: client)
    }

    // MARK: Menu trong biểu tượng bộ gõ

    private enum Tag: Int {
        case modeVietnamese = 1, modeCode, modeEnglish
        case telex = 10, vni
        case modernTone = 20, autoRestore, freeMarking, wStandalone, hotkey
        case smartContext = 25, vietnameseInStrings, editExisting
        case markedForApp = 30
        case editWords = 40, debugLog
        case uninstall = 50
    }

    override func menu() -> NSMenu! {
        let s = Settings.shared
        let m = NSMenu(title: "VietIME")

        let appName = bundleID.isEmpty ? "app này" : (NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?
            .deletingPathExtension().lastPathComponent ?? bundleID)
        let header = NSMenuItem(title: "Cho \(appName):", action: nil, keyEquivalent: "")
        header.isEnabled = false
        m.addItem(header)
        let modes: [(AppMode, Tag)] = [(.vietnamese, .modeVietnamese), (.code, .modeCode), (.english, .modeEnglish)]
        for (appMode, tag) in modes {
            m.addItem(item(appMode.title, tag, on: mode == appMode))
        }
        m.addItem(item("Dùng gạch chân (app không thay chữ được)", .markedForApp, on: style == .marked))
        m.addItem(.separator())
        m.addItem(item("Code: tự gõ tiếng Việt trong comment", .smartContext, on: s.smartContext))
        m.addItem(item("Code: gõ tiếng Việt cả trong chuỗi \"...\"", .vietnameseInStrings, on: s.vietnameseInStrings))
        let hint = NSMenuItem(title: "Mẹo: gõ thêm z để ép bỏ dấu (maxz → mã)", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        m.addItem(hint)
        m.addItem(.separator())
        m.addItem(item("Telex", .telex, on: s.method == .telex))
        m.addItem(item("VNI", .vni, on: s.method == .vni))
        m.addItem(.separator())
        m.addItem(item("Đặt dấu kiểu mới (hoà, thuỷ)", .modernTone, on: s.modernTone))
        m.addItem(item("Tự khôi phục từ không phải tiếng Việt", .autoRestore, on: s.autoRestore))
        m.addItem(item("Bỏ dấu tự do (tana → tân)", .freeMarking, on: s.freeMarking))
        m.addItem(item("Telex: w → ư", .wStandalone, on: s.wStandalone))
        m.addItem(item("Ctrl+Shift để bật/tắt", .hotkey, on: s.toggleHotkey))
        m.addItem(item("Sửa dấu từ đã gõ (đặt con trỏ vào từ rồi gõ dấu)", .editExisting, on: s.editExistingWords))
        m.addItem(.separator())
        m.addItem(item("Sửa từ điển ngoại lệ…", .editWords, on: false))
        m.addItem(item("Ghi log chẩn đoán", .debugLog, on: s.debugLog))
        m.addItem(.separator())
        m.addItem(item("Gỡ cài đặt VietIME…", .uninstall, on: false))
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let v = NSMenuItem(title: "VietIME \(version)", action: nil, keyEquivalent: "")
        v.isEnabled = false
        m.addItem(v)
        return m
    }

    private func item(_ title: String, _ tag: Tag, on: Bool) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: "")
        i.tag = tag.rawValue
        i.state = on ? .on : .off
        i.target = self
        return i
    }

    @objc private func menuAction(_ sender: Any?) {
        // IMK gửi dictionary chứa NSMenuItem; gọi trực tiếp thì sender là NSMenuItem.
        let menuItem = (sender as? NSMenuItem)
            ?? ((sender as? [String: Any])?[kIMKCommandMenuItemName] as? NSMenuItem)
            ?? ((sender as? NSDictionary)?[kIMKCommandMenuItemName] as? NSMenuItem)
        guard let tag = menuItem.flatMap({ Tag(rawValue: $0.tag) }) else { return }
        let s = Settings.shared
        switch tag {
        case .modeVietnamese: setAppMode(.vietnamese)
        case .modeCode: setAppMode(.code)
        case .modeEnglish: setAppMode(.english)
        case .markedForApp:
            let newStyle: InsertStyle = style == .marked ? .direct : .marked
            if !bundleID.isEmpty { s.setInsertStyle(newStyle, for: bundleID) }
        case .telex: s.method = .telex
        case .vni: s.method = .vni
        case .modernTone: s.modernTone.toggle()
        case .autoRestore: s.autoRestore.toggle()
        case .freeMarking: s.freeMarking.toggle()
        case .wStandalone: s.wStandalone.toggle()
        case .hotkey: s.toggleHotkey.toggle()
        case .smartContext: s.smartContext.toggle()
        case .vietnameseInStrings: s.vietnameseInStrings.toggle()
        case .editExisting: s.editExistingWords.toggle()
        case .debugLog: s.debugLog.toggle()
        case .uninstall:
            Uninstaller.run()
            return
        case .editWords:
            s.ensureWordsFile()
            NSWorkspace.shared.open(s.wordsFileURL)
        }
        reloadSettings()
        resetWord()
    }

    private func setAppMode(_ m: AppMode) {
        if !bundleID.isEmpty { Settings.shared.setMode(m, for: bundleID) }
    }
}
