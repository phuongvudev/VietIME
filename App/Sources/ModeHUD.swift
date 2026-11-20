import Cocoa
import InputMethodKit

/// Ô nhỏ "VI" / "EN" hiện cạnh con trỏ khi bấm Ctrl+Shift.
final class ModeHUD {
    static let shared = ModeHUD()

    private let panel: NSPanel
    private let label: NSTextField
    private var hideWork: DispatchWorkItem?

    private init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 44, height: 26),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]

        let bg = NSVisualEffectView(frame: panel.contentView!.bounds)
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 6
        bg.autoresizingMask = [.width, .height]

        label = NSTextField(labelWithString: "VI")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 4, width: 44, height: 18)
        label.autoresizingMask = [.width]
        bg.addSubview(label)
        panel.contentView?.addSubview(bg)
    }

    func show(_ text: String, near client: IMKTextInput?) {
        label.stringValue = text
        var origin = NSEvent.mouseLocation
        if let client = client {
            var rect = NSRect.zero
            _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
            if rect != .zero { origin = NSPoint(x: rect.minX, y: rect.minY - 30) }
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
}
