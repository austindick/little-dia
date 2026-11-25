import AppKit
import LittleDiaCore

/// The menu-bar item. The menu is rebuilt every time it opens so its status line is current: "All set · Work", or the
/// first thing that needs fixing, which opens the setup window when clicked.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let settings: UserDefaultsSettings
    private let newLittleWindow: () -> Void
    private let hasRecentPages: () -> Bool
    private let clearRecentPages: () -> Void
    private let currentLittleWindowSize: () -> Bounds?
    private let useCurrentLittleWindowSize: () -> Void
    private let remembersResizedSizeChanged: () -> Void
    private let status: () -> SetupStatus
    private let showSetup: () -> Void
    private let copyDiagnostics: () -> Void
    private let updateOffer: () -> UpdateOffer?
    private let checkForUpdates: () -> Void
    private let installUpdate: (UpdateOffer) -> Void
    private let isUpdating: () -> Bool
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    init(settings: UserDefaultsSettings, newLittleWindow: @escaping () -> Void,
         hasRecentPages: @escaping () -> Bool, clearRecentPages: @escaping () -> Void,
         currentLittleWindowSize: @escaping () -> Bounds?, useCurrentLittleWindowSize: @escaping () -> Void,
         remembersResizedSizeChanged: @escaping () -> Void, status: @escaping () -> SetupStatus, showSetup: @escaping () -> Void,
         copyDiagnostics: @escaping () -> Void, updateOffer: @escaping () -> UpdateOffer?,
         checkForUpdates: @escaping () -> Void, installUpdate: @escaping (UpdateOffer) -> Void,
         isUpdating: @escaping () -> Bool) {
        self.settings = settings
        self.newLittleWindow = newLittleWindow
        self.hasRecentPages = hasRecentPages
        self.clearRecentPages = clearRecentPages
        self.currentLittleWindowSize = currentLittleWindowSize
        self.useCurrentLittleWindowSize = useCurrentLittleWindowSize
        self.remembersResizedSizeChanged = remembersResizedSizeChanged
        self.status = status
        self.showSetup = showSetup
        self.copyDiagnostics = copyDiagnostics
        self.updateOffer = updateOffer
        self.checkForUpdates = checkForUpdates
        self.installUpdate = installUpdate
        self.isUpdating = isUpdating
        super.init()
        let image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Little Dia")
        image?.isTemplate = true
        statusItem.button?.image = image
        menu.delegate = self
        menu.autoenablesItems = false   // "Clear Recent Pages" is greyed out when there are none
        statusItem.menu = menu
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    func refresh() {
        menu.removeAllItems()

        // ⌃⇧⌘N works from any app (a hot key the app registers); shown here so it can be found.
        let new = action("New Little Window…", newLittleWindow)
        new.keyEquivalent = "n"
        new.keyEquivalentModifierMask = [.command, .control, .shift]
        menu.addItem(new)
        // Empties the Recent list in the New Little Window box.
        let clear = action("Clear Recent Pages", clearRecentPages)
        clear.isEnabled = hasRecentPages()
        menu.addItem(clear)
        menu.addItem(action("Open Links in Little Windows", checked: settings.isEnabled) { [weak self] in
            guard let self else { return }
            settings.isEnabled.toggle()
        })
        menu.addItem(sizeItem())
        menu.addItem(.separator())

        let line = status().menuLine
        if case .problem = line {
            let item = action(line.text, showSetup)
            item.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Needs attention")
            menu.addItem(item)
        } else {
            let item = NSMenuItem(title: line.text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(action("Setup…", showSetup))
        menu.addItem(.separator())

        if isUpdating() {
            let item = NSMenuItem(title: "Updating…", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else if let offer = updateOffer() {
            menu.addItem(action("Update to \(offer.version)…") { [weak self] in self?.installUpdate(offer) })
        } else {
            menu.addItem(action("Check for Updates…", checkForUpdates))
        }
        menu.addItem(action("Copy Diagnostics", copyDiagnostics))
        menu.addItem(action("About Little Dia", Self.showAbout))
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Little Dia", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    /// "Little Window Size": the size new little windows open at, a way to set it from the little window in front, and
    /// whether resizing one sets it.
    private func sizeItem() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false   // "Use Current Window's Size" is greyed out when it would change nothing
        let size = settings.littleWindowSize
        let opensAt = NSMenuItem(title: "New Ones Open at \(Int(size.width)) × \(Int(size.height))", action: nil, keyEquivalent: "")
        opensAt.isEnabled = false
        submenu.addItem(opensAt)
        if let current = currentLittleWindowSize() {
            let use = action("Use Current Window's Size (\(current.width) × \(current.height))", useCurrentLittleWindowSize)
            use.isEnabled = CGSize(width: current.width, height: current.height) != size
            submenu.addItem(use)
        } else {
            let use = NSMenuItem(title: "Use Current Window's Size", action: nil, keyEquivalent: "")
            use.isEnabled = false
            submenu.addItem(use)
        }
        submenu.addItem(.separator())
        submenu.addItem(action("Remember Size After Resizing", checked: settings.remembersResizedSize) { [weak self] in
            guard let self else { return }
            settings.remembersResizedSize.toggle()
            remembersResizedSizeChanged()
        })
        let item = NSMenuItem(title: "Little Window Size", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    /// The standard About panel, with the project link and the not-affiliated line.
    static func showAbout() {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                                                    .paragraphStyle: centered]
        let credits = NSMutableAttributedString(string: "github.com/austindick/little-dia", attributes: small)
        credits.addAttribute(.link, value: URL(string: "https://github.com/austindick/little-dia")!,
                             range: NSRange(location: 0, length: credits.length))
        credits.append(NSAttributedString(string: "\n\nNot affiliated with or endorsed by The Browser Company.", attributes: small))
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private func action(_ title: String, checked: Bool? = nil, _ handler: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: handler)
        if let checked { item.state = checked ? .on : .off }
        return item
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}
