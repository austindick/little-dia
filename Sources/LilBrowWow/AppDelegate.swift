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
            browserIsFrontmost: { [settings] in NSWorkspace.shared.frontmostApplication?.bundleIdentifier == settings?.browser.bundleID },
            browserHasWindowOnThisDesktop: { [browserControl, settings] in
                guard let bundleID = settings?.browser.bundleID else { return false }
                return browserControl.onScreenWindows(bundleID: bundleID).contains { $0.frame.width > 200 && $0.frame.height > 200 }
            },
            activate: { $0.activate() })
        installNativeHostManifests(applicationSupport: applicationSupport)
        statusMenu = StatusMenu(settings: settings, link: link)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // The app the link was clicked in; focus goes back there when the little window closes.
        let cameFrom = NSWorkspace.shared.frontmostApplication.flatMap { app in
            app.bundleIdentifier == settings.browser.bundleID || app == NSRunningApplication.current ? nil : app
        }
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
        case let .littleBounds(_, bounds):
            settings.rememberSize(bounds)
        case .littleClosed:
            // Give the window server a moment to take the closed window off screen before looking.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.focusReturn.handle(message) }
        case .littleMoved:
            focusReturn.handle(message)
        default:
            break
        }
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
