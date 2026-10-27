import AppKit
import LittleDiaCore
import os

/// The Back, Copy and Move-to-browser buttons, drawn in a borderless panel that sits on the right end of a little
/// window's title bar. The panel never activates this app, so the browser keeps focus when a button is clicked.
/// With more than one browser profile, the Move button splits: "↗ Work" moves the page live, and "▾" offers the
/// other profiles. Back is dimmed while the page has nowhere to go back to.
/// A click-through backdrop sits just below the buttons: the title bar's own colour, fading in from the left, so a
/// long page title fades out before the buttons instead of running under them.
@MainActor
final class TitleBarOverlay {
    /// Gaps above and to the right of the buttons, inside the window's top-right corner. With the buttons'
    /// height they fill Dia's 31pt title bar (measured 2026-10-26) with an equal gap below.
    static let topInset: CGFloat = 4
    static let rightInset: CGFloat = 4
    /// Dia's popup window corner radius (estimated); the rightmost button's top-right corner nests inside it.
    static let windowCornerRadius: CGFloat = 16
    /// How far left of the buttons the backdrop starts fading in.
    static let fadeWidth: CGFloat = 40

    private let panel: NSPanel
    private let backdrop: NSPanel
    private let stack = NSStackView()
    private let browserName: String
    private let onBack: (Int) -> Void
    private let onCopy: (Int) -> Void
    private let onMove: (Int) -> Void
    private let onSendToProfile: (Int, String) -> Void
    private var backButton: PillButton!
    private var copyButton: PillButton!
    private var profiles: BrowserProfiles?
    private var current: TrackedWindow?
    private var canGoBack = false
    private var copiedReset: DispatchWorkItem?

    init(browserName: String, titleBarColor: NSColor, onBack: @escaping (Int) -> Void, onCopy: @escaping (Int) -> Void,
         onMove: @escaping (Int) -> Void, onSendToProfile: @escaping (Int, String) -> Void) {
        self.browserName = browserName
        self.onBack = onBack
        Self.allowCursorChangesInBackground()
        self.onCopy = onCopy
        self.onMove = onMove
        self.onSendToProfile = onSendToProfile

        panel = Self.makePanel()
        backdrop = Self.makePanel()
        // The fade strip lies over Dia's title bar, which must stay draggable and clickable.
        backdrop.ignoresMouseEvents = true
        backdrop.contentView = BackdropView(color: titleBarColor, fadeWidth: Self.fadeWidth,
                                            cornerRadius: Self.windowCornerRadius - Self.rightInset)

        stack.orientation = .horizontal
        stack.spacing = 4
        panel.contentView = stack
        setProfiles(nil)
    }

    /// macOS ignores cursor changes from apps that aren't active, and this one never is. The window server has a
    /// private per-app switch for that; it's looked up at run time, so if a macOS release drops it the buttons simply
    /// keep the arrow cursor.
    private static func allowCursorChangesInBackground() {
        typealias MainConnection = @convention(c) () -> Int32
        typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        let logger = Logger(subsystem: "com.austindick.littledia", category: "overlay")
        guard let handle = dlopen(nil, RTLD_LAZY),
              let mainSymbol = dlsym(handle, "CGSMainConnectionID"),
              let setSymbol = dlsym(handle, "CGSSetConnectionProperty") else {
            logger.notice("can't set the cursor in the background on this macOS")
            return
        }
        let connection = unsafeBitCast(mainSymbol, to: MainConnection.self)()
        let status = unsafeBitCast(setSymbol, to: SetProperty.self)(connection, connection, "SetsCursorInBackground" as CFString,
                                                                    kCFBooleanTrue)
        if status != 0 { logger.notice("can't set the cursor in the background (\(status))") }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
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
        return panel
    }

