/// When a little window closes, hands focus back to the app you clicked the link in (Slack, Mail, …), the way
/// closing Little Arc did. Skipped when the page moved to the main window, when you've already switched apps, or
/// when another browser window is still on this desktop.
@MainActor
public final class FocusReturn<App> {
    private let browserIsFrontmost: () -> Bool
    private let browserHasWindowOnThisDesktop: () -> Bool
    private let activate: (App) -> Void
    private var cameFrom: [Int: App] = [:]

    public init(browserIsFrontmost: @escaping () -> Bool, browserHasWindowOnThisDesktop: @escaping () -> Bool,
                activate: @escaping (App) -> Void) {
        self.browserIsFrontmost = browserIsFrontmost
        self.browserHasWindowOnThisDesktop = browserHasWindowOnThisDesktop
        self.activate = activate
    }

    public func littleWindowOpened(_ windowId: Int, cameFrom app: App?) {
        cameFrom[windowId] = app
    }

    public func handle(_ message: InboundMessage) {
        switch message {
        case let .littleMoved(windowId):
            cameFrom.removeValue(forKey: windowId)
        case let .littleClosed(windowId):
            guard let app = cameFrom.removeValue(forKey: windowId),
                  browserIsFrontmost(), !browserHasWindowOnThisDesktop() else { return }
            activate(app)
        default:
            break
        }
    }
}
