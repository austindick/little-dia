import AppKit
import LilBrowCore

/// The Copy and Move-to-browser buttons, drawn in a borderless panel that sits on the right end of a little
/// window's title bar. The panel never activates this app, so the browser keeps focus when a button is clicked.
@MainActor
final class TitleBarOverlay {
    /// Dia's popup title bar (measured); the address row sits below it.
    static let titleBarHeight: CGFloat = 28
    static let rightInset: CGFloat = 8

    private let panel: NSPanel
    private let copyButton: PillButton
    private let moveButton: PillButton
    private let onCopy: (Int) -> Void
    private let onMove: (Int) -> Void
    private var current: TrackedWindow?
    private var copiedReset: DispatchWorkItem?

    init(browserName: String, onCopy: @escaping (Int) -> Void, onMove: @escaping (Int) -> Void) {
        self.onCopy = onCopy
        self.onMove = onMove

        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isFloatingPanel = true

        copyButton = PillButton(title: nil, symbol: "link", label: "Copy link")
        moveButton = PillButton(title: browserName, symbol: "arrow.up.forward.app", label: "Open in \(browserName)")
        copyButton.toolTip = "Copy this page's URL"
        moveButton.toolTip = "Move this page to the main \(browserName) window"

        let stack = NSStackView(views: [copyButton, moveButton])
        stack.orientation = .horizontal
        stack.spacing = 4
        panel.contentView = stack
        panel.setContentSize(stack.fittingSize)

        copyButton.target = self
        copyButton.action = #selector(copyClicked)
        moveButton.target = self
        moveButton.action = #selector(moveClicked)
    }

    func show(_ window: TrackedWindow, primaryScreenHeight: CGFloat) {
        current = window
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        let topLeft = ScreenGeometry.overlayFrame(windowTopLeft: window.frameTopLeft, overlaySize: size,
                                                  titleBarHeight: Self.titleBarHeight, rightInset: Self.rightInset)
        let wasHidden = !panel.isVisible
        panel.setFrame(ScreenGeometry.appKitRect(fromTopLeft: topLeft, primaryScreenHeight: primaryScreenHeight), display: true)
        if wasHidden {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        current = nil
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    /// Swaps the link icon for a checkmark for a moment.
    func flashCopied() {
        copiedReset?.cancel()
        copyButton.setSymbol("checkmark")
        let reset = DispatchWorkItem { [weak self] in self?.copyButton.setSymbol("link") }
        copiedReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: reset)
    }

    @objc private func copyClicked() {
        if let id = current?.windowId { onCopy(id) }
    }

    @objc private func moveClicked() {
        if let id = current?.windowId { onMove(id) }
    }
}

/// A small borderless button with a soft, semi-transparent rounded fill that darkens on hover and press.
private final class PillButton: NSButton {
    static let height: CGFloat = 22
    private var hovering = false { didSet { updateFill() } }

    init(title: String?, symbol: String, label: String) {
        super.init(frame: .zero)
        self.title = title ?? ""
        isBordered = false
        setButtonType(.momentaryChange)
        imagePosition = title == nil ? .imageOnly : .imageLeading
        imageHugsTitle = true
        font = .systemFont(ofSize: 12, weight: .medium)
        contentTintColor = .labelColor
        setAccessibilityLabel(label)
        wantsLayer = true
        layer?.cornerRadius = 6
        setSymbol(symbol)
        updateFill()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setSymbol(_ name: String) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }

    override var intrinsicContentSize: NSSize {
        let content = super.intrinsicContentSize
        let width = title.isEmpty ? Self.height + 4 : content.width + 16
        return NSSize(width: max(width, Self.height), height: Self.height)
    }

    override var isHighlighted: Bool {
        didSet { updateFill() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFill()
    }

    private func updateFill() {
        let alpha: CGFloat = isHighlighted ? 0.22 : hovering ? 0.15 : 0.08
        var color: CGColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.labelColor.withAlphaComponent(alpha).cgColor
        }
        layer?.backgroundColor = color
    }
}