        /// Rebuilds the buttons for the browser's profiles (nil: unknown, a plain Move button labeled with the browser).
    func setProfiles(_ profiles: BrowserProfiles?) {
        self.profiles = profiles
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        backButton = PillButton(title: nil, symbol: "arrow.left", label: "Back", filled: false)
        backButton.toolTip = "Go back"
        backButton.target = self
        backButton.action = #selector(backClicked)
        backButton.isEnabled = canGoBack
        stack.addArrangedSubview(backButton)

        copyButton = PillButton(title: nil, symbol: "link", label: "Copy link", filled: false)
        copyButton.toolTip = "Copy this page's URL"
        copyButton.target = self
        copyButton.action = #selector(copyClicked)
        stack.addArrangedSubview(copyButton)

        let nest = Self.windowCornerRadius - Self.rightInset
        let destination = profiles?.current ?? browserName
        let split = !(profiles?.others.isEmpty ?? true)
        let move = PillButton(title: "Open in \(destination)", symbol: "arrow.up.forward.app", label: "Open in \(destination)",
                              corners: split ? .init(topLeft: nest, topRight: 0, bottomRight: 0, bottomLeft: nest)
                                             : .init(topLeft: nest, topRight: nest, bottomRight: nest, bottomLeft: nest))
        move.toolTip = "Move this page to the main \(browserName) window"
        move.target = self
        move.action = #selector(moveClicked)
        stack.addArrangedSubview(move)

        if split {
            let chevron = PillButton(title: nil, symbol: "chevron.down", label: "Open in another profile", width: 26,
                                     corners: .init(topLeft: 0, topRight: nest, bottomRight: nest, bottomLeft: 0))
            chevron.toolTip = "Open this page in another profile"
            chevron.target = self
            chevron.action = #selector(chevronClicked(_:))
            stack.setCustomSpacing(1, after: move)
            stack.addArrangedSubview(chevron)
        }
        panel.setContentSize(stack.fittingSize)
        if let current, panel.isVisible { show(current, canGoBack: canGoBack, primaryScreenHeight: NSScreen.screens.first?.frame.height ?? 0) }
    }

    /// Enables or dims Back for the little window the buttons are on; other windows' changes wait until they're shown.
    func setCanGoBack(_ canGoBack: Bool, windowId: Int) {
        guard current?.windowId == windowId else { return }
        self.canGoBack = canGoBack
        backButton.isEnabled = canGoBack
    }

