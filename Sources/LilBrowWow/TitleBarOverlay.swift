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
    private let copyButton: NSButton
    private let moveButton: NSButton
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

        copyButton = Self.makeButton(title: "Copy", symbol: "link")
        moveButton = Self.makeButton(title: browserName, symbol: "arrow.up.forward.app")
        copyButton.toolTip = "Copy this page's URL"
        moveButton.toolTip = "Open this page in the main \(browserName) window"

        let stack = NSStackView(views: [copyButton, moveButton])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
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

    /// Shows "Copied" on the Copy button for a moment.
    func flashCopied() {
        copiedReset?.cancel()
        copyButton.title = "Copied"
        let reset = DispatchWorkItem { [weak self] in self?.copyButton.title = "Copy" }
        copiedReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: reset)
    }

    @objc private func copyClicked() {
        if let id = current?.windowId { onCopy(id) }
    }

    @objc private func moveClicked() {
        if let id = current?.windowId { onMove(id) }
    }

    private static func makeButton(title: String, symbol: String) -> NSButton {
        let button = NSButton(title: title, image: NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage(),
                              target: nil, action: nil)
        button.imagePosition = .imageLeading
        button.bezelStyle = .accessoryBarAction
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.setButtonType(.momentaryPushIn)
        return button
    }
}
