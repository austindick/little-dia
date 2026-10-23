/// "Move to main window": switches you to the browser's main window immediately, while the extension opens the page
/// there; once it reports `littleMoved`, closes the little window. Dia ignores the extension API's window close and
/// focus requests for popups, so the window is closed natively (its close button, through Accessibility) when possible.
@MainActor
public final class MoveToMain {
    private let sendMove: (Int) -> Void
    private let showMainWindow: () -> Void
    private let closeNatively: (Int) -> Bool
    private let closeViaExtension: (Int) -> Void

    public init(sendMove: @escaping (Int) -> Void, showMainWindow: @escaping () -> Void,
                closeNatively: @escaping (Int) -> Bool, closeViaExtension: @escaping (Int) -> Void) {
        self.sendMove = sendMove
        self.showMainWindow = showMainWindow
        self.closeNatively = closeNatively
        self.closeViaExtension = closeViaExtension
    }

    /// The desktop switch animates while the extension moves the page, so it starts first thing.
    public func start(windowId: Int) {
        sendMove(windowId)
        showMainWindow()
    }

    public func handle(_ message: InboundMessage) {
        guard case let .littleMoved(windowId) = message else { return }
        if !closeNatively(windowId) { closeViaExtension(windowId) }
    }
}
