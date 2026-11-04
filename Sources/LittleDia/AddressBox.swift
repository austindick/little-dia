import AppKit
import LittleDiaCore

/// New Little Window: a floating box for a web address or a search, since a little window's own address bar can't
/// be typed in. Return opens it; Esc, or clicking elsewhere, cancels. It's a non-activating panel, like Spotlight: it
/// takes typing while the app you were in stays frontmost, so cancelling leaves you where you were.
@MainActor
final class AddressBox: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private let panel: KeyablePanel
    private let field = NSTextField()
    private var onSubmit: ((URL) -> Void)?

    override init() {
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 52),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        // A mask image, not a layer corner radius: the window's shadow and backing follow it, so the corners stay clear.
        background.maskImage = Self.roundedMask(radius: 12)

        let icon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
        icon.symbolConfiguration = .init(pointSize: 17, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor

        field.placeholderString = "Enter a web address or search"
        field.font = .systemFont(ofSize: 20)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self

        for view in [icon, field] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16),
            field.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        panel.contentView = background
    }

    /// Shows the box on this desktop, on the screen the pointer is on. If it's already open, brings it forward as it is.
    func show(onSubmit: @escaping (URL) -> Void) {
        self.onSubmit = onSubmit
        if !panel.isVisible {
            field.stringValue = ""
            let mouse = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
                let visible = screen.visibleFrame, size = panel.frame.size
                panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - visible.height / 3))
            }
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            // Empty text keeps the box open.
            guard let url = AddressInput.url(from: field.stringValue) else { return true }
            let submit = onSubmit
            dismiss()
            submit?(url)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss()
            return true
        default:
            return false
        }
    }

    /// Clicking anywhere else cancels, like Spotlight.
    func windowDidResignKey(_ notification: Notification) {
        if panel.isVisible { dismiss() }
    }

    /// A resizable rounded rectangle for the background's mask.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private func dismiss() {
        onSubmit = nil
        panel.orderOut(nil)
    }
}

/// A borderless panel doesn't take typing unless it says it can. It also handles the editing shortcuts itself: a
/// menu-bar app has no Edit menu, which is what normally turns ⌘V and the rest into actions.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    private static let editing: [String: Selector] = [
        "x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)), "v": #selector(NSText.paste(_:)),
        "a": #selector(NSText.selectAll(_:)), "z": Selector(("undo:")), "Z": Selector(("redo:")),
    ]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if modifiers == .command || modifiers == [.command, .shift], let key = event.charactersIgnoringModifiers,
           let action = Self.editing[modifiers.contains(.shift) ? key.uppercased() : key.lowercased()],
           NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
