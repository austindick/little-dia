import AppKit
import LilBrowCore

/// The Copy and Move-to-browser buttons, drawn in a borderless panel that sits on the right end of a little
/// window's title bar. The panel never activates this app, so the browser keeps focus when a button is clicked.
@MainActor
final class TitleBarOverlay {
    /// Gap above and to the right of the buttons, inside the window's top-right corner.
    static let inset: CGFloat = 5
    /// Dia's popup window corner radius (estimated); the Move button's top-right corner nests inside it.
    static let windowCornerRadius: CGFloat = 16

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
        // Disappear instantly when hidden (drag/resize); the fade-in on show is done by hand.
        panel.animationBehavior = .none

        copyButton = PillButton(title: nil, symbol: "link", label: "Copy link", filled: false)
        moveButton = PillButton(title: browserName, symbol: "arrow.up.forward.app", label: "Open in \(browserName)",
                                topRightRadius: Self.windowCornerRadius - Self.inset)
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
        let topLeft = ScreenGeometry.overlayFrame(windowTopLeft: window.frameTopLeft, overlaySize: size, inset: Self.inset)
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
        panel.alphaValue = 0   // stops a fade-in that may still be running
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

/// A small borderless button, optionally with a soft, semi-transparent rounded fill that darkens on hover and press.
/// The fill is drawn here rather than set on the button's layer, which AppKit manages itself.
private final class PillButton: NSButton {
    static let height: CGFloat = 23
    static let cornerRadius: CGFloat = 6
    private let filled: Bool
    private let topRightRadius: CGFloat
    private var hovering = false { didSet { needsDisplay = true } }

    init(title: String?, symbol: String, label: String, filled: Bool = true, topRightRadius: CGFloat? = nil) {
        self.filled = filled
        self.topRightRadius = topRightRadius ?? Self.cornerRadius
        super.init(frame: .zero)
        self.title = title ?? ""
        isBordered = false
        setButtonType(.momentaryChange)
        imagePosition = title == nil ? .imageOnly : .imageLeading
        imageHugsTitle = true
        font = .systemFont(ofSize: 12, weight: .medium)
        contentTintColor = .labelColor
        setAccessibilityLabel(label)
        setSymbol(symbol)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setSymbol(_ name: String) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }

    override var intrinsicContentSize: NSSize {
        let content = super.intrinsicContentSize
        // Icon-only buttons have no fill, so a little extra width is invisible and makes a bigger click target.
        let width = title.isEmpty ? Self.height + 4 : content.width + 16
        return NSSize(width: max(width, Self.height), height: Self.height)
    }

    override var isHighlighted: Bool {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        if filled {
            let alpha: CGFloat = isHighlighted ? 0.22 : hovering ? 0.15 : 0.08
            NSColor.labelColor.withAlphaComponent(alpha).setFill()
            fillPath().fill()
        }
        super.draw(dirtyRect)
    }

    /// A rounded rectangle whose top-right corner can be rounder than the rest.
    private func fillPath() -> NSBezierPath {
        let r = bounds, small = Self.cornerRadius, big = min(topRightRadius, r.height / 2)
        // In a flipped view the top edge is at minY.
        let top = isFlipped ? r.minY : r.maxY, bottom = isFlipped ? r.maxY : r.minY
        let down: CGFloat = isFlipped ? 1 : -1   // direction from the top edge toward the bottom
        let path = NSBezierPath()
        path.move(to: NSPoint(x: r.minX + small, y: top))
        path.line(to: NSPoint(x: r.maxX - big, y: top))
        path.curve(to: NSPoint(x: r.maxX, y: top + down * big),
                   controlPoint1: NSPoint(x: r.maxX - big * 0.45, y: top), controlPoint2: NSPoint(x: r.maxX, y: top + down * big * 0.55))
        path.line(to: NSPoint(x: r.maxX, y: bottom - down * small))
        path.curve(to: NSPoint(x: r.maxX - small, y: bottom),
                   controlPoint1: NSPoint(x: r.maxX, y: bottom - down * small * 0.45), controlPoint2: NSPoint(x: r.maxX - small * 0.55, y: bottom))
        path.line(to: NSPoint(x: r.minX + small, y: bottom))
        path.curve(to: NSPoint(x: r.minX, y: bottom - down * small),
                   controlPoint1: NSPoint(x: r.minX + small * 0.45, y: bottom), controlPoint2: NSPoint(x: r.minX, y: bottom - down * small * 0.55))
        path.line(to: NSPoint(x: r.minX, y: top + down * small))
        path.curve(to: NSPoint(x: r.minX + small, y: top),
                   controlPoint1: NSPoint(x: r.minX, y: top + down * small * 0.45), controlPoint2: NSPoint(x: r.minX + small * 0.55, y: top))
        path.close()
        return path
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
        needsDisplay = true
    }
}
