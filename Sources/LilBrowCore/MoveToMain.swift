/// Finishes "Move to main window" once the extension has opened the page as a tab there (`littleMoved`): closes the
/// little window and takes you to the browser. Dia ignores the extension API's window close and focus requests for
/// popups, so the window is closed natively (its close button, through Accessibility) when possible.
@MainActor
public final class MoveToMain {
    private let closeNatively: (Int) -> Bool
    private let closeViaExtension: (Int) -> Void
    private let activateBrowser: () -> Void
    private let settle: Duration

    /// - Parameter settle: pause after closing, so the browser has no window left on this desktop when it is
    ///   activated and macOS switches to its main window.
    public init(closeNatively: @escaping (Int) -> Bool, closeViaExtension: @escaping (Int) -> Void,
                activateBrowser: @escaping () -> Void, settle: Duration = .milliseconds(300)) {
        self.closeNatively = closeNatively
        self.closeViaExtension = closeViaExtension
        self.activateBrowser = activateBrowser
        self.settle = settle
    }

    public func handle(_ message: InboundMessage) async {
        guard case let .littleMoved(windowId) = message else { return }
        if !closeNatively(windowId) { closeViaExtension(windowId) }
        try? await Task.sleep(for: settle)
        activateBrowser()
    }
}
