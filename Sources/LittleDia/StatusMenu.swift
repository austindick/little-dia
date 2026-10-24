import AppKit
import LittleDiaCore

/// The menu-bar item. The menu is rebuilt every time it opens so its status lines are current.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let settings: UserDefaultsSettings
    private let link: ExtensionLink
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    init(settings: UserDefaultsSettings, link: ExtensionLink) {
        self.settings = settings
        self.link = link
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
        let browser = settings.browser
        menu.removeAllItems()

        menu.addItem(action("Open Links in Little Windows", checked: settings.isEnabled) { [weak self] in
            guard let self else { return }
            settings.isEnabled.toggle()
        })
        menu.addItem(.separator())

        menu.addItem(status("\(browser.name) Extension: \(link.isReady(browser: browser.bundleID) ? "Connected" : "Not Connected")"))
        if SystemIntegration.isAccessibilityTrusted(prompt: false) {
            menu.addItem(status("Accessibility: Granted"))
        } else {
            menu.addItem(action("Grant Accessibility Access…") {
                _ = SystemIntegration.isAccessibilityTrusted(prompt: true)
                SystemIntegration.openAccessibilitySettings()
            })
        }
        if SystemIntegration.isDefaultBrowser() {
            menu.addItem(status("Default Browser: Little Dia"))
        } else {
            menu.addItem(action("Make Little Dia the Default Browser…") {
                Task { await SystemIntegration.makeDefaultBrowser() }
            })
        }
        if SystemIntegration.isBrowserAssignedToDesktop(browser.bundleID) {
            menu.addItem(status("⚠︎ \(browser.name) is assigned to one desktop — set Dock › Options › Assign To › None"))
        }
        menu.addItem(action("Launch at Login", checked: SystemIntegration.launchAtLogin) {
            SystemIntegration.launchAtLogin.toggle()
        })
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Little Dia", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func status(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
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