    func show(_ window: TrackedWindow, canGoBack: Bool, primaryScreenHeight: CGFloat) {
        current = window
        self.canGoBack = canGoBack
        backButton.isEnabled = canGoBack
        let size = stack.fittingSize
        let topLeft = ScreenGeometry.overlayFrame(windowTopLeft: window.frameTopLeft, overlaySize: size,
                                                  topInset: Self.topInset, rightInset: Self.rightInset)
        let wasHidden = !panel.isVisible
        let frame = ScreenGeometry.appKitRect(fromTopLeft: topLeft, primaryScreenHeight: primaryScreenHeight)
        panel.setFrame(frame, display: true)
        backdrop.setFrame(NSRect(x: frame.minX - Self.fadeWidth, y: frame.minY, width: frame.width + Self.fadeWidth, height: frame.height),
                          display: true)
        if wasHidden {
            panel.alphaValue = 0
            backdrop.alphaValue = 0
        }
        // The backdrop goes up first so the buttons stay on top of it.
        backdrop.orderFrontRegardless()
        panel.orderFrontRegardless()
        if wasHidden {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
                backdrop.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        current = nil
        // Setting alpha stops a fade-in that may still be running.
        for window in [panel, backdrop] {
            window.alphaValue = 0
            window.orderOut(nil)
        }
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

    @objc private func backClicked() {
        if let id = current?.windowId { onBack(id) }
    }

    @objc private func copyClicked() {
        if let id = current?.windowId { onCopy(id) }
    }

    @objc private func moveClicked() {
        if let id = current?.windowId { onMove(id) }
    }

    @objc private func chevronClicked(_ sender: NSButton) {
        guard let id = current?.windowId, let profiles else { return }
        let menu = NSMenu()
        for profile in profiles.all {
            // The little window's own profile gets the live move; the others reopen the page there.
            let item = MenuAction(title: profile) { [weak self] in
                if profile == profiles.current { self?.onMove(id) } else { self?.onSendToProfile(id, profile) }
            }
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

/// Solid `color` under the buttons, rounded on the right like the rightmost button, fading to clear over `fadeWidth`
/// on the left.
private final class BackdropView: NSView {
    private let color: NSColor
    private let fadeWidth: CGFloat
    private let cornerRadius: CGFloat

    init(color: NSColor, fadeWidth: CGFloat, cornerRadius: CGFloat) {
        self.color = color
        self.fadeWidth = fadeWidth
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        // Resolved while drawing, so a colour that follows light and dark mode uses this view's appearance.
        let solid = color.usingColorSpace(.sRGB) ?? color
        solid.setFill()
        NSRect(x: fadeWidth, y: 0, width: bounds.width - fadeWidth - cornerRadius, height: bounds.height).fill()
        NSBezierPath(roundedRect: NSRect(x: bounds.width - 2 * cornerRadius, y: 0, width: 2 * cornerRadius, height: bounds.height),
                     xRadius: cornerRadius, yRadius: cornerRadius).fill()
        NSGradient(starting: solid.withAlphaComponent(0), ending: solid)?
            .draw(in: NSRect(x: 0, y: 0, width: fadeWidth, height: bounds.height), angle: 0)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

extension NSColor {
    /// A colour that follows the light or dark appearance of whatever draws it.
    convenience init(_ color: AppearanceColor) {
        self.init(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? color.dark : color.light
            return NSColor(srgbRed: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255, blue: CGFloat(rgb.blue) / 255, alpha: 1)
        }
    }
}

/// A small borderless button with a soft, semi-transparent fill that darkens on hover and press. Unfilled (icon-only)
/// buttons show the fill only on hover and press. The fill is drawn here rather than set on the button's layer, which
/// AppKit manages itself.
private final class PillButton: NSButton {
    struct Corners {
        var topLeft: CGFloat, topRight: CGFloat, bottomRight: CGFloat, bottomLeft: CGFloat
        static let standard = Corners(topLeft: 6, topRight: 6, bottomRight: 6, bottomLeft: 6)
    }

    /// 4pt above, 23pt of button and 4pt below fill Dia's 31pt title bar.
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
        // Icon-only buttons get a little extra width for a bigger click target; their hover fill covers it.
        let width = title.isEmpty ? 27 : super.intrinsicContentSize.width + 16
        return NSSize(width: max(width, Self.height), height: Self.height)
    }

    override var isHighlighted: Bool {
        didSet { needsDisplay = true }
    }

    override var isEnabled: Bool {
        didSet {
            contentTintColor = isEnabled ? .labelColor : .tertiaryLabelColor
            needsDisplay = true
        }
    }

    /// AppKit gives icon-only buttons alignment insets taken from the symbol's shape, which made the chevron half a
    /// point shorter and half a point wider than laid out (so its right edge was clipped). These buttons are laid out
    /// by their full frame.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override func draw(_ dirtyRect: NSRect) {
        // Icon-only buttons have no fill at rest and a lighter one on hover and press. A disabled button (Back with
        // nowhere to go) gets no hover fill, as it gets no pointing hand.
        let (rest, hover, press): (CGFloat, CGFloat, CGFloat) = filled ? (0.08, 0.15, 0.22) : (0, 0.08, 0.16)
        let alpha = isHighlighted ? press : hovering && isEnabled ? hover : rest
        if alpha > 0 {
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
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    // The pointing hand is set by hand: this app is never active, so AppKit's cursor rects never apply to its panel
    // (see TitleBarOverlay.allowCursorChangesInBackground). It's set again as the mouse moves, in case the browser
    // underneath resets it.
    override func mouseEntered(with event: NSEvent) {
        hovering = true
        updateCursor()
    }

    override func mouseMoved(with event: NSEvent) { updateCursor() }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        NSCursor.arrow.set()
    }

    private func updateCursor() {
        (isEnabled ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
