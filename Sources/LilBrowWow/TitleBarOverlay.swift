import AppKit
import LilBrowCore

/// The Copy and Move-to-browser buttons, drawn in a borderless panel that sits on the right end of a little
/// window's title bar. The panel never activates this app, so the browser keeps focus when a button is clicked.
/// With more than one browser profile, the Move button splits: "↗ Work" moves the page live, and "▾" offers the
/// other profiles.
@MainActor
final class TitleBarOverlay {
    /// Gap above and to the right of the buttons, inside the window's top-right corner.
    static let inset: CGFloat = 5
    /// Dia's popup window corner radius (estimated); the rightmost button's top-right corner nests inside it.
    static let windowCornerRadius: CGFloat = 16

    private let panel: NSPanel
    private let stack = NSStackView()
    private let browserName: String
    private let onCopy: (Int) -> Void
    private let onMove: (Int) -> Void
    private let onSendToProfile: (Int, String) -> Void
    private var copyButton: PillButton!
    private var otherProfiles: [String] = []
    private var current: TrackedWindow?
    private var copiedReset: DispatchWorkItem?

    init(browserName: String, onCopy: @escaping (Int) -> Void, onMove: @escaping (Int) -> Void,
         onSendToProfile: @escaping (Int, String) -> Void) {
        self.browserName = browserName
        self.onCopy = onCopy
        self.onMove = onMove
        self.onSendToProfile = onSendToProfile

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

        stack.orientation = .horizontal
        stack.spacing = 4
        panel.contentView = stack
        setProfiles(nil)
    }

    /// Rebuilds the buttons for the browser's profiles (nil: unknown, a plain Move button labeled with the browser).
    func setProfiles(_ profiles: BrowserProfiles?) {
        otherProfiles = profiles?.others ?? []
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        copyButton = PillButton(title: nil, symbol: "link", label: "Copy link", filled: false)
        copyButton.toolTip = "Copy this page's URL"
        copyButton.target = self
        copyButton.action = #selector(copyClicked)
        stack.addArrangedSubview(copyButton)

        let nest = Self.windowCornerRadius - Self.inset
        let destination = profiles?.current ?? browserName
        let split = !otherProfiles.isEmpty
        let move = PillButton(title: destination, symbol: "arrow.up.forward.app", label: "Move to \(destination)",
                              corners: split ? .init(topLeft: 6, topRight: 0, bottomRight: 0, bottomLeft: 6)
                                             : .init(topLeft: 6, topRight: nest, bottomRight: 6, bottomLeft: 6))
        move.toolTip = "Move this page to the main \(browserName) window"
        move.target = self
        move.action = #selector(moveClicked)
        stack.addArrangedSubview(move)

        if split {
            let chevron = PillButton(title: nil, symbol: "chevron.down", label: "Send to another profile", width: 20,
                                     corners: .init(topLeft: 0, topRight: nest, bottomRight: 6, bottomLeft: 0))
            chevron.toolTip = "Send this page to another profile"
            chevron.target = self
            chevron.action = #selector(chevronClicked(_:))
            stack.setCustomSpacing(1, after: move)
            stack.addArrangedSubview(chevron)
        }
        panel.setContentSize(stack.fittingSize)
        if let current, panel.isVisible { show(current, primaryScreenHeight: NSScreen.screens.first?.frame.height ?? 0) }
    }

    func show(_ window: TrackedWindow, primaryScreenHeight: CGFloat) {
        current = window
        let size = stack.fittingSize
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

    @objc private func chevronClicked(_ sender: NSButton) {
        guard let id = current?.windowId else { return }
        let menu = NSMenu()
        for profile in otherProfiles {
            let item = MenuAction(title: "Send to \(profile)") { [weak self] in self?.onSendToProfile(id, profile) }
            menu.addItem(item)
        }
        let below = NSPoint(x: 0, y: sender.isFlipped ? sender.bounds.maxY + 4 : -4)
        menu.popUp(positioning: nil, at: below, in: sender)
    }
}

private final class MenuAction: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}

/// A small borderless button, optionally with a soft, semi-transparent fill that darkens on hover and press.
/// The fill is drawn here rather than set on the button's layer, which AppKit manages itself.
private final class PillButton: NSButton {
    struct Corners {
        var topLeft: CGFloat, topRight: CGFloat, bottomRight: CGFloat, bottomLeft: CGFloat
        static let standard = Corners(topLeft: 6, topRight: 6, bottomRight: 6, bottomLeft: 6)
    }

    static let height: CGFloat = 23
    private let filled: Bool
    private let corners: Corners
    private let fixedWidth: CGFloat?
    private var hovering = false { didSet { needsDisplay = true } }

    init(title: String?, symbol: String, label: String, filled: Bool = true, width: CGFloat? = nil, corners: Corners = .standard) {
        self.filled = filled
        self.corners = corners
        self.fixedWidth = width
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
        if let fixedWidth { return NSSize(width: fixedWidth, height: Self.height) }
        // Icon-only buttons are unfilled, so a little extra width is invisible and makes a bigger click target.
        let width = title.isEmpty ? Self.height + 4 : super.intrinsicContentSize.width + 16
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

    /// A rectangle with its own radius at each corner.
    private func fillPath() -> NSBezierPath {
        let r = bounds
        let cap = r.height / 2
        let tl = min(corners.topLeft, cap), tr = min(corners.topRight, cap)
        let br = min(corners.bottomRight, cap), bl = min(corners.bottomLeft, cap)
        // In a flipped view the top edge is at minY.
        let top = isFlipped ? r.minY : r.maxY, bottom = isFlipped ? r.maxY : r.minY
        let down: CGFloat = isFlipped ? 1 : -1   // from the top edge toward the bottom
        let k: CGFloat = 0.45                    // control-point factor for soft corners
        let path = NSBezierPath()
        path.move(to: NSPoint(x: r.minX + tl, y: top))
        path.line(to: NSPoint(x: r.maxX - tr, y: top))
        path.curve(to: NSPoint(x: r.maxX, y: top + down * tr),
                   controlPoint1: NSPoint(x: r.maxX - tr * k, y: top), controlPoint2: NSPoint(x: r.maxX, y: top + down * tr * (1 - k)))
        path.line(to: NSPoint(x: r.maxX, y: bottom - down * br))
        path.curve(to: NSPoint(x: r.maxX - br, y: bottom),
                   controlPoint1: NSPoint(x: r.maxX, y: bottom - down * br * k), controlPoint2: NSPoint(x: r.maxX - br * (1 - k), y: bottom))
        path.line(to: NSPoint(x: r.minX + bl, y: bottom))
        path.curve(to: NSPoint(x: r.minX, y: bottom - down * bl),
                   controlPoint1: NSPoint(x: r.minX + bl * k, y: bottom), controlPoint2: NSPoint(x: r.minX, y: bottom - down * bl * (1 - k)))
        path.line(to: NSPoint(x: r.minX, y: top + down * tl))
        path.curve(to: NSPoint(x: r.minX + tl, y: top),
                   controlPoint1: NSPoint(x: r.minX, y: top + down * tl * k), controlPoint2: NSPoint(x: r.minX + tl * (1 - k), y: top))
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
