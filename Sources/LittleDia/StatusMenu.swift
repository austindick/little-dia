import AppKit
import LittleDiaCore

/// The menu-bar item. The menu is rebuilt every time it opens so its status line is current: "All set · Work", or the
/// first thing that needs fixing, which opens the setup window when clicked.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let settings: UserDefaultsSettings
    private let status: () -> SetupStatus
    private let showSetup: () -> Void
    private let copyDiagnostics: () -> Void
    private let updateOffer: () -> UpdateOffer?
    private let checkForUpdates: () -> Void
    private let installUpdate: (UpdateOffer) -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    init(settings: UserDefaultsSettings, status: @escaping () -> SetupStatus, showSetup: @escaping () -> Void,
         copyDiagnostics: @escaping () -> Void, updateOffer: @escaping () -> UpdateOffer?,
         checkForUpdates: @escaping () -> Void, installUpdate: @escaping (UpdateOffer) -> Void) {
        self.settings = settings
        self.status = status
        self.showSetup = showSetup
        self.copyDiagnostics = copyDiagnostics
        self.updateOffer = updateOffer
        self.checkForUpdates = checkForUpdates
        self.installUpdate = installUpdate
        super.init()
        let image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Little Dia")
        image?.isTemplate = true
        statusItem.button?.image = image
        menu.delegate = self
        statusItem.menu = menu
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    func refresh() {
        menu.removeAllItems()

        menu.addItem(action("Open Links in Little Windows", checked: settings.isEnabled) { [weak self] in
            guard let self else { return }
            settings.isEnabled.toggle()
        })
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

        if let offer = updateOffer() {
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
