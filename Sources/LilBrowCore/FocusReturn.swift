/// When a little window closes, hands focus back to the app you clicked the link in (Slack, Mail, …), the way
/// closing Little Arc did. Skipped when the page moved to the main window, when you've already switched apps, or
/// when another browser window is still on this desktop.
@MainActor
public final class FocusReturn<App> {
    private let isOwnOrBrowser: (App) -> Bool
    private let browserIsFrontmost: () -> Bool
    private let browserHasWindowOnThisDesktop: () -> Bool
    private let activate: (App) -> Void
    private let settle: Duration
    private let pollInterval: Duration
    private var cameFrom: [Int: App] = [:]
    private var lastOtherApp: App?
    /// Why focus did or didn't go back, for the log.
    public var onDecision: ((String) -> Void)?

    /// - Parameters:
    ///   - settle: how long to wait for the closed window to leave the screen (its close animation).
    public init(isOwnOrBrowser: @escaping (App) -> Bool, browserIsFrontmost: @escaping () -> Bool,
                browserHasWindowOnThisDesktop: @escaping () -> Bool, activate: @escaping (App) -> Void,
                settle: Duration = .seconds(1), pollInterval: Duration = .milliseconds(50)) {
        self.isOwnOrBrowser = isOwnOrBrowser
        self.browserIsFrontmost = browserIsFrontmost
        self.browserHasWindowOnThisDesktop = browserHasWindowOnThisDesktop
        self.activate = activate
        self.settle = settle
        self.pollInterval = pollInterval
    }

    /// Call on every app activation, so the origin is known even after macOS activates this app for the link.
    public func appActivated(_ app: App) {
        if !isOwnOrBrowser(app) { lastOtherApp = app }
    }

    /// The app a link was clicked in.
    public func origin(frontmost: App?) -> App? {
        if let frontmost, !isOwnOrBrowser(frontmost) { return frontmost }
        return lastOtherApp
    }

    public func littleWindowOpened(_ windowId: Int, cameFrom app: App?) {
        cameFrom[windowId] = app
    }

    public func handle(_ message: InboundMessage) async {
        switch message {
        case let .littleMoved(windowId):
            cameFrom.removeValue(forKey: windowId)
        case let .littleClosed(windowId):
            guard let app = cameFrom.removeValue(forKey: windowId) else { return decided("window \(windowId): no app to return to") }
            guard await closedWindowLeftScreen() else { return decided("window \(windowId): browser still has a window here") }
            guard browserIsFrontmost() else { return decided("window \(windowId): browser no longer frontmost") }
            decided("window \(windowId): returning focus to \(app)")
            activate(app)
        default:
            break
        }
    }

    private func closedWindowLeftScreen() async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + settle
        while browserHasWindowOnThisDesktop() {
            if clock.now >= deadline { return false }
            try? await Task.sleep(for: pollInterval)
        }
        return true
    }

    private func decided(_ reason: String) {
        onDecision?(reason)
    }
}
