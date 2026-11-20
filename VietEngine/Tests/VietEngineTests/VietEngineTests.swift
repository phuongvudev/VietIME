import XCTest
@testable import VietEngine

final class VietEngineTests: XCTestCase {
    func testTelex() {
        let e = VietEngine()
        XCTAssertEqual(e.simulate("tieengs Vieetj"), "tiếng Việt")
        XCTAssertEqual(e.simulate("nguoiwf"), "người")
        XCTAssertEqual(e.simulate("dduowcj"), "được")
        XCTAssertEqual(e.simulate("hoaf"), "hoà")
        e.modernTone = false
        XCTAssertEqual(e.simulate("hoaf"), "hòa")
    }

    func testCodeStaysEnglish() {
        let e = VietEngine()
        for word in ["class", "pass", "useEffect", "if", "is", "as", "max", "test", "var", "return", "const"] {
            XCTAssertEqual(e.simulate(word), word, word)
        }
    }

    func testVNI() {
        let e = VietEngine()
        e.method = .vni
        XCTAssertEqual(e.simulate("vie65t"), "việt")
        XCTAssertEqual(e.simulate("d9u7o7c5"), "được")
    }

    func testBackspace() {
        let e = VietEngine()
        XCTAssertEqual(e.simulate("tieengs<"), "tiến")
        XCTAssertEqual(e.simulate("tieengs<g"), "tiếng")
    }

    func testForceVietnamese() {
        let e = VietEngine()
        XCTAssertEqual(e.simulate("max"), "max")
        XCTAssertEqual(e.simulate("maxz"), "mã")
        e.englishCheck = false
        XCTAssertEqual(e.simulate("max"), "mã")
        XCTAssertEqual(e.simulate("maxx"), "max")
    }

    func testContext() {
        XCTAssertEqual(VietEngine.detectContext("let a = 1 // "), .comment)
        XCTAssertEqual(VietEngine.detectContext("let a = \"Xin "), .string)
        XCTAssertEqual(VietEngine.detectContext("let a = "), .code)
        XCTAssertEqual(VietEngine.detectContext("x = 1  # "), .comment)
    }

    func testEditExistingWord() {
        let e = VietEngine()
        XCTAssertTrue(e.loadWord("việt"))
        let edit = e.process(Character("s"))
        XCTAssertEqual(edit, Edit(passthrough: false, backspaces: 2, insert: "ết"))
        XCTAssertEqual(e.currentWord, "viết")
        XCTAssertTrue(VietEngine.isWordChar("ệ"))
        XCTAssertFalse(VietEngine.isWordChar(" "))
    }

    func testMinimalReplacement() {
        // Chỉ thay đúng phần thay đổi để giữ suggestion của editor
        let e = VietEngine()
        e.reset()
        _ = e.process(Character("t"))
        _ = e.process(Character("i"))
        _ = e.process(Character("e"))
        let edit = e.process(Character("e"))
        XCTAssertEqual(edit, Edit(passthrough: false, backspaces: 1, insert: "ê"))
    }
}
