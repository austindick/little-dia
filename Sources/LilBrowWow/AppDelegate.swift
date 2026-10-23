import AppKit
import LilBrowCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.lilbrowwow", category: "app")
    private let browserControl = BrowserControlImpl()
    private let registry = LittleWindowRegistry()
    private var settings: UserDefaultsSettings!
    private var server: BridgeServer!
    private var link: BridgeExtensionLink!
    private var router: LinkRouter!
    private var statusMenu: StatusMenu!
    private var focusReturn: FocusReturn<NSRunningApplication>!
    private var tracker: LittleWindowTracker!
    private var overlay: TitleBarOverlay!
    private var moveToMain: MoveToMain!

    /// Everything is built here rather than in didFinishLaunching, because a link that launched the app is
    /// delivered in between.
    func applicationWillFinishLaunching(_ notification: Notification) {
        settings = UserDefaultsSettings()

        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let ownFolder = applicationSupport.appendingPathComponent("LilBrowWow", isDirectory: true)
        try? FileManager.default.createDirectory(at: ownFolder, withIntermediateDirectories: true)

        server = BridgeServer(socketPath: ownFolder.appendingPathComponent("bridge.sock").path)
        link = BridgeExtensionLink(server: server)
        link.onEvent = { [weak self] message, bundleID in self?.handle(message, from: bundleID) }
        link.onConnectionsChanged = { [weak self] in self?.statusMenu?.refresh() }
        do {
            try server.start()
        } catch {
            logger.error("bridge failed to start: \(String(describing: error), privacy: .public)")
        }

        router = LinkRouter(settings: settings, link: link, browser: browserControl, screen: Self.currentScreen)
        focusReturn = FocusReturn(
            isOwnOrBrowser: { [settings] app in
                app == NSRunningApplication.current || app.bundleIdentifier == settings?.browser.bundleID
            },
            browserIsFrontmost: { [settings] in NSWorkspace.shared.frontmostApplication?.bundleIdentifier == settings?.browser.bundleID },
            browserHasWindowOnThisDesktop: { [browserControl, settings] in
                guard let bundleID = settings?.browser.bundleID else { return false }
                return browserControl.onScreenWindows(bundleID: bundleID).contains { $0.frame.width > 200 && $0.frame.height > 200 }
            },
            activate: { $0.activate() })
        focusReturn.onDecision = { [logger, browserControl, settings] reason in
            let windows = browserControl.onScreenWindows(bundleID: settings?.browser.bundleID ?? "")
                .map { "#\($0.id) \(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))x\(Int($0.frame.height))" }
            let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
            logger.notice("focus return: \(reason, privacy: .public); frontmost=\(front, privacy: .public) browser windows here=[\(windows.joined(separator: "; "), privacy: .public)]")
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication { focusReturn.appActivated(frontmost) }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.focusReturn.appActivated(app) }
        }
        overlay = TitleBarOverlay(browserName: settings.browser.name,
                                  onCopy: { [weak self] id in self?.copyURL(ofLittleWindow: id) },
                                  onMove: { [weak self] id in self?.moveToMainWindow(id) })
        tracker = LittleWindowTracker { [weak self] window in
            guard let self else { return }
            if let window {
                self.overlay.show(window, primaryScreenHeight: NSScreen.screens.first?.frame.height ?? 0)
            } else {
                self.overlay.hide()
            }
        }
        moveToMain = MoveToMain(
            sendMove: { [weak self] id in
                guard let self else { return }
                self.server.send(.move(windowId: id), to: self.registry.info(for: id)?.browserBundleID ?? self.settings.browser.bundleID)
            },
            showMainWindow: { [weak self] in
                guard let self else { return }
                self.browserControl.showMainWindow(bundleID: self.settings.browser.bundleID)
            },
            closeNatively: { [weak self] id in self?.tracker.close(windowId: id) ?? false },
            closeViaExtension: { [weak self] id in
                guard let self else { return }
                self.server.send(.close(windowId: id), to: self.registry.info(for: id)?.browserBundleID ?? self.settings.browser.bundleID)
            })
        installNativeHostManifests(applicationSupport: applicationSupport)
        statusMenu = StatusMenu(settings: settings, link: link)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // The app the link was clicked in; focus goes back there when the little window closes.
        let cameFrom = focusReturn.origin(frontmost: NSWorkspace.shared.frontmostApplication)
        logger.notice("link arrived; frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?", privacy: .public) cameFrom=\(cameFrom?.localizedName ?? "none", privacy: .public)")
        Task {
            for url in urls {
                let outcome = await router.route(url)
                logger.notice("routed \(url.absoluteString, privacy: .private) → \(String(describing: outcome), privacy: .public)")
                if case let .little(windowId) = outcome { focusReturn.littleWindowOpened(windowId, cameFrom: cameFrom) }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    private func handle(_ message: InboundMessage, from bundleID: String) {
        logger.notice("event \(Self.describe(message), privacy: .public)")
        registry.apply(message, from: bundleID)
        switch message {
        case let .opened(_, windowId, _, bounds):
            if let pid = server.browserPID(for: bundleID) {
                Task { _ = await tracker.track(windowId: windowId, bounds: bounds, browserPID: pid) }
            }
        case let .littleBounds(_, bounds):
            settings.rememberSize(bounds)
        case let .littleClosed(windowId):
            tracker.untrack(windowId: windowId)
            Task { await focusReturn.handle(message) }
        case .littleMoved:
            Task { await focusReturn.handle(message) }
            moveToMain.handle(message)
        case let .log(text):
            logger.notice("extension: \(text, privacy: .public)")
        case let .copy(url):
            writeToPasteboard(url)
        default:
            break
        }
    }

    // MARK: Title-bar buttons

    private func copyURL(ofLittleWindow windowId: Int) {
        guard let url = registry.info(for: windowId)?.url else { return }
        writeToPasteboard(url)
    }

    private func writeToPasteboard(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        if overlay.isVisible { overlay.flashCopied() }
    }

    private func moveToMainWindow(_ windowId: Int) {
        overlay.hide()
        moveToMain.start(windowId: windowId)
    }

    private static func describe(_ message: InboundMessage) -> String {
        switch message {
        case let .opened(requestId, windowId, _, b): return "opened window=\(windowId) request=\(requestId ?? "-") bounds=\(b.left),\(b.top) \(b.width)x\(b.height)"
        case let .littleBounds(windowId, b): return "littleBounds window=\(windowId) \(b.left),\(b.top) \(b.width)x\(b.height)"
        case let .littleClosed(windowId): return "littleClosed window=\(windowId)"
        case let .littleMoved(windowId): return "littleMoved window=\(windowId)"
        case let .littleURL(windowId, _): return "littleURL window=\(windowId)"
        case let .openFailed(requestId, error): return "openFailed request=\(requestId) \(error)"
        case let .hello(version): return "hello \(version)"
        case .copy: return "copy"
        case .log: return "log"
        case .hostHello: return "hostHello"
        }
    }


    /// The screen the pointer is on, so the little window opens where the user is looking.
    private static func currentScreen() -> ScreenContext {
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let screen = screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? screens[0]
        return ScreenContext(visibleFrame: screen.visibleFrame, primaryScreenHeight: screens[0].frame.height)
    }

    private func installNativeHostManifests(applicationSupport: URL) {
        let hostPath = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/lilbrow-host").path
        for adapter in BrowserAdapter.all where NSWorkspace.shared.urlForApplication(withBundleIdentifier: adapter.bundleID) != nil {
            do {
                let files = try NativeHostManifest.install(hostExecutablePath: hostPath, adapter: adapter, applicationSupport: applicationSupport)
                logger.notice("installed native host manifest for \(adapter.name, privacy: .public): \(files.map(\.path).joined(separator: ", "), privacy: .public)")
            } catch {
                logger.error("installing native host manifest for \(adapter.name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
