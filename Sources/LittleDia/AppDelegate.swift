import AppKit
import LittleDiaCore
import os
import OSLog

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
    /// Where Dia loads the extension from (a copy of the one bundled in the app).
    private var extensionFolder: URL!
    private var bundledExtensionVersion: String?
    /// The version the running extension last reported.
    private var lastExtensionVersion: String?
    private var reloadPolicy = ExtensionReloadPolicy()
    private var setupWindow: SetupWindowController?
    private var updater: Updater!

    /// Everything is built here rather than in didFinishLaunching, because a link that launched the app is
    /// delivered in between.
    func applicationWillFinishLaunching(_ notification: Notification) {
        settings = UserDefaultsSettings()

        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let ownFolder = applicationSupport.appendingPathComponent("Little Dia", isDirectory: true)
        // Owner-only, like the socket inside it.
        try? FileManager.default.createDirectory(at: ownFolder, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ownFolder.path)
        extensionFolder = ownFolder.appendingPathComponent("Extension", isDirectory: true)
        installBundledExtension()

        server = BridgeServer(socketPath: ownFolder.appendingPathComponent("bridge.sock").path,
                              acceptPeer: PeerVerifier.make(helperPath: Self.helperPath,
                                                            browserRequirement: settings.browser.codeRequirement))
        link = BridgeExtensionLink(server: server)
        link.onEvent = { [weak self] message, bundleID in self?.handle(message, from: bundleID) }
        link.onConnectionsChanged = { [weak self] in
            self?.statusMenu?.refresh()
            self?.reloadProfiles()
            self?.pingExtension()
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
                                  titleBarColor: settings.browser.titleBarColor.map { NSColor($0) } ?? .windowBackgroundColor,
                                  onBack: { [weak self] id in self?.goBack(inLittleWindow: id) },
                                  onCopy: { [weak self] id in self?.copyURL(ofLittleWindow: id) },
                                  onMove: { [weak self] id in self?.moveToMainWindow(id) },
                                  onSendToProfile: { [weak self] id, profile in self?.send(id, toProfile: profile) })
        tracker = LittleWindowTracker(
            onChange: { [weak self] window in
                guard let self else { return }
                if let window {
                    self.overlay.show(window, canGoBack: self.registry.info(for: window.windowId)?.canGoBack ?? false,
                                      primaryScreenHeight: NSScreen.screens.first?.frame.height ?? 0)
                } else {
                    self.overlay.hide()
                }
            },
            onResize: { [weak self] windowId, page in
                guard let self else { return }
                self.settings.rememberSize(page)
                self.logger.notice("little window \(windowId) resized; next ones open at \(page.width)x\(page.height)")
            },
            onSettled: { [weak self] _, chromeHeight in
                guard let self else { return }
                self.settings.rememberChromeHeight(chromeHeight)
                self.logger.notice("measured title bar \(Int(chromeHeight.rounded()))pt")
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
        updater = Updater(settings: settings)
        statusMenu = StatusMenu(settings: settings,
                                status: { [weak self] in self?.setupStatus() ?? .unknown },
                                showSetup: { [weak self] in self?.showSetup() },
                                copyDiagnostics: { [weak self] in self?.copyDiagnostics() },
                                updateOffer: { [weak self] in self?.updater.offer },
                                checkForUpdates: { [weak self] in Task { await self?.updater.check(userInitiated: true) } },
                                installUpdate: { [weak self] offer in Task { await self?.updater.install(offer) } },
                                isUpdating: { [weak self] in self?.updater.state == .installing })
        updater.onChange = { [weak self] in self?.statusMenu?.refresh() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !settings.hasLaunchedBefore {
            SystemIntegration.launchAtLogin = true
            settings.hasLaunchedBefore = true
        }
        updater.startAutomaticChecks()
        // Open the setup window if a step is unfinished. When Dia is running, give its extension time to connect
        // first, so a set-up Mac doesn't flash the window on every launch: a few seconds normally, and up to a minute
        // more (the extension's reconnect alarm) when Dia's files show the extension is installed.
        Task {
            let bundleID = settings.browser.bundleID
            if browserControl.isRunning(bundleID: bundleID),
               !(await link.waitUntilReady(browser: bundleID, timeout: .seconds(5))), loadProfiles() != nil {
                _ = await link.waitUntilReady(browser: bundleID, timeout: .seconds(65))
            }
            let status = setupStatus()
            logger.notice("setup status at launch: \(status.menuLine.text, privacy: .public)")
            if !status.requiredDone { showSetup() }
        }
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
        case let .littleHistory(windowId, canGoBack):
            overlay.setCanGoBack(canGoBack, windowId: windowId)
        case let .littleBounds(_, bounds):
            settings.rememberSize(bounds)
        case let .littleClosed(windowId):
            tracker.untrack(windowId: windowId)
            Task { await focusReturn.handle(message) }
        case .littleMoved:
            Task { await focusReturn.handle(message) }
            moveToMain.handle(message)
        case let .hello(version):
            lastExtensionVersion = version
            checkExtensionVersion(version, browser: bundleID)
        case let .log(text):
            logger.notice("extension: \(text, privacy: .public)")
        default:
            break
        }
    }

    // MARK: Setup

    /// What the setup window and the menu's status line report.
    func setupStatus() -> SetupStatus {
        let bundleID = settings.browser.bundleID
        let profiles = loadProfiles()
        let extensionState: ExtensionState
        if link.isReady(browser: bundleID) {
            extensionState = .connected
        } else if !browserControl.isRunning(bundleID: bundleID), profiles != nil {
            // Dia can't connect while it's closed; its profile files show the extension is there.
            extensionState = .installed
        } else {
            extensionState = .missing
        }
        return SetupStatus(isDefaultBrowser: SystemIntegration.isDefaultBrowser(), extensionState: extensionState,
                           accessibilityGranted: SystemIntegration.isAccessibilityTrusted(prompt: false),
                           browserPinnedToDesktop: SystemIntegration.isBrowserAssignedToDesktop(bundleID),
                           profile: profiles?.current)
    }

    func showSetup() {
        if setupWindow == nil {
            let model = SetupModel(extensionFolder: extensionFolder,
                                   readStatus: { [weak self] in self?.setupStatus() ?? .unknown },
                                   openExtensionsPage: { [weak self] in
                                       await self?.runAppleScript(DiaScript.openTab(url: "chrome://extensions")) ?? false
                                   })
            setupWindow = SetupWindowController(model: model)
        }
        logger.notice("showing the setup window")
        setupWindow?.present()
    }

    // MARK: Diagnostics

    /// Puts versions, setup status and the last hour of this app's log on the clipboard (URLs scrubbed).
    private func copyDiagnostics() {
        let info = Bundle.main.infoDictionary
        let browserVersion = NSWorkspace.shared.urlForApplication(withBundleIdentifier: settings.browser.bundleID)
            .flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }
        let text = Diagnostics.report(appVersion: info?["CFBundleShortVersionString"] as? String ?? "unknown",
                                      extensionVersion: lastExtensionVersion,
                                      macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                                      browserVersion: browserVersion, status: setupStatus(), profiles: loadProfiles(),
                                      chromeHeight: settings.chromeHeight, logLines: recentLogLines())
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let alert = NSAlert()
        alert.messageText = "Diagnostics copied"
        alert.informativeText = "Paste them into a message when you report a problem. Web addresses are left out."
        NSApp.activate()
        alert.runModal()
    }

    private func recentLogLines() -> [String] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return [] }
        let since = store.position(date: Date().addingTimeInterval(-3600))
        let ours = NSPredicate(format: "subsystem == %@", "com.austindick.littledia")
        guard let entries = try? store.getEntries(at: since, matching: ours) else { return [] }
        let time = DateFormatter()
        time.dateFormat = "HH:mm:ss"
        return entries.compactMap { $0 as? OSLogEntryLog }.map { "\(time.string(from: $0.date)) [\($0.category)] \($0.composedMessage)" }
    }

    // MARK: The extension

    /// Copies the extension bundled in the app to the folder Dia loads it from, when that copy is missing or older.
    private func installBundledExtension() {
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("Extension", isDirectory: true) else { return }
        bundledExtensionVersion = ExtensionInstaller.version(ofExtensionAt: bundled)
        do {
            if try ExtensionInstaller.installIfNeeded(bundled: bundled, installed: extensionFolder) {
                logger.notice("installed extension \(self.bundledExtensionVersion ?? "?", privacy: .public) at \(self.extensionFolder.path, privacy: .public)")
            }
        } catch {
            logger.error("installing the extension failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The extension's first hello can be lost before the helper reaches the app, so ask again once connected.
    private func pingExtension() {
        let bundleID = settings.browser.bundleID
        guard link.isReady(browser: bundleID) else { return }
        server.send(.ping, to: bundleID)
    }

    /// After an update, the extension Dia is running is older than the copy just installed: have it reload from disk.
    private func checkExtensionVersion(_ version: String, browser bundleID: String) {
        guard let bundled = bundledExtensionVersion, version != bundled else { return }
        if reloadPolicy.shouldReload(connectedVersion: version, bundledVersion: bundled) {
            logger.notice("extension \(version, privacy: .public) differs from the bundled \(bundled, privacy: .public); asking it to reload")
            server.send(.reload, to: bundleID)
        } else {
            logger.notice("extension \(version, privacy: .public) still differs from the bundled \(bundled, privacy: .public); Dia may be loading it from a folder other than \(self.extensionFolder.path, privacy: .public)")
        }
    }

    // MARK: Title-bar buttons

    private func goBack(inLittleWindow windowId: Int) {
        server.send(.back(windowId: windowId), to: registry.info(for: windowId)?.browserBundleID ?? settings.browser.bundleID)
    }

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
        let profiles = loadProfiles()
        logger.notice("profiles: current=\(profiles?.current ?? "unknown", privacy: .public) others=\(profiles?.others.joined(separator: ", ") ?? "", privacy: .public)")
        overlay.setProfiles(profiles)
    }

    /// The browser's profiles and which one has the extension, read from its files (nil if the extension isn't in any).
    private func loadProfiles() -> BrowserProfiles? {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return settings.browser.userDataDirectory.flatMap {
            BrowserProfiles.load(userDataDirectory: applicationSupport.appendingPathComponent($0))
        }
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
        case let .littleHistory(windowId, canGoBack): return "littleHistory window=\(windowId) canGoBack=\(canGoBack)"
        case let .openFailed(requestId, error): return "openFailed request=\(requestId) \(error)"
        case let .hello(version): return "hello \(version)"
        case .log: return "log"
        case .hostHello: return "hostHello"
        }
    }


    /// The screen the pointer is on, so the little window opens where the user is looking. Nil with no display.
    private static func currentScreen() -> ScreenContext? {
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard let primary = screens.first,
              let screen = screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main ?? screens.first else { return nil }
        return ScreenContext(visibleFrame: screen.visibleFrame, primaryScreenHeight: primary.frame.height)
    }

    private static var helperPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/littledia-host").path
    }

    private func installNativeHostManifests(applicationSupport: URL) {
        let hostPath = Self.helperPath
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
