import AppKit
import LittleDiaCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.austindick.littledia", category: "app")
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
    private var sendToProfile: SendToProfile!

    /// Everything is built here rather than in didFinishLaunching, because a link that launched the app is
    /// delivered in between.
    func applicationWillFinishLaunching(_ notification: Notification) {
        settings = UserDefaultsSettings()

        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let ownFolder = applicationSupport.appendingPathComponent("Little Dia", isDirectory: true)
        try? FileManager.default.createDirectory(at: ownFolder, withIntermediateDirectories: true)

        server = BridgeServer(socketPath: ownFolder.appendingPathComponent("bridge.sock").path)
        link = BridgeExtensionLink(server: server)
        link.onEvent = { [weak self] message, bundleID in self?.handle(message, from: bundleID) }
        link.onConnectionsChanged = { [weak self] in
            self?.statusMenu?.refresh()
            self?.reloadProfiles()
        }
        do {
            try server.start()
        } catch {
            logger.error("bridge failed to start: \(String(describing: error), privacy: .public)")
        }

        router = LinkRouter(settings: settings, link: link, browser: browserControl, screen: Self.currentScreen)
        router.onAbandon = { [weak self] windowId in _ = self?.tracker.close(windowId: windowId) }
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
                                  onMove: { [weak self] id in self?.moveToMainWindow(id) },
                                  onSendToProfile: { [weak self] id, profile in self?.send(id, toProfile: profile) })
        tracker = LittleWindowTracker(
            onChange: { [weak self] window in
                guard let self else { return }
                if let window {
                    self.overlay.show(window, primaryScreenHeight: NSScreen.screens.first?.frame.height ?? 0)
                } else {
                    self.overlay.hide()
                }
            },
            onResize: { [weak self] windowId, page in
                guard let self else { return }
                self.settings.rememberSize(page)
                self.logger.notice("little window \(windowId) resized; next ones open at \(page.width)x\(page.height)")
            })
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
        sendToProfile = SendToProfile(
            urlOf: { [weak self] id in self?.registry.info(for: id)?.url },
            forget: { [weak self] id in self?.focusReturn.forget(id) },
            closeNatively: { [weak self] id in self?.tracker.close(windowId: id) ?? false },
            closeViaExtension: { [weak self] id in
                guard let self else { return }
                self.server.send(.close(windowId: id), to: self.registry.info(for: id)?.browserBundleID ?? self.settings.browser.bundleID)
            },
            openInProfile: { [weak self] url, profile in
                await self?.runAppleScript(DiaScript.openInProfile(url: url, profile: profile)) ?? false
            },
            openNormally: { [weak self] url in
                guard let self, let parsed = URL(string: url) else { return }
                self.browserControl.openNormally(parsed, bundleID: self.settings.browser.bundleID)
            })
        reloadProfiles()
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

    private func writeToPasteboard(_ url: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        if overlay.isVisible { overlay.flashCopied() }
    }

    private func send(_ windowId: Int, toProfile profile: String) {
        overlay.hide()
        tracker.untrack(windowId: windowId)
        Task { await sendToProfile.send(windowId: windowId, to: profile) }
    }

    /// Profile names for the Move button, read from the browser's files (they can change while the app runs).
    private func reloadProfiles() {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let profiles = settings.browser.userDataDirectory.flatMap {
            BrowserProfiles.load(userDataDirectory: applicationSupport.appendingPathComponent($0))
        }
        logger.notice("profiles: current=\(profiles?.current ?? "unknown", privacy: .public) others=\(profiles?.others.joined(separator: ", ") ?? "", privacy: .public)")
        overlay.setProfiles(profiles)
    }

    /// Runs an AppleScript with `osascript`, so the main thread stays free (the first run may wait on the
    /// "Little Dia wants to control Dia" permission prompt).
    private func runAppleScript(_ source: String) async -> Bool {
        let logger = self.logger
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = Pipe()
            process.terminationHandler = { finished in
                let ok = finished.terminationStatus == 0
                if !ok {
                    let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    logger.error("AppleScript failed: \(message, privacy: .public)")
                }
                continuation.resume(returning: ok)
            }
            do {
                try process.run()
            } catch {
                logger.error("could not run osascript: \(error.localizedDescription, privacy: .public)")
                continuation.resume(returning: false)
            }
        }
    }

    private func moveToMainWindow(_ windowId: Int) {
        overlay.hide()
        focusReturn.forget(windowId)
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
        let hostPath = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/littledia-host").path
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
