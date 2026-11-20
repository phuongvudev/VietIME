import CVietEngine

public enum InputMethod: Int, CaseIterable {
    case telex = 0
    case vni = 1
}

/// Kết quả của một phím: xoá `backspaces` ký tự trước con trỏ rồi chèn `insert`.
/// `passthrough == true` nghĩa là để app tự chèn phím (bộ gõ không can thiệp).
public struct Edit: Equatable {
    public let passthrough: Bool
    public let backspaces: Int
    public let insert: String

    public static let pass = Edit(passthrough: true, backspaces: 0, insert: "")
}

/// Ngữ cảnh tại con trỏ khi gõ code.
public enum CodeContext: Equatable {
    case code
    case comment
    case string
}

public final class VietEngine {
    /// Đoán con trỏ đang ở code, comment hay chuỗi từ text ngay trước con trỏ.
    public static func detectContext(_ textBeforeCursor: String) -> CodeContext {
        var cps = textBeforeCursor.unicodeScalars.map { $0.value }
        let ctx = cps.withUnsafeMutableBufferPointer { buf in
            ve_detect_context(buf.baseAddress, Int32(buf.count))
        }
        switch ctx {
        case VE_CTX_COMMENT: return .comment
        case VE_CTX_STRING: return .string
        default: return .code
        }
    }

    private let ptr: OpaquePointer

    public init() {
        guard let p = ve_new() else { fatalError("VietEngine: không cấp phát được bộ nhớ") }
        ptr = p
    }

    deinit { ve_free(ptr) }

    // MARK: Tuỳ chọn

    public var method: InputMethod = .telex {
        didSet { ve_set_method(ptr, method == .telex ? VE_TELEX : VE_VNI) }
    }

    /// true: hoà, thuỷ (kiểu mới). false: hòa, thủy (kiểu cũ).
    public var modernTone: Bool = true {
        didSet { ve_set_modern_tone(ptr, modernTone ? 1 : 0) }
    }

    /// Tự khôi phục chữ gốc khi không phải âm tiết tiếng Việt hợp lệ.
    public var autoRestore: Bool = true {
        didSet { ve_set_auto_restore(ptr, autoRestore ? 1 : 0) }
    }

    /// Giữ nguyên các từ trong từ điển ngoại lệ (max, test, var, if, is...).
    public var englishCheck: Bool = true {
        didSet { ve_set_english_check(ptr, englishCheck ? 1 : 0) }
    }

    /// Cho phép bỏ dấu mũ / đ cách xa ("tana" → "tân").
    public var freeMarking: Bool = false {
        didSet { ve_set_free_marking(ptr, freeMarking ? 1 : 0) }
    }

    /// Telex: "w" đứng riêng → "ư".
    public var wStandalone: Bool = true {
        didSet { ve_set_w_standalone(ptr, wStandalone ? 1 : 0) }
    }

    // MARK: Từ điển ngoại lệ

    @discardableResult
    public func addWord(_ word: String) -> Bool { ve_add_english_word(ptr, word) == 1 }

    @discardableResult
    public func removeWord(_ word: String) -> Bool { ve_remove_english_word(ptr, word) == 1 }

    public func hasWord(_ word: String) -> Bool { ve_has_english_word(ptr, word) == 1 }

    // MARK: Phím

    /// Xử lý một ký tự (không kèm Cmd/Ctrl/Option).
    public func process(_ scalar: Unicode.Scalar) -> Edit {
        let r = ve_process_key(ptr, scalar.value)
        if r.passthrough != 0 { return .pass }
        let count = Int(r.insert_len)
        var s = String.UnicodeScalarView()
        withUnsafeBytes(of: r.insert) { raw in
            let cps = raw.bindMemory(to: UInt32.self)
            for i in 0..<count {
                if let u = Unicode.Scalar(cps[i]) { s.append(u) }
            }
        }
        return Edit(passthrough: false, backspaces: Int(r.backspaces), insert: String(s))
    }

    public func process(_ character: Character) -> Edit {
        let scalars = character.unicodeScalars
        guard scalars.count == 1, let u = scalars.first else {
            reset()
            return .pass
        }
        return process(u)
    }

    /// Nạp một từ có sẵn trong văn bản làm từ hiện tại, để phím tiếp theo sửa dấu cho nó.
    /// Trả false nếu từ không sửa dấu được (khi đó phím tiếp theo chỉ được chép).
    @discardableResult
    public func loadWord(_ word: String) -> Bool {
        var cps = word.unicodeScalars.map { $0.value }
        return cps.withUnsafeMutableBufferPointer { buf in
            ve_load_word(ptr, buf.baseAddress, Int32(buf.count)) == 1
        }
    }

    /// Ký tự có thuộc một từ không (chữ Latin, nguyên âm có dấu, đ).
    public static func isWordChar(_ u: Unicode.Scalar) -> Bool { ve_is_word_char(u.value) == 1 }

    /// Phím có thể là phím dấu (dùng để sửa dấu khi con trỏ nằm giữa từ).
    public func isMarkKey(_ u: Unicode.Scalar) -> Bool {
        switch method {
        case .telex: return "sfrxjzaeowdSFRXJZAEOWD".unicodeScalars.contains(u)
        case .vni: return u.value >= 0x30 && u.value <= 0x39
        }
    }

    /// Gọi khi người dùng nhấn Backspace (app tự xoá ký tự).
    public func backspace() { ve_backspace(ptr) }

    /// Kết thúc từ hiện tại.
    public func reset() { ve_reset(ptr) }

    /// Chữ đang hiển thị của từ hiện tại.
    public var currentWord: String {
        var buf = [UInt32](repeating: 0, count: 128)
        let n = Int(ve_current_word(ptr, &buf, Int32(buf.count)))
        var s = String.UnicodeScalarView()
        for i in 0..<n {
            if let u = Unicode.Scalar(buf[i]) { s.append(u) }
        }
        return String(s)
    }

    /// Độ dài từ hiện tại theo UTF-16 (đơn vị NSRange).
    public var currentWordUTF16Count: Int { currentWord.utf16.count }

    // MARK: Tiện ích cho test

    /// Gõ một chuỗi phím và trả về văn bản thu được (mô phỏng ô text).
    /// "<" = Backspace.
    public func simulate(_ keys: String) -> String {
        reset()
        var text: [Character] = []
        for ch in keys {
            if ch == "<" {
                backspace()
                if !text.isEmpty { text.removeLast() }
                continue
            }
            let e = process(ch)
            if e.passthrough {
                text.append(ch)
            } else {
                text.removeLast(min(e.backspaces, text.count))
                text.append(contentsOf: e.insert)
            }
        }
        return String(text)
    }
}
