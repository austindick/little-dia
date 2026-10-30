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
    private var profiles: BrowserProfiles?
    /// The profile Dia's main window was showing when last asked (nil: unknown), and whether Dia is being asked now.
    private var mainWindowProfile: String?
    private var askingMainWindowProfile = false
    /// The profile each bridge connection's extension runs in, from the token in its hello.
    private var connectionProfiles: [Int: String] = [:]

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
        link.onEvent = { [weak self] message, bundleID, connection in self?.handle(message, from: bundleID, connection: connection) }
        link.onConnectionsChanged = { [weak self] in
            guard let self else { return }
            let ready = Set(self.server.readyConnections(for: self.settings.browser.bundleID))
            self.connectionProfiles = self.connectionProfiles.filter { ready.contains($0.key) }
            self.statusMenu?.refresh()
            self.reloadProfiles()
            self.pingExtension()
            self.refreshMainWindowProfile()
        }
        // A link opens in the profile Dia's main window is showing, when that profile has the extension.
        link.chooseConnection = { [weak self] ready in
            guard let self else { return nil }
            return ProfileRouting.connection(for: self.mainWindowProfile, ready: ready, profileOf: self.connectionProfiles)
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
        // Dia's profile can only change while Dia is in front, so what it shows as you leave it holds for the links
        // you click elsewhere.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated {
                if app.bundleIdentifier == self?.settings.browser.bundleID { self?.refreshMainWindowProfile() }
            }
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
                    // The buttons hide whenever the little window loses focus, so the main window may have changed
                    // profile since they were last shown.
                    if !self.overlay.isVisible { self.refreshMainWindowProfile() }
                    let info = self.registry.info(for: window.windowId)
                    self.overlay.show(window, profile: info?.connection.flatMap { self.connectionProfiles[$0] },
                                      canGoBack: info?.canGoBack ?? false,
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
                self.send(.move(windowId: id), toLittleWindow: id)
            },
            showMainWindow: { [weak self] in
                guard let self else { return }
                self.browserControl.showMainWindow(bundleID: self.settings.browser.bundleID)
            },
            closeNatively: { [weak self] id in self?.tracker.close(windowId: id) ?? false },
            closeViaExtension: { [weak self] id in self?.send(.close(windowId: id), toLittleWindow: id) })
        sendToProfile = SendToProfile(
            urlOf: { [weak self] id in self?.registry.info(for: id)?.url },
            forget: { [weak self] id in self?.focusReturn.forget(id) },
            closeNatively: { [weak self] id in self?.tracker.close(windowId: id) ?? false },
            closeViaExtension: { [weak self] id in self?.send(.close(windowId: id), toLittleWindow: id) },
            openInProfile: { [weak self] url, profile in
                await self?.runAppleScript(DiaScript.openInProfile(url: url, profile: profile)) != nil
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

    private func handle(_ message: InboundMessage, from bundleID: String, connection: Int) {
        logger.notice("event \(Self.describe(message), privacy: .public) (connection \(connection))")
        registry.apply(message, from: bundleID, connection: connection)
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
        case let .hello(version, token):
            lastExtensionVersion = version
            noteProfile(ofConnection: connection, token: token)
            checkExtensionVersion(version, connection: connection)
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
                           profile: profiles.map { ListFormatter.localizedString(byJoining: $0.withExtension) })
    }

    func showSetup() {
        if setupWindow == nil {
            let model = SetupModel(extensionFolder: extensionFolder,
                                   readStatus: { [weak self] in self?.setupStatus() ?? .unknown },
                                   openExtensionsPage: { [weak self] in
                                       await self?.runAppleScript(DiaScript.openTab(url: "chrome://extensions")) != nil
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

    /// The extension's first hello can be lost before the helper reaches the app, so ask again once connected
    /// (each profile's copy has its own connection).
    private func pingExtension() {
        for connection in server.readyConnections(for: settings.browser.bundleID) where connectionProfiles[connection] == nil {
            server.send(.ping, toConnection: connection)
        }
    }

    /// Works out which profile a connection's extension runs in, from the token it keeps in its profile's storage.
    private func noteProfile(ofConnection connection: Int, token: String?) {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        guard let token, let userData = settings.browser.userDataDirectory.map({ applicationSupport.appendingPathComponent($0) }) else {
            logger.notice("connection \(connection): the extension didn't say which profile it's in")
            return
        }
        let profile = BrowserProfiles.profile(holdingToken: token, userDataDirectory: userData)
        connectionProfiles[connection] = profile
        logger.notice("connection \(connection): extension in \(profile ?? "an unknown profile", privacy: .public)")
    }

    /// Sends to the profile's extension that opened the little window (the newest connection if that's unknown).
    private func send(_ message: OutboundMessage, toLittleWindow windowId: Int) {
        if let connection = registry.info(for: windowId)?.connection, server.send(message, toConnection: connection) { return }
        server.send(message, to: settings.browser.bundleID)
    }

    /// After an update, the extension Dia is running is older than the copy just installed: have it reload from disk.
    private func checkExtensionVersion(_ version: String, connection: Int) {
        guard let bundled = bundledExtensionVersion, version != bundled else { return }
        if reloadPolicy.shouldReload(connectedVersion: version, bundledVersion: bundled, copies: profiles?.withExtension.count ?? 1) {
            logger.notice("extension \(version, privacy: .public) differs from the bundled \(bundled, privacy: .public); asking it to reload")
            server.send(.reload, toConnection: connection)
        } else {
            logger.notice("extension \(version, privacy: .public) still differs from the bundled \(bundled, privacy: .public); Dia may be loading it from a folder other than \(self.extensionFolder.path, privacy: .public)")
        }
    }

    // MARK: Title-bar buttons

    private func goBack(inLittleWindow windowId: Int) {
        send(.back(windowId: windowId), toLittleWindow: windowId)
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
        self.profiles = profiles
        logger.notice("profiles: current=\(profiles?.current ?? "unknown", privacy: .public) others=\(profiles?.others.joined(separator: ", ") ?? "", privacy: .public)")
        overlay.setProfiles(profiles)
    }

    /// Asks Dia which profile its main window is showing, so "Open in" names that one. Only with more than one
    /// profile, and one question at a time. The first may wait on the "Little Dia wants to control Dia" prompt; without
    /// that permission the button keeps the extension's profile.
    private func refreshMainWindowProfile() {
        guard !askingMainWindowProfile, !(profiles?.others.isEmpty ?? true) else { return }
        askingMainWindowProfile = true
        Task {
            let answer = await runAppleScript(DiaScript.activeProfileName, logFailure: false)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let name = answer?.isEmpty == false ? answer : nil
            askingMainWindowProfile = false
            if name != mainWindowProfile {
                logger.notice("main window profile: \(name ?? "unknown (Dia didn't answer)", privacy: .public)")
            }
            mainWindowProfile = name
            overlay.setActiveProfile(name)
        }
    }

    /// The browser's profiles and which one has the extension, read from its files (nil if the extension isn't in any).
    private func loadProfiles() -> BrowserProfiles? {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return settings.browser.userDataDirectory.flatMap {
            BrowserProfiles.load(userDataDirectory: applicationSupport.appendingPathComponent($0))
        }
    }

    /// Runs an AppleScript with `osascript`, so the main thread stays free (the first run may wait on the
    /// "Little Dia wants to control Dia" permission prompt). Returns what the script printed, or nil if it failed.
    private func runAppleScript(_ source: String, logFailure: Bool = true) async -> String? {
        let logger = self.logger
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let errors = Pipe()
            let output = Pipe()
            process.standardError = errors
            process.standardOutput = output
            process.terminationHandler = { finished in
                guard finished.terminationStatus == 0 else {
                    if logFailure {
                        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                        logger.error("AppleScript failed: \(message, privacy: .public)")
                    }
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
            }
            do {
                try process.run()
            } catch {
                logger.error("could not run osascript: \(error.localizedDescription, privacy: .public)")
                continuation.resume(returning: nil)
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
        case let .hello(version, _): return "hello \(version)"
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
