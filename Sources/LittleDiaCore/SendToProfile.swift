/// "Send to another profile": closes the little window, then opens its page in the chosen profile through Dia's
/// scripting (pages can't move live between profiles; each keeps its own logins, so the page reloads there).
/// If scripting fails (for example the Automation permission was denied), the page opens in the browser normally.
@MainActor
public final class SendToProfile {
    private let urlOf: (Int) -> String?
    private let forget: (Int) -> Void
    private let closeNatively: (Int) -> Bool
    private let closeViaExtension: (Int) -> Void
    private let openInProfile: (String, String) async -> Bool
    private let openNormally: (String) -> Void
    private let settle: Duration

    /// - Parameter settle: pause after closing, so the main window is the browser's front window for the script.
    public init(urlOf: @escaping (Int) -> String?, forget: @escaping (Int) -> Void, closeNatively: @escaping (Int) -> Bool,
                closeViaExtension: @escaping (Int) -> Void, openInProfile: @escaping (String, String) async -> Bool,
                openNormally: @escaping (String) -> Void, settle: Duration = .milliseconds(200)) {
        self.urlOf = urlOf
        self.forget = forget
        self.closeNatively = closeNatively
        self.closeViaExtension = closeViaExtension
        self.openInProfile = openInProfile
        self.openNormally = openNormally
        self.settle = settle
    }

    public func send(windowId: Int, to profile: String) async {
        guard let url = urlOf(windowId) else { return }
        forget(windowId)
        if !closeNatively(windowId) { closeViaExtension(windowId) }
        try? await Task.sleep(for: settle)
        if await !openInProfile(url, profile) { openNormally(url) }
    }
}
